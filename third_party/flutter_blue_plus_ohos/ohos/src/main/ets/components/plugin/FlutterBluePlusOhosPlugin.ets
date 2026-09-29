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

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  AbilityPluginBinding,
} from '@ohos/flutter_ohos';
import { ble, connection } from '@kit.ConnectivityKit';
import { List } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import access from '@ohos.bluetooth.access';
import BleUtils from './BleUtils';
import BlePermissionManager from './BlePermissionManager';
import BleConnectionManager from './BleConnectionManager';
import BleScanManager from './BleScanManager';
import BleGattManager from './BleGattManager';
import BleCharacteristicManager from './BleCharacteristicManager';
import BleDescriptorManager from './BleDescriptorManager';
import BleNotifyManager from './BleNotifyManager';
import BleMtuManager from './BleMtuManager';
import BleBondManager from './BleBondManager';
import GattCacheHolder from './GattCacheHolder';
import BleMethodDispatcher from './BleMethodDispatcher';

/**
 * FlutterBluePlus OHOS 插件主类（slim coordinator）。
 *
 * 原单体类（2196 行）已按职责拆分为 9 个 Manager + 1 个方法分发器，主类仅承担：
 *  1. FlutterPlugin / AbilityPlugin 生命周期：构造各 Manager、注册/注销系统事件监听、资源清理；
 *  2. MethodChannel 方法分发：委托 {@link BleMethodDispatcher}（Map 查找替代原 switch）；
 *  3. 适配器/系统类 handle* 方法（11 个）：其余业务方法已迁入对应 Manager。
 *
 * 跨 Manager 共享状态经 plugin 实例中介访问（channel / permissionManager / gattCache /
 * connectionManager / bondManager / scanManager / notifyManager 等 public 字段），
 * 避免子 Manager 间互相持有引用。
 */
export default class FlutterBluePlusOhosPlugin implements FlutterPlugin, MethodCallHandler {
  /** Flutter MethodChannel，各 Manager 经此回传事件。 */
  public channel: MethodChannel | null = null;
  /** 权限管理器（context 由本类在 onAttachedToAbility 注入）。 */
  public permissionManager: BlePermissionManager = new BlePermissionManager();
  /** GATT 共享缓存（mtuMap/writeChrMap/writeDescMap/deviceServicesMap）。 */
  public gattCache: GattCacheHolder = new GattCacheHolder();
  /** 连接管理器（持有 connectedDevices 等设备表）。 */
  public connectionManager!: BleConnectionManager;
  /** 配对管理器（持有 bondingDevices、bondStateChangeCallback）。 */
  public bondManager!: BleBondManager;
  /** 扫描管理器（持有 onScanResult 回调、advSeen/scanCounts）。 */
  public scanManager!: BleScanManager;
  /** GATT facade（readRssi / discoverServices）。 */
  public gattManager!: BleGattManager;
  /** 特征读写管理器。 */
  public characteristicManager!: BleCharacteristicManager;
  /** 描述符读写管理器。 */
  public descriptorManager!: BleDescriptorManager;
  /** 通知/指示管理器（setNotifyValue、BLECharacteristicChange 注册）。 */
  public notifyManager!: BleNotifyManager;
  /** MTU 协商管理器。 */
  public mtuManager!: BleMtuManager;
  /** 方法分发器（Map 查找表）。 */
  public dispatcher!: BleMethodDispatcher;
  /** 引擎是否已分离，各 Manager 回调据此短路退出。 */
  public isDetached: boolean = false;

  /**
   * 返回插件类的唯一标识名，供 Flutter 插件注册框架使用。
   * @returns 类名字符串。
   */
  getUniqueClassName(): string {
    return 'FlutterBluePlusPlugin';
  }

