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
import { ble } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BleUtils from './BleUtils';
import HexUtil from './HexUtil';
import BleGattShared, { ChrFound, NotifyRequest, NotifyWriteContext } from './BleGattShared';
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/**
 * 蓝牙通知（Notify/Indicate）管理器。
 *
 * 从 FlutterBluePlusOhosPlugin 主类剥离的通知订阅逻辑：setNotifyValue（开启/关闭特征通知并写 CCCD 描述符）、
 * 每设备 BLECharacteristicChange 回调注册/注销（notifyCallbackMap），以及通知数据到达回调
 * onCharacteristicReceived（读取/通知共用，组装特征值并回传 OnCharacteristicReceived；0x1801/2A05 触发 OnServicesReset）。
 *
 * 方法体来源：1.33.5 FlutterBluePlusOhosPlugin（handleSetNotifyValue / onCharacteristicReceived /
 * characteristicChangeCallbacks），适配 this.X → this.plugin.X、this.parser.X → BleUtils/BleGattShared/HexUtil。
 *
 * 跨 Manager 访问（经 plugin 中介，对齐 2.1.0 拆分）：
 *  - 已连接设备 / 配对等待：plugin.connectionManager.connectedDevices / waitIfBonding。
 *  - 写描述符缓存 / 服务树缓存：plugin.gattCache.writeDescMap / deviceServicesMap。
 *  - 通道回传：plugin.channel。
 *  - locateCharacteristic / getDescriptorFromArray / getPrimaryService：BleGattShared 静态工具。
 *
 * CCCD 值解析（notify/indicate/disable 三分支）保持与 1.33.5 完全一致：enable=false→全零；
 * 否则按 canIndicate/canNotify/forceIndications 优先级取 ENABLE_INDICATION_VALUE/ENABLE_NOTIFICATION_VALUE。
 *
 * BLECharacteristicChange 注册策略（对齐 Android BluetoothGattCallback、与 2.1.0 一致）：
 *  - 在 handleConnected 时即按设备注册一个绑定 deviceId 的闭包（notifyCallbackMap），而非仅在
 *    readCharacteristic 里懒注册 → 即使 App 只 setNotifyValue 不先 read 也能收到通知。
 *  - 闭包内直接用捕获的 deviceId，不再遍历所有已连设备按 UUID 反查 → 多设备相同 UUID 不串台。
 */
export default class BleNotifyManager {
  /** 启用通知的 CCCD 写入值。 */
  public readonly ENABLE_NOTIFICATION_VALUE: Uint8Array = new Uint8Array([0x01, 0x00]);
  /** 启用指示（indication）的 CCCD 写入值。 */
  public readonly ENABLE_INDICATION_VALUE: Uint8Array = new Uint8Array([0x02, 0x00]);
  /** 关闭通知/指示的 CCCD 写入值。 */
  public readonly DISABLE_NOTIFICATION_VALUE: Uint8Array = new Uint8Array([0x00, 0x00]);

  /** 插件引用，用于访问 connectionManager/gattCache/channel。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /**
   * 每个已连接设备对应的 BLECharacteristicChange 回调（deviceId -> 闭包）。
   *
   * OHOS 的 BLECharacteristicChange 回调签名仅为 (characteristic: BLECharacteristic)，不含 deviceId（平台限制）。
   * 但回调是按 GattClientDevice 实例注册的，因此为每个设备创建一个绑定 deviceId 的闭包并注册，
   * 回调时直接用捕获的 deviceId 调用 onCharacteristicReceived —— 无需遍历反查，多设备相同 UUID 不串台。
   */
  public notifyCallbackMap: Map<string, (characteristic: ble.BLECharacteristic) => Promise<void>> = new Map();

