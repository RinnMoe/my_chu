/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 ("the License");
 *
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { ble, constant } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import access from '@ohos.bluetooth.access';
import BleUtils from './BleUtils';
import TextUtils from './TextUtils';
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/**
 * 蓝牙连接管理器。
 *
 * 集中管理设备连接/断开/适配器状态，持有 connectedDevices/currentlyConnectingDevices/
 * autoConnected 三个设备表，以及 connectStateChanged/stateChangeCallback 两个回调
 * （成员属性箭头函数，保证 ble/access.on/off 传引用时 this 不丢失）。
 *
 * 跨 Manager 共享状态经 plugin 中介访问：
 *  - mtu/writeChr/writeDesc/deviceServices → plugin.gattCache
 *  - bondingDevices → plugin.bondManager
 *  - characteristicChangeCallbacks → plugin.notifyManager
 *  - 权限检测/申请 → plugin.permissionManager
 *
 * 方法体来源：1.33.5 FlutterBluePlusOhosPlugin（handleConnect/handleDisconnect/
 * connectStateChanged/disconnectAllDevices/releaseGatt/closeAllGattClients/
 * isConnecting/isConnected/waitIfBonding/onReceiveEvent），适配 this.X → this.plugin.X。
 */
export default class BleConnectionManager {
  /** 插件引用，用于访问 channel/gattCache/bondManager/permissionManager 等共享状态。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /** 已连接设备（remoteId -> GattClientDevice）。 */
  public connectedDevices: Map<string, ble.GattClientDevice> = new Map<string, ble.GattClientDevice>();
  /** 正在连接的设备。 */
  public currentlyConnectingDevices: Map<string, ble.GattClientDevice> = new Map<string, ble.GattClientDevice>();
  /** 自动重连设备集合。 */
  public autoConnected: Map<string, ble.GattClientDevice> = new Map<string, ble.GattClientDevice>();
  /** 当前操作的 GattClientDevice（单设备场景占位）。 */
  public clientDevice: ble.GattClientDevice | null = null;
  /** 当前操作的 remoteId（单设备场景占位）。 */
  public remoteId: string | null = null;
  /** 用户主动断连中的设备集合：disconnect() 调用后、connectStateChanged 回调到达前标记,
   *  使回调能区分主动断连(reason=23789258)与系统断连(reason=0),避免已连接设备主动断连被误报为系统断连。 */
  private userDisconnectingDevices: Set<string> = new Set<string>();

  /**
   * stateChange 订阅状态标志位：access.on('stateChange') 注册后置 true，off 后置 false。
   * 追踪订阅状态，使 on/off 能幂等执行并避免无效 off（off 未订阅监听会抛异常/产生噪音）。
   */
  public stateChangeSubscribed: boolean = false;

  /**
   * access.on('stateChange') 回调：适配器开关变化。
   * 成员属性箭头函数，保证 access.on/off 传引用时 this 不丢失，且便于注册前精确 off。
   */
  public stateChangeCallback: (data: access.BluetoothState) => void =
    (data: access.BluetoothState) => {
      this.onReceiveEvent(data);
    };

  /**
   * ble.on('BLEConnectionStateChange') 回调：设备连接/断开状态变化。
   *
   * 仅使用回调自带的 deviceId 与 per-device Map，不依赖任何共享单实例变量，
   * 避免多设备并发时引用错误设备。
   * 断连时释放对应的 GattClientDevice 并取消其设备级监听。
   * 保持成员属性箭头函数形式，ble.on/off 传引用时 this 不丢失。
   */
  public connectStateChanged = (state: ble.BLEConnectionChangeState): void => {
    if (state.state !== constant.ProfileConnectionState.STATE_CONNECTED &&
      state.state !== constant.ProfileConnectionState.STATE_DISCONNECTED) {
      return;
    }
    // 仅使用回调自带的 deviceId,不再 fallback 到共享单实例,避免多设备并发引用错误。
    let deviceId: string = state.deviceId as string;
    // 记录状态变化前该设备是否处于 connecting 态（须在 handle* 删除 Map 条目之前取值）。
    // 用于区分「连接中即断开 = 连接失败」与「已连接后自发断连」两种场景，
    // 进而决定 disconnect_reason_code/string（emitConnectionStateChanged）。
    let wasConnecting: boolean = this.currentlyConnectingDevices.has(deviceId);
    if (state.state === constant.ProfileConnectionState.STATE_CONNECTED) {
      this.handleConnected(deviceId);
    } else {
      this.handleDisconnected(deviceId);
    }
    this.emitConnectionStateChanged(deviceId, state.state, wasConnecting);
  };