  /**
   * 插件绑定到 Flutter 引擎时初始化 MethodChannel 并构造全部 Manager。
   * Manager 在 setMethodCallHandler 之前构造完毕，确保首个方法调用到达时分发器已就绪。
   * @param binding Flutter 插件绑定信息。
   */
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.isDetached = false;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'flutter_blue_plus/methods');
    // 按依赖顺序构造：被依赖者先构造（permissionManager/gattCache 已字段初始化，无需此处构造）。
    this.connectionManager = new BleConnectionManager(this);
    this.bondManager = new BleBondManager(this);
    this.gattManager = new BleGattManager(this);
    this.characteristicManager = new BleCharacteristicManager(this);
    this.descriptorManager = new BleDescriptorManager(this);
    this.notifyManager = new BleNotifyManager(this);
    this.mtuManager = new BleMtuManager(this);
    this.scanManager = new BleScanManager(this);
    this.dispatcher = new BleMethodDispatcher(this);
    this.channel.setMethodCallHandler(this);
  }

  /**
   * MethodChannel 方法调用入口：委托分发器按 call.method 查 Map 分发。
   * @param call 方法调用，包含方法名与参数。
   * @param result 结果回调，用于向 Flutter 返回成功或错误。
   */
  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    await this.dispatcher.onMethodCall(call, result);
  }

  /**
   * 插件从 Flutter 引擎解绑时完整释放资源。
   * 标记 detached → 取消 handler → 连接管理器清理（释放 GattClientDevice、off stateChange）
   * → off 全局事件监听 → 清空 channel。
   * @param binding Flutter 插件绑定信息。
   */
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.isDetached = true;
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
    }
    // cleanup 内部已按 stateChangeSubscribed 标志位幂等注销 stateChange 并释放所有 gatt/Map。
    this.connectionManager.cleanup();
    // bondStateChange 由 Ability 生命周期订阅,引擎分离时也需注销(用标志位幂等)。
    this.unsubscribeBondStateChange();
    try {
      ble.stopBLEScan();
    } catch (e) {
      // 扫描可能未启动，忽略。
    }
    try {
      ble.off('BLEDeviceFind', this.scanManager.onScanResult);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'onDetachedFromEngine off BLEDeviceFind: ' + (e as BusinessError)?.message);
    }
    this.channel = null;
  }

  /**
   * 插件绑定到 Ability 时注册配对/适配器状态监听并注入 context。
   * 先 off 旧监听再 on，避免重复注册（同一回调引用才能真正取消）。
   * @param binding Ability 插件绑定信息。
   */
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.isDetached = false;
    this.subscribeBondStateChange();
    this.subscribeStateChange();
    this.permissionManager.context = binding.getAbility().context;
  }

  /**
   * Ability 分离时取消 bondStateChange / stateChange 监听并释放 context 引用。
   * @param binding Ability 插件绑定信息。
   */
  onDetachedFromAbility(binding: AbilityPluginBinding): void {
    this.unsubscribeBondStateChange();
    this.unsubscribeStateChange();
    this.permissionManager.context = null;
  }

  /**
   * 注册 bondStateChange 监听(幂等)：已订阅则跳过;否则先 off 旧监听再 on,置订阅标志位。
   * 用 {@link BleBondManager#bondStateSubscribed} 追踪订阅状态,避免重复 on 累积监听器、
   * 也避免对未订阅监听执行无效 off。
   */
  private subscribeBondStateChange(): void {
    if (this.bondManager.bondStateSubscribed) {
      return;
    }
    try {
      connection.off('bondStateChange', this.bondManager.bondStateChangeCallback);
    } catch (e) {
      // 首次注册时无旧监听，忽略。
    }
    try {
      connection.on('bondStateChange', this.bondManager.bondStateChangeCallback);
      this.bondManager.bondStateSubscribed = true;
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'subscribeBondStateChange on: ' + (e as BusinessError)?.message);
    }
  }

  /**
   * 注销 bondStateChange 监听(幂等)：未订阅则跳过;否则 off 并清订阅标志位。
   */
  private unsubscribeBondStateChange(): void {
    if (!this.bondManager.bondStateSubscribed) {
      return;
    }
    try {
      connection.off('bondStateChange', this.bondManager.bondStateChangeCallback);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'unsubscribeBondStateChange off: ' + (e as BusinessError)?.message);
    }
    this.bondManager.bondStateSubscribed = false;
  }

  /**
   * 注册 stateChange 监听(幂等)：已订阅则跳过;否则先 off 旧监听再 on,置订阅标志位。
   * 用 {@link BleConnectionManager#stateChangeSubscribed} 追踪订阅状态。
   */
  private subscribeStateChange(): void {
    if (this.connectionManager.stateChangeSubscribed) {
      return;
    }
    try {
      access.off('stateChange', this.connectionManager.stateChangeCallback);
    } catch (e) {
      // 首次注册时无旧监听，忽略。
    }
    try {
      access.on('stateChange', this.connectionManager.stateChangeCallback);
      this.connectionManager.stateChangeSubscribed = true;
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'subscribeStateChange on: ' + (e as BusinessError)?.message);
    }
  }

  /**
   * 注销 stateChange 监听(幂等)：未订阅则跳过;否则 off 并清订阅标志位。
   */
  private unsubscribeStateChange(): void {
    if (!this.connectionManager.stateChangeSubscribed) {
      return;
    }
    try {
      access.off('stateChange', this.connectionManager.stateChangeCallback);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'unsubscribeStateChange off: ' + (e as BusinessError)?.message);
    }
    this.connectionManager.stateChangeSubscribed = false;
  }

  // ===== 特征值回传委托 =====

  /**
   * 特征值到达回传委托：BleCharacteristicManager 读取成功后调用此方法回传 OnCharacteristicReceived。
   * 实际发射逻辑在 {@link BleNotifyManager#onCharacteristicReceived}（通知回调与 CCCD 写入强相关，归属通知管理器更内聚）。
   * @param address 设备 MAC 地址。
   * @param services 该设备的 GATT 服务树。
   * @param characteristic 到达的特征。
   */
  onCharacteristicReceived(address: string, services: ble.GattService[],
    characteristic: ble.BLECharacteristic): void {
    this.notifyManager.onCharacteristicReceived(address, services, characteristic);
  }

  // ===== 适配器/系统类 handle* 方法（委托目标，由 BleMethodDispatcher 调用）=====

  /**
   * 处理 flutterRestart：停扫描、重注册适配器监听、断开所有设备，回传剩余连接数。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  handleFlutterRestart(call: MethodCall, result: MethodResult): void {
    try {
      ble.stopBLEScan();
      this.scanManager.isScanning = false;
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'flutterRestart stopBLEScan: ' + (e as BusinessError)?.message);
    }
    try {
      access.off('stateChange', this.connectionManager.stateChangeCallback);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'flutterRestart off stateChange: ' + (e as BusinessError)?.message);
    }
    try {
      access.on('stateChange', this.connectionManager.stateChangeCallback);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'flutterRestart on stateChange: ' + (e as BusinessError)?.message);
    }
    this.connectionManager.disconnectAllDevices('flutterRestart');
    result.success(this.connectionManager.connectedDevices.size);
  }

  /**
   * 处理 connectedCount：回传当前已连接设备数。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  handleConnectedCount(call: MethodCall, result: MethodResult): void {
    try {
      BleUtils.log(hilog.LogLevel.DEBUG, 'connectedPeripherals: ' + this.connectionManager.connectedDevices.size);
      result.success(this.connectionManager.connectedDevices.size);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'handleConnectedCount: ' + (e as BusinessError)?.message);
      result.error('connectedCount', (e as BusinessError)?.message ?? 'unknown error', null);
    }
  }

  /**
   * 处理 setOptions：解析并记录参数（OHOS 不支持 powerAlert/restoreState），返回成功。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  handleSetOptions(call: MethodCall, result: MethodResult): void {
    try {
      let data: Map<string, boolean> = call.args;
      let showPowerAlert: boolean = data.get('show_power_alert') as boolean;
      let restoreState: boolean = data.get('restore_state') as boolean;
      BleUtils.log(hilog.LogLevel.DEBUG, 'setOptions showPowerAlert=' + showPowerAlert +
        ' restoreState=' + restoreState + ' (ignored on OHOS)');
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'setOptions parse: ' + (e as BusinessError)?.message);
    }
    result.success(true);
  }

  /**
   * 处理 getAdapterState：读取适配器状态并映射为 Flutter 端枚举值回传。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  handleGetAdapterState(call: MethodCall, result: MethodResult): void {
    let accessNum: number = -1;
    try {
      accessNum = access.getState();
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'getAdapterState getState: ' + (e as BusinessError)?.message);
    }
    let map: Map<string, number> = new Map<string, number>();
    map.set('adapter_state', BleUtils.buildAdapterStateEnum(accessNum));
    result.success(map);
  }

  /**
   * 处理 getSystemDevices：返回系统已连接的 BLE 设备列表。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  async handleGetSystemDevices(call: MethodCall, result: MethodResult): Promise<void> {
    if (!await this.permissionManager.ensurePermissions(result, 'getSystemDevices')) {
      return;
    }
    try {
      let devices: string[] = ble.getConnectedBLEDevices();
      let devList: List<Map<string, string>> = new List<Map<string, string>>();
      devices.forEach((device: string) => {
        devList.add(BleUtils.buildBluetoothDevice(device));
      });
      let response: Map<string, object> = new Map<string, object>();
      response.set('devices', devList);
      result.success(response);
    } catch (err) {
      BleUtils.log(hilog.LogLevel.ERROR, 'errCode: ' + (err as BusinessError)?.code + ', errMessage: ' +
        (err as BusinessError)?.message);
      result.error('getSystemDevices', (err as BusinessError)?.message ?? 'get connected BLE devices failed', null);
    }
  }

  /**
   * 处理 turnOn：适配器处于关闭态时请求开启蓝牙。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  async handleTurnOn(call: MethodCall, result: MethodResult): Promise<void> {
    if (!await this.permissionManager.ensurePermissions(result, 'turnOn')) {
      return;
    }
    let state: access.BluetoothState = access.getState();
    if (state === access.BluetoothState.STATE_OFF || state === access.BluetoothState.STATE_TURNING_OFF ||
      state === access.BluetoothState.STATE_BLE_TURNING_OFF) {
      try {
        access.enableBluetooth();
        result.success(true);
      } catch (e) {
        // enableBluetooth 失败必须回传 error,否则 Dart 侧 turnOn Future(Future<void>)正常完成,
        // 用户无法得知开关操作失败。
        BleUtils.log(hilog.LogLevel.ERROR, 'turnOn enableBluetooth: ' + (e as BusinessError)?.message);
        result.error('turnOn', 'enableBluetooth failed: ' + ((e as BusinessError)?.message ?? ''), null);
      }
      return;
    }
    // 适配器不在可开启状态区间(如已开启/正在开启),无需操作,正常返回 false(changed=false)。
    result.success(false);
  }

  /**
   * 处理 turnOff：适配器处于开启态时请求关闭蓝牙。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  async handleTurnOff(call: MethodCall, result: MethodResult): Promise<void> {
    if (!await this.permissionManager.ensurePermissions(result, 'turnOff')) {
      return;
    }
    let state: access.BluetoothState = access.getState();
    if (state === access.BluetoothState.STATE_ON || state === access.BluetoothState.STATE_TURNING_ON ||
      state === access.BluetoothState.STATE_BLE_TURNING_ON || state === access.BluetoothState.STATE_BLE_ON) {
      try {
        access.disableBluetooth();
        result.success(true);
      } catch (e) {
        // disableBluetooth 失败必须回传 error,否则 Dart 侧 turnOff Future 静默成功。
        BleUtils.log(hilog.LogLevel.ERROR, 'turnOff disableBluetooth: ' + (e as BusinessError)?.message);
        result.error('turnOff', 'disableBluetooth failed: ' + ((e as BusinessError)?.message ?? ''), null);
      }
      return;
    }
    // 适配器不在可关闭状态区间(如已关闭/正在关闭),无需操作,正常返回 false。
    result.success(false);
  }

  /**
   * 处理 setLogLevel：按 Dart 传入的索引设置 BleUtils.logLevel（静态，全局生效）。
   * @param call 方法调用，args 为日志级别索引（0-5）。
   * @param result 结果回调。
   */
  handleSetLogLevel(call: MethodCall, result: MethodResult): void {
    try {
      let idx: number = call.args as number;
      switch (idx) {
        case 0:
          BleUtils.logLevel = hilog.LogLevel.FATAL + 1; // 关闭所有日志
          break;
        case 1:
          BleUtils.logLevel = hilog.LogLevel.ERROR;
          break;
        case 2:
          BleUtils.logLevel = hilog.LogLevel.WARN;
          break;
        case 3:
          BleUtils.logLevel = hilog.LogLevel.INFO;
          break;
        case 4:
        case 5:
          BleUtils.logLevel = hilog.LogLevel.DEBUG;
          break;
        default:
          break;
      }
      result.success(true);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'handleSetLogLevel: ' + (e as BusinessError)?.message);
      result.error('setLogLevel', (e as BusinessError)?.message ?? 'unknown error', null);
    }
  }

  /**
   * 处理 isSupported：检测系统是否支持蓝牙核心能力。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  handleIsSupported(call: MethodCall, result: MethodResult): void {
    try {
      let supported: boolean = canIUse('SystemCapability.Communication.Bluetooth.Core');
      result.success(supported);
    } catch (err) {
      // 检测蓝牙支持能力失败必须回传 error,而非 success(false)——后者会让 Dart 侧误判为"不支持蓝牙",
      // 与"检测过程出错"是两种完全不同的语义。
      BleUtils.log(hilog.LogLevel.ERROR, 'Failed to check bluetooth support: ' + (err as BusinessError)?.message);
      result.error('isSupported', (err as BusinessError)?.message ?? 'unknown error', null);
    }
  }

  /**
   * 处理 getAdapterName：返回蓝牙适配器本地名称。
   * @param call 方法调用。
   * @param result 结果回调。
   */
  async handleGetAdapterName(call: MethodCall, result: MethodResult): Promise<void> {
    if (!await this.permissionManager.ensurePermissions(result, 'getAdapterName')) {
      return;
    }
    let localName: string | null = null;
    try {
      localName = connection.getLocalName();
    } catch (err) {
      BleUtils.log(hilog.LogLevel.ERROR,
        'errCode: ' + (err as BusinessError)?.code + ', errMessage: ' + (err as BusinessError)?.message);
    }
    result.success(localName !== null ? localName : 'N/A');
  }

  /**
   * 处理 clearGattCache：校验设备已连接后返回成功（OHOS 无 GATT 缓存清理 API，平台限制）。
   * @param call 方法调用，args 为 remoteId。
   * @param result 结果回调。
   */
  handleClearGattCache(call: MethodCall, result: MethodResult): void {
    let remoteId: string = call.args;
    let gatt: ble.GattClientDevice | undefined = this.connectionManager.connectedDevices.get(remoteId);
    if (gatt === null || gatt === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'device is disconnected');
      result.error('clearGattCache', 'device is disconnected', null);
      return;
    }
    result.success(true);
  }
}