  /**
   * 构造通知管理器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * 为指定设备构造 BLECharacteristicChange 回调闭包（绑定 deviceId）并注册到 gatt。
   * 在 handleConnected 时调用（对齐 Android：连接即注册，不依赖 read/notify）。幂等。
   * @param deviceId - 设备 ID
   * @param gatt - 该设备的 GattClientDevice
   */
  public registerCharacteristicChangeCallback(deviceId: string, gatt: ble.GattClientDevice): void {
    // 复用已存在的闭包，避免重复注册导致回调多次执行。
    if (this.notifyCallbackMap.has(deviceId)) {
      return;
    }
    // 回调签名不含 deviceId（平台限制），故在此构造闭包捕获 deviceId，直接派发给 onCharacteristicReceived。
    let callback: (characteristicChangeReq: ble.BLECharacteristic) => Promise<void> =
      async (characteristicChangeReq: ble.BLECharacteristic): Promise<void> => {
      try {
        if (this.plugin.isDetached) {
          return;
        }
        let services: ble.GattService[] | undefined = this.plugin.gattCache.deviceServicesMap.get(deviceId);
        if (services === null || services === undefined) {
          // 设备未发现服务缓存时现场取一次，保证 onCharacteristicReceived 能定位 primary service。
          // 注意：此回调由 BLE 栈异步触发，cache miss 时调 gatt.getServices() 可能与 runGatt
          // 保护的 GATT 操作并发触发 2900011。但正常流程 connect → discoverServices 已缓存服务，
          // 此处几乎不会 miss；即使 miss 并发，catch 兜底吞掉异常，仅丢失本条通知数据，不影响后续。
          services = await gatt.getServices();
          this.plugin.gattCache.deviceServicesMap.set(deviceId, services);
        }
        this.onCharacteristicReceived(deviceId, services, characteristicChangeReq);
      } catch (e) {
        // 顶层兜底：通知数据到达回调异常必须吞掉，避免中断后续特征通知事件。
        BleUtils.log(hilog.LogLevel.ERROR,
          `onCharacteristicChange: unhandled error for ${deviceId}: ${JSON.stringify(e)}`);
      }
    };
    this.notifyCallbackMap.set(deviceId, callback);
    gatt.on('BLECharacteristicChange', callback);
  }

  /**
   * 注销指定设备的 BLECharacteristicChange 回调并从映射表移除。幂等。
   * @param deviceId - 设备 ID
   * @param gatt - 该设备的 GattClientDevice
   */
  public unregisterCharacteristicChangeCallback(deviceId: string, gatt: ble.GattClientDevice): void {
    let callback: ((characteristicChangeReq: ble.BLECharacteristic) => Promise<void>) | undefined =
      this.notifyCallbackMap.get(deviceId);
    if (callback !== null && callback !== undefined) {
      try {
        gatt.off('BLECharacteristicChange', callback);
      } catch (e) {
        BleUtils.log(hilog.LogLevel.WARN,
          `unregisterCharacteristicChangeCallback: off BLECharacteristicChange failed ` +
          `for ${deviceId}: ${JSON.stringify(e)}`);
      }
      this.notifyCallbackMap.delete(deviceId);
    }
  }