  /**
   * 判断设备是否为用户主动断连并清除标记。
   * @param deviceId 设备 ID。
   * @returns true 表示该断连由用户主动发起(disconnect() 调用触发)。
   */
  private consumeUserDisconnect(deviceId: string): boolean {
    if (this.userDisconnectingDevices.has(deviceId)) {
      this.userDisconnectingDevices.delete(deviceId);
      return true;
    }
    return false;
  }

  /**
   * connectStateChanged 的 CONNECTED 分支:从正在连接表取出 gatt 入已连接表,置默认 MTU=23。
   */
  private handleConnected(deviceId: string): void {
    // 连接成功:从正在连接表取出 gatt。取不到说明 connect 未走标准流程,记录并跳过。
    let gattConnected: ble.GattClientDevice | undefined = this.currentlyConnectingDevices.get(deviceId);
    if (gattConnected === null || gattConnected === undefined) {
      BleUtils.log(hilog.LogLevel.WARN, 'connectStateChanged: device not found in connecting table: ' + deviceId);
      return;
    }
    this.connectedDevices.set(deviceId, gattConnected);
    this.currentlyConnectingDevices.delete(deviceId);
    this.plugin.gattCache.mtuMap.set(deviceId, 23);
    // 连接即注册 BLECharacteristicChange 回调(对齐 Android BluetoothGattCallback),
    // 使 setNotifyValue 开启的通知能收到特征变化事件;readCharacteristic 不再单独注册,避免双重监听。
    this.plugin.notifyManager.registerCharacteristicChangeCallback(deviceId, gattConnected);
  }

  /**
   * connectStateChanged 的 DISCONNECTED 分支:从各表删除设备,
   * 非自动连接设备执行 off 监听器 + close 释放(自动连接设备保留以便重连)。
   */
  private handleDisconnected(deviceId: string): void {
    // 先取出 gatt 实例,再 delete,否则 delete 后 get 永远返回 undefined。
    let gattToRelease: ble.GattClientDevice | undefined = this.connectedDevices.get(deviceId);
    if (gattToRelease === null || gattToRelease === undefined) {
      gattToRelease = this.autoConnected.get(deviceId);
    }
    this.connectedDevices.delete(deviceId);
    this.currentlyConnectingDevices.delete(deviceId);
    // 断连时释放 BONDING 态创建的 GattClientDevice(仅 delete 不 close 会泄漏原生资源),
    // clearBondingState 内部先 close 再 delete,与 closeAllGattClients 的释放语义一致。
    this.plugin.bondManager.clearBondingState(deviceId);
    // 清理该设备的 GATT 缓存(mtuMap + deviceServicesMap),避免重连后用旧服务树解析通知数据。
    this.plugin.gattCache.clearForDevice(deviceId);
    // 注销 NotifyManager 注册的 BLECharacteristicChange 回调,打破闭包(this.plugin→gatt)循环引用。
    // 自动连接设备保留 gatt 以便重连,但回调引用仍需注销(重连后由 handleConnected 重新注册)。
    if (gattToRelease !== null && gattToRelease !== undefined) {
      this.plugin.notifyManager.unregisterCharacteristicChangeCallback(deviceId, gattToRelease);
    }
    // 仅非自动连接设备才关闭(自动连接设备保留以便重连)。
    if (!this.autoConnected.has(deviceId)) {
      this.releaseDisconnectedGatt(deviceId, gattToRelease);
    }
  }

  /**
   * 释放断连设备的 GattClientDevice:取消设备级监听器 + close。
   * gattToRelease 为 undefined 时跳过(设备已不在任何表中)。
   */
  private releaseDisconnectedGatt(deviceId: string, gattToRelease: ble.GattClientDevice | undefined): void {
    if (gattToRelease === null || gattToRelease === undefined) {
      return;
    }
    try {
      gattToRelease.off('BLEConnectionStateChange', this.connectStateChanged);
      gattToRelease.off('BLECharacteristicChange');
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'connectStateChanged off listeners: ' + (e as BusinessError)?.message);
    }
    try {
      gattToRelease.close();
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'connectStateChanged gatt close: ' + (e as BusinessError)?.message);
    }
  }

  /**
   * 回传 OnConnectionStateChanged 给指定设备(连接/断连状态)。
   * 断连时区分主动断连(reason=23789258,由 disconnect() 标记)与系统断连(reason=0)。
   * OHOS BLEConnectionChangeState 不暴露真实 HCI 状态码,系统断连统一用 0(GATT_SUCCESS),
   * 主动断连用 23789258(自定义用户取消码),与 Android/iOS 的契约保持一致。
   *
   * @param wasConnecting - 状态变化前设备是否处于 connecting 态。true 表示连接中即断开
   *   （连接失败,如拒绝配对/超时/远端拒绝）,回传 code=1 + 'UNKNOWN_HCI_ERROR (1)',
   *   false 表示已连接后自发断连,回传 code=0 + 'unknown'
   */
  private emitConnectionStateChanged(deviceId: string, state: number, wasConnecting: boolean): void {
    let response: Map<string, string | number> = new Map<string, string | number>();
    let connectState: number = BleUtils.buildConnectionStateEnum(state);
    response.set('remote_id', deviceId);
    response.set('connection_state', connectState);
    if (state !== constant.ProfileConnectionState.STATE_CONNECTED) {
      // 消费主动断连标记:有标记则为用户主动断开(23789258),无标记为系统侧断连。
      if (this.consumeUserDisconnect(deviceId)) {
        // 主动断开(23789258)统一为 'connection canceled'(与 cancelConnectingDevice 一致)。
        response.set('disconnect_reason_code', 23789258);
        response.set('disconnect_reason_string', 'connection canceled');
      } else if (wasConnecting) {
        // 连接中即断开 = 连接失败（拒绝配对/超时/远端拒绝）。
        // OHOS 回调无 cause 字段拿不到真实 HCI 原因码,回传 code=1 + 'UNKNOWN_HCI_ERROR (1)'
        response.set('disconnect_reason_code', 1);
        response.set('disconnect_reason_string', TextUtils.hciStatusString(1));
      } else {
        // 不能用 hciStatusString(0) → 'SUCCESS',否则 Flutter 侧会显示
        // "Connect Error: SUCCESS" 这种语义矛盾的红色弹窗。
        // 自发断连(code 0)的 OHOS 回调无 cause 字段,0 是占位码,赋语义化 'unknown'。
        response.set('disconnect_reason_code', 0);
        response.set('disconnect_reason_string', 'unknown');
      }
    }
    this.plugin.channel?.invokeMethod('OnConnectionStateChanged', response);
  }

  /**
   * 构造连接管理器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * 判断指定设备是否处于连接建立中(connecting)状态。Map.get 返回 undefined 表示键不存在,需与 null 一并判空。
   * @param remoteId 设备 MAC 地址。
   * @returns 处于连接中返回 true。
   */
  isConnecting(remoteId: string): boolean {
    let gatt: ble.GattClientDevice | undefined = this.currentlyConnectingDevices.get(remoteId);
    return gatt !== null && gatt !== undefined;
  }

  /**
   * 判断指定设备是否已建立连接(connected)。Map.get 返回 undefined 表示键不存在,需与 null 一并判空。
   * @param remoteId 设备 MAC 地址。
   * @returns 已连接返回 true。
   */
  isConnected(remoteId: string): boolean {
    let gatt: ble.GattClientDevice | undefined = this.connectedDevices.get(remoteId);
    return gatt !== null && gatt !== undefined;
  }

  /**
   * 处理 connect 方法调用:创建 GATT 客户端并连接指定远程设备。
   *
   * connect() 异常必须提前返回,避免未成功连接的 clientDevice 被误加入 currentlyConnectingDevices。
   * @param call 方法调用,含方法名与参数。
   * @param result 结果回调,用于向 Flutter 返回成功或错误。
   */
  async connect(call: MethodCall, result: MethodResult): Promise<void> {
    let args: Map<string, string | boolean> = call.args;
    let remoteId: string = args.get('remote_id') as string;
    // 关键参数显式校验:remote_id 为空时直接回传错误并提前返回,避免 undefined 沿调用链下行触发空指针。
    if (remoteId === null || remoteId === undefined || remoteId.length === 0) {
      BleUtils.log(hilog.LogLevel.ERROR, 'connect: remote_id is required and non-empty');
      result.error('connect', 'remote_id is required and non-empty', null);
      return;
    }
    // Dart 侧 auto_connect 经 MethodChannel 传 boolean,true/false 直转即可。
    let autoConnect: boolean = args.get('auto_connect') as boolean;
    // 前置校验(权限/适配器/幂等):任一不满足时已 result.success/error 并返回 false。
    if (!await this.validateConnectPrerequisites(remoteId, result)) {
      return;
    }
    await this.waitIfBonding();
    let clientDevice: ble.GattClientDevice | null = null;
    try {
      clientDevice = ble.createGattClientDevice(remoteId);
      clientDevice.connect();
      clientDevice.on('BLEConnectionStateChange', this.connectStateChanged);
    } catch (err) {
      // 错误路径必须关闭已创建的 GattClientDevice,否则原生 BLE 资源泄漏(先 disconnect 再 close)。
      this.cleanupFailedConnect(clientDevice);
      // 连接失败必须回传 Flutter,否则 Dart 侧误以为连接成功而无限等待。
      BleUtils.log(hilog.LogLevel.ERROR,
        'errCode: ' + (err as BusinessError)?.code + ', errMessage: ' + (err as BusinessError)?.message);
      result.error('connect', (err as BusinessError)?.message ?? 'connect failed', null);
      return;
    }
    this.registerConnectingDevice(remoteId, clientDevice, autoConnect);
    result.success(true);
  }

  /**
   * connect 前置校验:权限、适配器开启、幂等(正在连接/已连接)。
   * 幂等命中时回传 success(true/false) 并返回 false(主方法据此 return);校验失败回传 error 并返回 false。
   * @returns true 表示通过校验可继续连接;false 表示已回传结果,主方法应直接 return。
   */
  private async validateConnectPrerequisites(remoteId: string, result: MethodResult): Promise<boolean> {
    if (!await this.plugin.permissionManager.ensurePermissions(result, 'connect')) {
      return false;
    }
    if (!BleUtils.isAdapterOn()) {
      BleUtils.log(hilog.LogLevel.ERROR, 'bluetooth must be turned on');
      result.error('connect', 'bluetooth must be turned on', null);
      return false;
    }
    if (this.isConnecting(remoteId)) {
      BleUtils.log(hilog.LogLevel.DEBUG, 'already connecting');
      result.success(true); // still work to do;
      return false;
    }
    if (this.isConnected(remoteId)) {
      BleUtils.log(hilog.LogLevel.DEBUG, 'already connected');
      result.success(false); // still work to do;
      return false;
    }
    return true;
  }

  /**
   * 将已连接的 GattClientDevice 入表(正在连接表 + 按需加入自动重连表)。
   */
  private registerConnectingDevice(remoteId: string, clientDevice: ble.GattClientDevice,
    autoConnect: boolean): void {
    this.currentlyConnectingDevices.set(remoteId, clientDevice);
    if (autoConnect) {
      this.autoConnected.set(remoteId, clientDevice);
    } else {
      this.autoConnected.delete(remoteId);
    }
  }

  /**
   * connect 异常路径的资源清理:关闭已创建的 GattClientDevice,避免原生 BLE 资源泄漏。
   * 先 disconnect(可能尚未连接成功,失败忽略)再 close,与 releaseGatt 的释放顺序保持一致。
   * @param clientDevice 已创建的 GattClientDevice(可能为 null,创建失败时)。
   */
  private cleanupFailedConnect(clientDevice: ble.GattClientDevice | null): void {
    if (clientDevice !== null) {
      try {
        clientDevice.disconnect();
      } catch (e) {
        BleUtils.log(hilog.LogLevel.ERROR, 'connect error cleanup disconnect: ' + (e as BusinessError)?.message);
      }
      try {
        clientDevice.close();
      } catch (e) {
        BleUtils.log(hilog.LogLevel.ERROR, 'connect error cleanup close: ' + (e as BusinessError)?.message);
      }
    }
  }

  /**
   * 处理 disconnect 方法调用:断开/取消连接,清理监听并通过 OnConnectionStateChanged 回传。
   *
   * 三路查找待断开设备:connecting → connected → autoConnected。
   * connecting 路径用 releaseGatt 释放后回传 reason=23789258(用户取消);
   * connected 路径仅 disconnect,交由 connectStateChanged 回调执行 off→close 释放;
   * autoConnected 路径表示设备已断开,仅清理 autoconnect 标记。
   * @param call 方法调用,参数为 remoteId 字符串。
   * @param result 结果回调,用于向 Flutter 返回成功或错误。
   */
  disconnect(call: MethodCall, result: MethodResult): void {
    try {
      let remoteId: string = call.args;
      // 依次从 connecting/connected/autoConnected 三表查找待断开设备。
      let gatt: ble.GattClientDevice | undefined = this.findGattForDisconnect(remoteId, result);
      if (gatt === null || gatt === undefined) {
        // findGattForDisconnect 已对 autoConnected 命中/未命中场景回传 success(false)。
        return;
      }
      this.autoConnected.delete(remoteId);
      if (this.isConnecting(remoteId)) {
        this.cancelConnectingDevice(remoteId, gatt);
      } else {
        // 已连接设备的主动断开:标记为用户主动断连,使 connectStateChanged 回调能区分
        // reason=23789258(用户取消) vs reason=0(系统断连)。仅 disconnect 交由回调处理释放。
        this.userDisconnectingDevices.add(remoteId);
        gatt.disconnect();
      }
      result.success(true);
      return;
    } catch (e) {
      let be: BusinessError = e as BusinessError;
      let msg: string = (be !== null && be.message !== null) ? be.message : 'unknown';
      BleUtils.log(hilog.LogLevel.ERROR, 'disconnect error: ' + msg);
      result.error('disconnect', 'disconnect failed: ' + msg, null);
      return;
    }
  }

  /**
   * disconnect 时依次从 connecting/connected/autoConnected 三表查找 gatt。
   * autoConnected 命中(已断开仅禁用自动重连)或三表皆无时,回传 success(false) 并返回 undefined;
   * 找到时返回 gatt(调用方继续执行主动断开)。
   */
  private findGattForDisconnect(remoteId: string,
    result: MethodResult): ble.GattClientDevice | undefined {
    let gatt: ble.GattClientDevice | undefined = this.currentlyConnectingDevices.get(remoteId);
    if (gatt !== null && gatt !== undefined) {
      BleUtils.log(hilog.LogLevel.DEBUG, 'disconnect: cancelling connection in progress');
    }
    if (gatt === null || gatt === undefined) {
      gatt = this.connectedDevices.get(remoteId);
    }
    if (gatt === null || gatt === undefined) {
      gatt = this.autoConnected.get(remoteId);
      if (gatt !== null && gatt !== undefined) {
        BleUtils.log(hilog.LogLevel.DEBUG, 'already disconnected. disabling autoconnect');
        this.autoConnected.delete(remoteId);
        // 先取消设备级监听器,再 disconnect/close,避免 gatt 持有 connectStateChanged→this 引用阻止 GC。
        this.releaseGatt(gatt);
        result.success(false); // no work to do;
        return undefined;
      }
    }
    if (gatt === null || gatt === undefined) {
      BleUtils.log(hilog.LogLevel.DEBUG, 'already disconnected');
      result.success(false); // no work to do;
      return undefined;
    }
    return gatt;
  }

  /**
   * 取消正在连接中的设备:从 connecting 表移除,off 监听器再 close,并回传
   * OnConnectionStateChanged(reason=23789258 用户主动取消)。
   */
  private cancelConnectingDevice(remoteId: string, gatt: ble.GattClientDevice): void {
    this.currentlyConnectingDevices.delete(remoteId);
    // 连接中取消:先 off 监听器再 close,确保 BLEConnectionStateChange 回调被移除,
    // 避免 close() 不隐式解绑监听器时形成 gatt→callback→this 残留引用。
    this.releaseGatt(gatt);
    let bmUserCanceledErrorCode: number = 23789258;
    let response: Map<string, string | number> = new Map<string, string | number>();
    response.set('remote_id', remoteId);
    response.set('connection_state',
      BleUtils.buildConnectionStateEnum(constant.ProfileConnectionState.STATE_DISCONNECTED));
    response.set('disconnect_reason_code', bmUserCanceledErrorCode);
    response.set('disconnect_reason_string', 'connection canceled');
    this.plugin.channel?.invokeMethod('OnConnectionStateChanged', response);
  }

  /**
   * 释放单个 GattClientDevice:按 off(BLEConnectionStateChange) → off(BLECharacteristicChange)
   * → disconnect → close 的固定顺序释放,确保设备级监听器被取消,避免 gatt 内部持有
   * connectStateChanged/characteristicChange 回调 → this 的引用而阻止 GC。
   * 供 disconnect 与 closeAllGattClients 共用,保证 on/off 对称。
   *
   * 【泄漏修复】此 off→off→disconnect→close 顺序为前期内存泄漏 hard-won 修复,不得更改。
   * @param gatt 待释放的 GattClientDevice。
   */
  releaseGatt(gatt: ble.GattClientDevice): void {
    try {
      gatt.off('BLEConnectionStateChange', this.connectStateChanged);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'releaseGatt off BLEConnectionStateChange: ' + (e as BusinessError)?.message);
    }
    try {
      gatt.off('BLECharacteristicChange');
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'releaseGatt off BLECharacteristicChange: ' + (e as BusinessError)?.message);
    }
    try {
      gatt.disconnect();
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'releaseGatt disconnect: ' + (e as BusinessError)?.message);
    }
    try {
      gatt.close();
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'releaseGatt close: ' + (e as BusinessError)?.message);
    }
  }

  /**
   * 关闭并释放所有 GattClientDevice,取消其设备级监听(连接状态变化、特征值变化)。
   * 在插件解绑或适配器关闭时调用,防止底层 BLE 资源泄漏。
   * 遍历 connectedDevices/currentlyConnectingDevices/autoConnected/bondingDevices 四个设备表。
   */
  closeAllGattClients(): void {
    let closeGatt = (gatt: ble.GattClientDevice) => {
      this.releaseGatt(gatt);
    };
    this.connectedDevices.forEach((gatt: ble.GattClientDevice) => {
      closeGatt(gatt);
    });
    this.currentlyConnectingDevices.forEach((gatt: ble.GattClientDevice) => {
      closeGatt(gatt);
    });
    this.autoConnected.forEach((gatt: ble.GattClientDevice) => {
      closeGatt(gatt);
    });
    this.plugin.bondManager.bondingDevices.forEach((gatt: ble.GattClientDevice) => {
      closeGatt(gatt);
    });
  }

  /**
   * 拆除所有跟踪设备。`adapterTurnOff` 路径取消回调并关闭每个 GATT 客户端
   * (保留自动连接设备),同时为每台设备发出 OnConnectionStateChanged;
   * `flutterRestart` 路径断开并关闭所有设备。各 Map 在迭代结束后统一清空,
   * 而非迭代中清空,以避免边迭代边修改的未定义行为。
   * @param func 触发上下文:'adapterTurnOff' 或 'flutterRestart'。
   */
  disconnectAllDevices(func: string): void {
    // 先收集 key 再迭代,避免在 forEach 过程中对当前 Map delete 导致未定义行为;
    // 响应用迭代 key 而非 this.remoteId(后者在多设备场景会指向错误设备)。
    let keys: string[] = [];
    this.connectedDevices.forEach((_value: ble.GattClientDevice, key: string) => {
      keys.push(key);
    });
    if (func === 'adapterTurnOff') {
      this.disconnectAllForAdapterTurnOff(keys);
    } else {
      this.disconnectAllForFlutterRestart(keys);
    }
    // clear 移到迭代之外,避免边迭代边清空。
    this.connectedDevices.clear();
    this.currentlyConnectingDevices.clear();
    this.plugin.bondManager.bondingDevices.clear();
    this.plugin.gattCache.clearAll();
    this.autoConnected.clear();
    this.userDisconnectingDevices.clear();
  }

  /**
   * adapterTurnOff 路径:从各表删除并释放非自动连接设备(off→disconnect→close),
   * 为每台设备回传 OnConnectionStateChanged(reason=0 系统断连)。
   */
  private disconnectAllForAdapterTurnOff(keys: string[]): void {
    for (let i = 0; i < keys.length; i++) {
      let key: string = keys[i];
      let value: ble.GattClientDevice | undefined = this.connectedDevices.get(key);
      if (value === null || value === undefined) {
        continue;
      }
      this.connectedDevices.delete(key);
      this.currentlyConnectingDevices.delete(key);
      // 同 handleDisconnected:释放 BONDING 态 GattClientDevice,避免只 delete 不 close 泄漏。
      this.plugin.bondManager.clearBondingState(key);
      if (!this.autoConnected.has(key)) {
        try {
          value.off('BLEConnectionStateChange', this.connectStateChanged);
          value.off('BLECharacteristicChange');
          // adapterTurnOff 时适配器虽已关闭(disconnect 可能已无实际效果),仍按 releaseGatt 的
          // 标准释放顺序 off→disconnect→close 执行,保持一致性,避免保留半连接状态。
          value.disconnect();
          value.close();
        } catch (e) {
          BleUtils.log(hilog.LogLevel.ERROR, 'disconnectAllDevices close: ' + (e as BusinessError)?.message);
        }
      }
      this.emitDisconnectedState(key, 0);
    }
  }

  /**
   * flutterRestart 路径:断开并关闭所有设备(off→disconnect→close)。
   */
  private disconnectAllForFlutterRestart(keys: string[]): void {
    for (let i = 0; i < keys.length; i++) {
      let key: string = keys[i];
      let value: ble.GattClientDevice | undefined = this.connectedDevices.get(key);
      if (value === null || value === undefined) {
        continue;
      }
      try {
        value.off('BLEConnectionStateChange', this.connectStateChanged);
        value.off('BLECharacteristicChange');
        value.disconnect();
        value.close();
      } catch (e) {
        BleUtils.log(hilog.LogLevel.ERROR, 'disconnectAllDevices disconnect: ' + (e as BusinessError)?.message);
      }
    }
  }

  /**
   * 回传 OnConnectionStateChanged(STATE_DISCONNECTED) 给指定设备。
   * @param remoteId 设备 ID;@param reasonCode 断连原因码(0=系统断连,23789258=用户取消)。
   */
  private emitDisconnectedState(remoteId: string, reasonCode: number): void {
    let response: Map<string, string | number> = new Map<string, string | number>();
    response.set('remote_id', remoteId);
    response.set('connection_state',
      BleUtils.buildConnectionStateEnum(constant.ProfileConnectionState.STATE_DISCONNECTED));
    response.set('disconnect_reason_code', reasonCode);
    // 同 emitConnectionStateChanged:0 在断连场景非真实 HCI SUCCESS,赋语义化 'unknown'
    // 避免 Flutter 侧 "Connect Error: SUCCESS" 的语义矛盾。
    response.set('disconnect_reason_string', reasonCode === 0 ? 'unknown' : 'connection canceled');
    this.plugin.channel?.invokeMethod('OnConnectionStateChanged', response);
  }

  /**
   * 在配对协商期间短暂暂停当前操作,使后续 GATT 调用基于已配对/加密链路执行。
   * 等待为单次短节拍并记录日志以便诊断。
   * @param maxWaitMs 最大等待毫秒数,默认 3000。
   */
  async waitIfBonding(maxWaitMs: number = 3000): Promise<void> {
    // 轮询等待配对完成:蓝牙配对通常需数百毫秒到数秒,单次 50ms 等待不足以保证完成。
    // 此处循环检测 bondingDevices 是否清空,超时则放弃等待(后续 GATT 操作可能在未加密链路上执行)。
    let waited: number = 0;
    while (this.plugin.bondManager.bondingDevices.size > 0 && waited < maxWaitMs) {
      BleUtils.log(hilog.LogLevel.DEBUG, 'waiting for bonding to complete...');
      await BleUtils.delay(100);
      waited += 100;
    }
    if (this.plugin.bondManager.bondingDevices.size > 0) {
      BleUtils.log(hilog.LogLevel.WARN, 'bonding wait timed out after ' + maxWaitMs + 'ms');
    }
  }

  /**
   * 处理蓝牙适配器状态变化:适配器可用时发出 OnTurnOnResponse,始终发出 OnAdapterStateChanged,
   * 并在适配器关闭时拆除所有设备连接。
   * @param data 新的 {@link access.BluetoothState}。
   */
  onReceiveEvent(data: access.BluetoothState): void {
    if (BleUtils.isAdapterOn()) {
      let map: Map<string, boolean> = new Map<string, boolean>();
      map.set('user_accepted', true);
      this.plugin.channel?.invokeMethod('OnTurnOnResponse', map);
    }
    let map: Map<string, number> = new Map<string, number>();
    map.set('adapter_state', BleUtils.buildAdapterStateEnum(data));
    this.plugin.channel?.invokeMethod('OnAdapterStateChanged', map);
    if (data === access.BluetoothState.STATE_BLE_TURNING_OFF ||
      data === access.BluetoothState.STATE_OFF) {
      this.disconnectAllDevices('adapterTurnOff');
    }
  }

  /**
   * 统一资源清理:注销适配器状态监听、释放所有 GattClientDevice、清空所有设备 Map 与共享缓存。
   * 幂等,可被 onDetachedFromEngine 调用。
   */
  cleanup(): void {
    BleUtils.log(hilog.LogLevel.INFO, 'cleanup: releasing all BLE connection resources');
    // 1) 注销适配器状态监听(传入原始回调引用)。用 stateChangeSubscribed 标志位做幂等:
    //    未订阅则跳过,避免对未注册监听执行无效 off;off 成功后复位标志位。
    if (this.stateChangeSubscribed) {
      try {
        access.off('stateChange', this.stateChangeCallback);
      } catch (e) {
        BleUtils.log(hilog.LogLevel.WARN, 'cleanup: off stateChange failed: ' + (e as BusinessError)?.message);
      }
      this.stateChangeSubscribed = false;
    }
    // 2) 释放所有 GattClientDevice 并取消其设备级监听。
    this.closeAllGattClients();
    // 3) 清空两个 BLECharacteristicChange 回调 Map。
    //    closeAllGattClients 已对每个 gatt 执行 BLECharacteristicChange 的 off,但这两个 Map 持有
    //    闭包引用(捕获 remoteId/services → 经 plugin 持有 connectedDevices),不清空会残留循环引用。
    //    这里仅清 Map 引用本身。
    this.plugin.notifyManager.clearAll();
    this.plugin.characteristicManager.clearAll();
    // 4) 清空连接管理器拥有的 Map 与用户主动断连标记。
    this.connectedDevices.clear();
    this.currentlyConnectingDevices.clear();
    this.autoConnected.clear();
    this.userDisconnectingDevices.clear();
    // 4) 清空共享缓存(gattCache: mtu/writeChr/writeDesc/deviceServices)。
    this.plugin.gattCache.clearAll();
    // 5) 清空配对设备表(bondingDevices 由 bondManager 持有)。
    this.plugin.bondManager.bondingDevices.clear();
    // 6) 复位标量引用。
    this.clientDevice = null;
    this.remoteId = null;
  }
}