  /**
   * 处理 setNotifyValue：开启/关闭特征通知，并写入 CCCD 描述符。
   *
   * 参数（1.33.5 Dart 契约）：remote_id / service_uuid（主服务）/ secondary_service_uuid（included 次服务，可空）/
   * characteristic_uuid / force_indications / enable。
   * @param call - 方法调用
   * @param result - 结果回调
   */
  async setNotifyValue(call: MethodCall, result: MethodResult): Promise<void> {
    let data: Map<string, string | boolean> = call.args;
    let remoteId: string = data.get('remote_id') as string;
    let serviceUuid: string = data.get('service_uuid') as string;
    let secondaryServiceUuid: string = data.get('secondary_service_uuid') as string;
    let characteristicUuid: string = data.get('characteristic_uuid') as string;
    // Dart 传入的是 bool，必须按 boolean 解析；原 as string 会让 "false" 被当作 truthy。
    let forceIndications: boolean = data.get('force_indications') as boolean;
    let enable: boolean = data.get('enable') as boolean;
    let gattMaybe: ble.GattClientDevice | undefined = this.plugin.connectionManager.connectedDevices.get(remoteId);
    if (gattMaybe === null || gattMaybe === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'setNotifyValue failed: device is disconnected');
      result.error('setNotifyValue', 'device is disconnected', null);
      return;
    }
    // 显式收窄为非空引用，供 runGatt 闭包内使用（闭包是独立作用域，外层判空不传导）。
    let gatt: ble.GattClientDevice = gattMaybe;
    // 按设备串行执行 GATT 操作，避免 OHOS BLE 栈 2900011 "operation is busy" 错误。
    // 配对协商期间短暂等待，使后续 GATT 调用基于已配对/加密链路执行。
    await this.plugin.gattCache.runGatt(remoteId, async () => {
      await this.plugin.connectionManager.waitIfBonding();
      // 优先使用 deviceServicesMap 缓存，对齐 read/write 的缓存策略；
      // cache miss 时才调 getServices() 并写回缓存，减少与 BLE 栈的异步交互。
      // getServices() 失败必须 try/catch 并 result.error + return，否则异常穿出 op()
      // 会使 Dart 侧 Future 挂起（见 GattCacheHolder.runGatt 异常隔离契约）。
      let gattServices: ble.GattService[] | undefined =
        this.plugin.gattCache.deviceServicesMap.get(remoteId);
      if (gattServices === null || gattServices === undefined) {
        try {
          gattServices = await gatt.getServices();
        } catch (e) {
          BleUtils.log(hilog.LogLevel.ERROR,
            'setNotifyValue: getServices failed: ' + ((e as BusinessError)?.message ?? 'unknown error'));
          result.error('setNotifyValue',
            'gatt.getServices() failed: ' + ((e as BusinessError)?.message ?? 'unknown error'), null);
          return;
        }
        this.plugin.gattCache.deviceServicesMap.set(remoteId, gattServices);
      }
      if (gattServices === null || gattServices === undefined) {
        BleUtils.log(hilog.LogLevel.ERROR, 'setNotifyValue failed: no service');
        result.error('setNotifyValue', 'no service', null);
        return;
      }
      // 解析目标特征（1.33.5 service_uuid=主/secondary_service_uuid=次 桥接到 foundation 查找；
      // 失败返回 null/undefined，由下方检查处理）。
      let found: ChrFound | undefined = await this.resolveNotifyCharacteristic(serviceUuid, secondaryServiceUuid,
        characteristicUuid, gattServices);
      if (found === null || found === undefined) {
        BleUtils.log(hilog.LogLevel.ERROR, 'setNotifyValue failed: characteristic not found');
        result.error('setNotifyValue', 'characteristic not found', null);
        return;
      }
      if (found.error !== null) {
        let errMsg: string = found.error;
        BleUtils.log(hilog.LogLevel.ERROR, 'setNotifyValue failed: ' + errMsg);
        result.error('setNotifyValue', errMsg, null);
        return;
      }
      let characteristic: ble.BLECharacteristic = found.characteristic as ble.BLECharacteristic;
      let ctx: NotifyWriteContext = {
        gatt: gatt,
        characteristic: characteristic,
        gattServices: gattServices,
        remoteId: remoteId,
      };
      let req: NotifyRequest = { forceIndications: forceIndications, enable: enable };
      await this.applyNotifyAndWriteCccd(ctx, req, result);
    });
  }

  /**
   * 解析 setNotifyValue 的目标特征（桥接 1.33.5 service_uuid=主 / secondary_service_uuid=次 到 foundation 查找）。
   *
   *  - 有次服务：locateCharacteristic(primaryServiceUuid=serviceUuid, serviceUuid=secondaryServiceUuid)。
   *  - 无次服务：locateCharacteristic 的 primaryServiceUuid 形参为 string，无法传 null 表达"非次服务"语义，
   *    故直接用 getServiceFromArray + getCharacteristicFromArray 走等价路径（与 foundation 内部 null 分支一致）。
   * 错误信息与 1.33.5 原内联逻辑完全一致（ChrFound.error 承载，调用方检查）。
   * @returns ChrFound（含特征或错误信息）；次服务路径下 locateCharacteristic 返回 undefined 时透传 undefined。
   */
  private async resolveNotifyCharacteristic(serviceUuid: string, secondaryServiceUuid: string,
    characteristicUuid: string, gattServices: ble.GattService[]): Promise<ChrFound | undefined> {
    let hasSecondary: boolean = secondaryServiceUuid !== null && secondaryServiceUuid !== undefined &&
      secondaryServiceUuid.length > 0;
    if (hasSecondary) {
      return await BleGattShared.locateCharacteristic(serviceUuid, secondaryServiceUuid,
        characteristicUuid, 0, gattServices);
    }
    let primaryService: ble.GattService | null = BleGattShared.getServiceFromArray(serviceUuid, gattServices);
    if (primaryService === null) {
      return new ChrFound(null, 'primary service not found \'' + serviceUuid + '\'');
    }
    let chr: ble.BLECharacteristic | null = BleGattShared.getCharacteristicFromArray(
      characteristicUuid, primaryService.characteristics, gattServices, 0);
    if (chr === null) {
      return new ChrFound(null, 'characteristic not found in service (chr: \'' +
        characteristicUuid + '\' svc: \'' + serviceUuid + '\')');
    }
    return new ChrFound(chr, null);
  }

  /**
   * 使能特征通知并写入 CCCD 描述符。
   *
   * setCharacteristicChangeNotification 注册失败必须回传并提前返回（否则 CCCD 写入成功也无实际通知效果）；
   * 无 CCCD 时回传 success(false)；CCCD 值不支持时由 resolveNotifyDescriptorValue 回传错误。
   * @param gatt - 目标设备 GattClientDevice
   * @param characteristic - 目标特征
   * @param gattServices - 已发现服务树（回传时定位 primary service）
   * @param remoteId - 设备 ID
   * @param forceIndications - 是否强制指示
   * @param enable - true 开启 / false 关闭
   * @param result - 结果回调
   */
  private async applyNotifyAndWriteCccd(ctx: NotifyWriteContext, req: NotifyRequest,
    result: MethodResult): Promise<void> {
    try {
      // 传入用户请求的 enable 而非 properties?.notify：
      // (1) enable=false（用户禁用）时，使用 properties?.notify(true) 会导致本地监听器未关闭；
      // (2) 特征仅支持 indicate 时，properties?.notify 为 false，enable=true 时本地监听器未启用。
      await ctx.gatt.setCharacteristicChangeNotification(ctx.characteristic, req.enable);
    } catch (e) {
      // 通知订阅失败必须回传 Flutter 并提前返回，否则 Dart 侧收到 success 却收不到特征变化事件。
      BleUtils.log(hilog.LogLevel.ERROR,
        'setNotifyValue: setCharacteristicChangeNotification failed: ' + (e as BusinessError)?.message);
      result.error('setNotifyValue',
        'setCharacteristicChangeNotification failed: ' + (e as BusinessError)?.message, null);
      return;
    }
    let descriptor: ble.BLEDescriptor | null =
      BleGattShared.getDescriptorFromArray(BleUtils.CCCD, ctx.characteristic.descriptors);
    if (descriptor === null) {
      // 无 CCCD 描述符：按 1.33.5 行为回传 success(false)。
      result.success(false);
      return;
    }
    let descriptorValue: Uint8Array | null =
      this.resolveNotifyDescriptorValue(ctx.characteristic, req.forceIndications, req.enable, ctx.remoteId, result);
    if (descriptorValue === null) {
      // resolveNotifyDescriptorValue 已通过 result 回传错误。
      return;
    }
    await this.writeNotifyDescriptor(ctx, descriptor, descriptorValue, result);
  }

  /**
   * 解析 CCCD 描述符写入值（enable=通知/指示；disable=全零）。逻辑与 1.33.5 完全一致。
   *
   * 优先级：disable → DISABLE；enable 下 canIndicate→INDICATION，canNotify→NOTIFICATION（后者覆盖前者，
   * 即同时支持时默认 NOTIFY），forceIndications→INDICATION（最终覆盖）。
   * @param characteristic - 目标特征
   * @param forceIndications - 是否强制指示
   * @param enable - true 开启 / false 关闭
   * @param remoteId - 设备 ID（日志用）
   * @param result - 结果回调（属性不支持时回传错误）
   * @returns 描述符值；若属性不支持则通过 result 回传错误并返回 null
   */
  private resolveNotifyDescriptorValue(characteristic: ble.BLECharacteristic, forceIndications: boolean,
    enable: boolean, remoteId: string, result: MethodResult): Uint8Array | null {
    if (!enable) {
      return this.DISABLE_NOTIFICATION_VALUE;
    }
    let characteristicUuid: string = BleUtils.uuidStr(characteristic.characteristicUuid);
    let canNotify: boolean = characteristic.properties?.notify as boolean;
    let canIndicate: boolean = characteristic.properties?.indicate as boolean;
    if (!canIndicate && !canNotify) {
      BleUtils.log(hilog.LogLevel.ERROR,
        'setNotifyValue failed for remoteId=' + remoteId +
        ': neither NOTIFY nor INDICATE properties are supported for chr=' + characteristicUuid);
      result.error('setNotifyValue',
        'neither NOTIFY nor INDICATE properties are supported by this BLE characteristic', null);
      return null;
    }
    if (forceIndications && !canIndicate) {
      BleUtils.log(hilog.LogLevel.ERROR,
        'setNotifyValue failed for remoteId=' + remoteId +
        ': INDICATE not supported for chr=' + characteristicUuid + ', force_indications requested');
      result.error('setNotifyValue', 'INDICATE not supported by this BLE characteristic', null);
      return null;
    }
    let descriptorValue: Uint8Array | null = null;
    if (canIndicate) {
      descriptorValue = this.ENABLE_INDICATION_VALUE;
    }
    if (canNotify) {
      descriptorValue = this.ENABLE_NOTIFICATION_VALUE;
    }
    if (forceIndications) {
      descriptorValue = this.ENABLE_INDICATION_VALUE;
    }
    return descriptorValue;
  }

  /**
   * 缓存 CCCD 写入值、写入描述符，并在完成后回传 OnDescriptorWritten。
   *
   * 采用 async/await + try-catch：写入失败时清理缓存并回传 result.error。
   * 响应 value 直接取自 descriptor.descriptorValue（与 1.33.5 一致），经 HexUtil.formatHexString 编码为十六进制串。
   * @param gatt - 目标设备 GattClientDevice
   * @param characteristic - 目标特征（回传时定位 primary service）
   * @param gattServices - 已发现服务树
   * @param remoteId - 设备 ID
   * @param descriptor - CCCD 描述符
   * @param descriptorValue - CCCD 写入值
   * @param result - 结果回调
   */
  private async writeNotifyDescriptor(ctx: NotifyWriteContext, descriptor: ble.BLEDescriptor,
    descriptorValue: Uint8Array, result: MethodResult): Promise<void> {
    // 记录正在写入的值（与 1.33.5 writeDesc 缓存对齐；GattCacheHolder 要求 Uint8Array）。
    let key: string = this.buildWriteNotifyKey(ctx.remoteId, descriptor);
    this.plugin.gattCache.writeDescMap.set(key, descriptorValue);
    if (descriptorValue) {
      let u8Array: Uint8Array = new Uint8Array(descriptorValue);
      descriptor.descriptorValue = BleUtils.typedArrayToBuffer(u8Array);
    }
    try {
      await ctx.gatt.writeDescriptorValue(descriptor);
      this.emitNotifyDescResponse(ctx.gattServices, ctx.remoteId, ctx.characteristic, descriptor, result);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR,
        'setNotifyValue failed for remoteId=' + ctx.remoteId + ': gatt.writeDescriptor() returned false');
      // 写入失败：清理刚缓存的写入值，避免 writeDescMap 残留。
      this.plugin.gattCache.writeDescMap.delete(key);
      result.error('setNotifyValue', 'gatt.writeDescriptor() returned false', null);
    }
  }

  /**
   * 构造通知 CCCD 写入缓存键（remoteId:serviceUuid:characteristicUuid:descriptorUuid）。
   * UUID 经 uuidStr 规范化，保证 set/delete 与响应侧一致。
   * @param remoteId - 设备 ID
   * @param descriptor - CCCD 描述符（提供 service/characteristic/descriptor UUID）
   * @returns 缓存键
   */
  private buildWriteNotifyKey(remoteId: string, descriptor: ble.BLEDescriptor): string {
    return remoteId + ':' + BleUtils.uuidStr(descriptor.serviceUuid) + ':' +
      BleUtils.uuidStr(descriptor.characteristicUuid) + ':' + BleUtils.uuidStr(descriptor.descriptorUuid);
  }

  /**
   * 写入成功后：组装并回传 OnDescriptorWritten。
   *
   * 响应字段与 1.33.5 契约一致：service_uuid 规范化（uuidStr），characteristic_uuid / descriptor_uuid
   * 取原生值；特征位于次（included）服务时附带 secondary_service_uuid。value 取 descriptor.descriptorValue
   * 经 HexUtil.formatHexString 编码。success 固定 1 / error_code 固定 0。
   * @param gattServices - 已发现服务树（定位 primary service）
   * @param remoteId - 设备 ID
   * @param characteristic - 目标特征
   * @param descriptor - 写入的 CCCD 描述符
   * @param result - 结果回调
   */
  private emitNotifyDescResponse(gattServices: ble.GattService[], remoteId: string,
    characteristic: ble.BLECharacteristic, descriptor: ble.BLEDescriptor, result: MethodResult): void {
    // readAndWriteServicePair 在 foundation 不存在，用 getPrimaryService 等价重建：
    //  - 返回非 null 表示特征位于次（included）服务，此时附带 secondary_service_uuid（=特征所属服务）。
    let primaryService: ble.GattService | null = BleGattShared.getPrimaryService(gattServices, characteristic);
    let response: Map<string, string | number> = new Map<string, string | number>();
    response.set('remote_id', remoteId);
    // 特征位于次（included）服务时:service_uuid=主服务(includer),secondary_service_uuid=特征所属次服务;
    // 位于主服务时:仅设 service_uuid=特征所属服务。与 onCharacteristicReceived 保持一致。
    if (primaryService !== null) {
      response.set('service_uuid', BleUtils.uuidStr(primaryService.serviceUuid));
      response.set('secondary_service_uuid', BleUtils.uuidStr(descriptor.serviceUuid));
    } else {
      response.set('service_uuid', BleUtils.uuidStr(descriptor.serviceUuid));
    }
    response.set('characteristic_uuid', descriptor.characteristicUuid);
    response.set('descriptor_uuid', descriptor.descriptorUuid);
    let unie8: Uint8Array = new Uint8Array(descriptor.descriptorValue);
    response.set('value', HexUtil.formatHexString(unie8));
    response.set('success', 1);
    response.set('error_code', 0);
    response.set('error_string', 'GATT_SUCCESS');
    this.plugin.channel?.invokeMethod('OnDescriptorWritten', response);
    result.success(true);
  }

  /**
   * 读取/通知回调中共用的特征值到达处理：组装 BmCharacteristicData 并回传 OnCharacteristicReceived。
   *
   * Generic Attribute service 0x1801 的 Service Changed 0x2A05 触发 OnServicesReset。
   * 响应字段与 1.33.5 契约一致：service_uuid / characteristic_uuid 均规范化（uuidStr），value 经
   * HexUtil.formatHexString 编码；特征位于次服务时附带 secondary_service_uuid。
   * @param address - 设备 ID
   * @param services - 该设备的 GATT 服务数组
   * @param characteristic - 到达的特征
   */
  onCharacteristicReceived(address: string, services: ble.GattService[],
    characteristic: ble.BLECharacteristic): void {
    // Generic Attribute service 0x1801 / Service Changed 0x2A05 → 通知 Dart 侧失效服务缓存。
    // uuidStr 返回小写，2A05 比较需 toUpperCase（与 2.1.0 一致，修正 1.33.5 的大小写不匹配）。
    if (BleUtils.uuidStr(characteristic.serviceUuid) === '1801') {
      if (BleUtils.uuidStr(characteristic.characteristicUuid).toUpperCase() === '2A05') {
        // 设备服务结构发生变化，清除服务缓存以强制 discoverServices 重新获取。
        // 否则 read/write/setNotifyValue 仍使用旧缓存，可能定位到已不存在的特征。
        this.plugin.gattCache.deviceServicesMap.delete(address);
        let servicesResetResp: Map<string, string> = BleUtils.buildBluetoothDevice(address);
        this.plugin.channel?.invokeMethod('OnServicesReset', servicesResetResp);
      }
    }
    let primaryService: ble.GattService | null = BleGattShared.getPrimaryService(services, characteristic);
    let response: Map<string, string | number> = new Map<string, string | number>();
    response.set('remote_id', address);
    if (primaryService !== null) {
      // 特征位于次（included）服务：service_uuid=主（includer），secondary_service_uuid=次（特征所属）。
      response.set('service_uuid', BleUtils.uuidStr(primaryService.serviceUuid));
      response.set('secondary_service_uuid', BleUtils.uuidStr(characteristic.serviceUuid));
    } else {
      response.set('service_uuid', BleUtils.uuidStr(characteristic.serviceUuid));
    }
    response.set('characteristic_uuid', BleUtils.uuidStr(characteristic.characteristicUuid));
    response.set('value', HexUtil.formatHexString(new Uint8Array(characteristic.characteristicValue)));
    response.set('success', 1);
    response.set('error_code', 0);
    response.set('error_string', 'GATT_SUCCESS');
    this.plugin.channel?.invokeMethod('OnCharacteristicReceived', response);
  }

  /** 清空所有通知回调映射。cleanup 全局清理时调用（gatt 的 off 由 cleanup 遍历 per-device 完成）。 */
  clearAll(): void {
    this.notifyCallbackMap.clear();
  }
}
