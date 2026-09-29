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
import BleGattShared, { ChrFound, DescriptorUuidArgs, DescriptorWriteResult } from './BleGattShared';
import HexUtil from './HexUtil';
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/**
 * 蓝牙描述符（Descriptor）读写管理器。
 *
 * 从 FlutterBluePlusOhosPlugin 剥离的描述符读写逻辑：readDescriptor（读取描述符值并回传
 * OnDescriptorRead）、writeDescriptor（MTU 长度校验后写入并回传 OnDescriptorWritten）。
 *
 * 跨 Manager 访问（与 BleMtuManager / BleBondManager 访问 plugin.X 的模式一致）：
 *  - 已连接设备 GattClientDevice → plugin.connectionManager.connectedDevices
 *  - 配绑定等待 → plugin.connectionManager.waitIfBonding()
 *  - 共享缓存 mtuMap / writeDescMap → plugin.gattCache
 *  - Flutter 通道 → plugin.channel
 *  - 日志 → BleUtils.log
 *
 * 1.33.5 响应契约：value 为十六进制字符串（与 1.33.5 Dart 侧 OnDescriptorRead/Written 约定一致），
 * service_uuid 为主服务 UUID、secondary_service_uuid 在次服务场景下填充。响应字段命名与
 * 1.33.5 主插件保持一致，未切换到 2.1.0 的 primary_service_uuid/instance_id 形式。
 *
 * locateCharacteristic / getReadDescriptorFromArray / getPrimaryService 为 BleGattShared 静态工具：
 *  - 1.33.5 的 service_uuid（主）/ secondary_service_uuid（次）映射为 BleGattShared.locateCharacteristic
 *    的 (primaryServiceUuid, serviceUuid) 参数对：无次服务时两者同为主服务 UUID（查找时
 *    includeServices 内自然找不到主自身，回退到主服务特征表，行为与 1.33.5 一致）。
 *  - 1.33.5 的 descriptorReadServicePair / readAndWriteServicePair 主次对解析，等价地由
 *    BleGattShared.getPrimaryService(services, characteristic) 表达：返回 null 表示特征在主服务，
 *    返回非 null 表示返回值即所属主服务（次服务场景）。
 *
 * 方法体来源：1.33.5 FlutterBluePlusOhosPlugin.handleReadDescriptor / handleWriteDescriptor，
 * 适配 this.connectedDevices → this.plugin.connectionManager.connectedDevices、
 * this.waitIfBonding → this.plugin.connectionManager.waitIfBonding()、
 * this.mtu → this.plugin.gattCache.mtuMap、this.writeDesc → this.plugin.gattCache.writeDescMap、
 * this.parser.* → BleUtils.* / BleGattShared.*、this.log → BleUtils.log、
 * this.channel → this.plugin.channel。
 */
export default class BleDescriptorManager {
  /** 插件引用，用于访问 connectionManager/gattCache/channel。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /**
   * 构造描述符读写管理器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * 处理 readDescriptor：读取指定描述符值并通过 OnDescriptorRead 回传。
   *
   * 流程：解析 remote_id/service_uuid/secondary_service_uuid/characteristic_uuid/descriptor_uuid →
   * 反查已连接 GattClientDevice → waitIfBonding → getServices → locateCharacteristic →
   * getReadDescriptorFromArray → readDescriptorValue（try-catch）→ 组装 OnDescriptorRead
   * （remote_id/service_uuid/secondary_service_uuid/characteristic_uuid/descriptor_uuid/value/
   * success/error_code/error_string）→ channel.invokeMethod → result.success(true)。
   *
   * @param call - 方法调用，args 含 remote_id/service_uuid/secondary_service_uuid/
   * characteristic_uuid/descriptor_uuid
   * @param result - 结果回调
   */
  async readDescriptor(call: MethodCall, result: MethodResult): Promise<void> {
    let uuidArgs: DescriptorUuidArgs = this.parseDescriptorArgs(call);
    let gattMaybe: ble.GattClientDevice | undefined =
      this.plugin.connectionManager.connectedDevices.get(uuidArgs.remoteId);
    if (gattMaybe === null || gattMaybe === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'readDescriptor failed: device is disconnected');
      result.error('readDescriptor', 'device is disconnected', null);
      return;
    }
    // 显式收窄为非空引用，供 runGatt 闭包内使用（闭包是独立作用域，外层判空不传导）。
    let gatt: ble.GattClientDevice = gattMaybe;
    // 按设备串行执行 GATT 操作，避免 OHOS BLE 栈 2900011 "operation is busy" 错误。
    // 先确认已连接,再等待配对完成(避免设备已断连时白白轮询等待 3s)。
    await this.plugin.connectionManager.waitIfBonding();
    // 解析特征/描述符（getServices → locateCharacteristic → getReadDescriptorFromArray，
    // waitIfBonding 已在上层调用）。解析失败时已在内部 result.error 并返回 null，调用方直接 return。
    await this.plugin.gattCache.runGatt(uuidArgs.remoteId, async () => {
      let resolved: DescriptorTarget | null =
        await this.resolveDescriptor('readDescriptor', gatt, uuidArgs, result);
      if (resolved === null) {
        return;
      }
      // 执行读取并回传（失败路径已在内部 result.error 并 return）。
      await this.executeReadDescriptor(uuidArgs.remoteId, gatt, resolved, result);
    });
  }

  /**
   * 解析 readDescriptor/writeDescriptor 调用参数：从 call.args 收窄为强类型 DescriptorUuidArgs。
   * @param call 方法调用，args 含 remote_id/service_uuid/secondary_service_uuid/characteristic_uuid/descriptor_uuid
   * @returns UUID 组。
   */
  private parseDescriptorArgs(call: MethodCall): DescriptorUuidArgs {
    let data: Map<string, string> = call.args;
    return {
      remoteId: data.get('remote_id') as string,
      serviceUuid: data.get('service_uuid') as string,
      secondaryServiceUuid: data.get('secondary_service_uuid') as string,
      characteristicUuid: data.get('characteristic_uuid') as string,
      descriptorUuid: data.get('descriptor_uuid') as string,
    };
  }

  /**
   * 执行描述符读取并组装 OnDescriptorRead 回传。
   * readDescriptorValue 失败时清理并通过 result.error 回传错误后 return；成功时构造响应并 result.success(true)。
   */
  private async executeReadDescriptor(remoteId: string, gatt: ble.GattClientDevice,
    resolved: DescriptorTarget, result: MethodResult): Promise<void> {
    let characteristic: ble.BLECharacteristic = resolved.characteristic;
    let descriptor: ble.BLEDescriptor = resolved.descriptor;
    let services: ble.GattService[] = resolved.services;
    let errorMessage: string = '';
    let errorCode: number = 0;
    let readDescriptor: ble.BLEDescriptor | null = null;
    // 失败标记：异常时置 true；上方 catch 已 return，到达响应构造时必为 false（success=1）。
    let readDescriptorFlag: boolean = false;
    try {
      readDescriptor = await gatt.readDescriptorValue(descriptor);
    } catch (e) {
      errorMessage = (e as BusinessError)?.message ?? '';
      errorCode = (e as BusinessError)?.code ?? 0;
      readDescriptorFlag = true;
      BleUtils.log(hilog.LogLevel.ERROR,
        `readDescriptor failed: gatt.readDescriptor() returned false, ` +
        `errorCode=${errorCode}, errorMessage=${errorMessage}`);
      result.error('readDescriptor', 'gatt.readDescriptor() returned false', null);
      return;
    }
    // 组装 OnDescriptorRead 并回传（1.33.5 契约，value 为读取字节的十六进制字符串）。
    this.buildDescriptorReadResponse(remoteId, services, characteristic, readDescriptor, readDescriptorFlag,
      errorCode, errorMessage);
    result.success(true);
  }

  /**
   * read/write 共用的描述符解析子步骤（getServices → locateCharacteristic → getReadDescriptorFromArray）。
   *
   * 合并自原 resolveDescriptorForRead / resolveDescriptorForWrite（两者仅日志前缀与 waitIfBonding
   * 时机不同；waitIfBonding 统一由上层在连接检查前调用）。解析失败时通过 result.error 回传错误
   * （错误码/消息与 1.33.5 原内联逻辑一致）并返回 null，调用方见 null 即 return。
   * @param methodName 'readDescriptor' 或 'writeDescriptor'，用于日志与 error code。
   * @param args UUID 组（含 descriptorUuid）。
   * @returns 解析结果（characteristic/descriptor/services）；失败返回 null。
   */
  private async resolveDescriptor(methodName: string, gatt: ble.GattClientDevice,
    args: DescriptorUuidArgs, result: MethodResult): Promise<DescriptorTarget | null> {
    // 优先使用 deviceServicesMap 缓存，cache miss 时才调 getServices() 并写回缓存，
    // 减少与 BLE 栈的异步交互次数（避免与其它 GATT 操作并发冲突触发 2900099）。
    // getServices() 失败必须 try/catch 并 result.error + return null，否则异常穿出 op()
    // 会使 Dart 侧 Future 挂起（见 GattCacheHolder.runGatt 异常隔离契约）。
    let services: ble.GattService[] | undefined =
      this.plugin.gattCache.deviceServicesMap.get(args.remoteId);
    if (services === null || services === undefined) {
      try {
        services = await gatt.getServices();
      } catch (e) {
        BleUtils.log(hilog.LogLevel.ERROR,
          `${methodName}: getServices failed: ${(e as BusinessError)?.message ?? 'unknown error'}`);
        result.error(methodName,
          `gatt.getServices() failed: ${(e as BusinessError)?.message ?? 'unknown error'}`, null);
        return null;
      }
      this.plugin.gattCache.deviceServicesMap.set(args.remoteId, services);
    }
    // 1.33.5 契约：serviceUuid 为主服务 UUID；
    // secondaryServiceUuid 为次服务 UUID（空表示无次服务）。
    // 映射到 BleGattShared.locateCharacteristic(primaryServiceUuid, serviceUuid, ...)：
    //  - 有次服务：primaryServiceUuid=serviceUuid（主），serviceUuid=secondaryServiceUuid（次）。
    //  - 无次服务：primaryServiceUuid=secondaryServiceUuid（运行时为 null），
    //    serviceUuid=serviceUuid（主）；
    //    与 BleCharacteristicManager.mapServiceArgs 一致：locateCharacteristic 检测 primaryServiceUuid
    //    为 null 时回退以 serviceUuid 作主服务查找；传非 null 会误判次服务查找并报
    //    "secondary service not found"。
    let isSecondary: boolean = args.secondaryServiceUuid !== null && args.secondaryServiceUuid !== undefined &&
      args.secondaryServiceUuid.length > 0;
    let primaryForLookup: string = isSecondary ? args.serviceUuid : args.secondaryServiceUuid;
    let serviceForLookup: string = isSecondary ? args.secondaryServiceUuid : args.serviceUuid;
    let found: ChrFound | undefined =
      await BleGattShared.locateCharacteristic(primaryForLookup, serviceForLookup, args.characteristicUuid, 0,
        services) as ChrFound;
    if (found === undefined || found === null) {
      BleUtils.log(hilog.LogLevel.ERROR, `${methodName} failed: characteristic not found`);
      result.error(methodName, 'characteristic not found', null);
      return null;
    }
    if (found.error !== null) {
      let errMsg: string = found.error as string;
      BleUtils.log(hilog.LogLevel.ERROR, `${methodName} failed: ${errMsg}`);
      result.error(methodName, errMsg, null);
      return null;
    }
    let characteristic: ble.BLECharacteristic = found.characteristic as ble.BLECharacteristic;
    let descriptor: ble.BLEDescriptor =
      BleGattShared.getReadDescriptorFromArray(args.descriptorUuid, characteristic.descriptors) as ble.BLEDescriptor;
    if (descriptor === null) {
      let s: string =
        'descriptor not found on characteristic. (desc: ' + args.descriptorUuid + ' chr: ' +
        args.characteristicUuid + ')';
      BleUtils.log(hilog.LogLevel.ERROR, `${methodName} failed: ${s}`);
      result.error(methodName, s, null);
      return null;
    }
    return new DescriptorTarget(characteristic, descriptor, services);
  }

  /**
   * 组装 OnDescriptorRead 响应 Map 并通过 channel 回传（1.33.5 契约）。
   *
   * 主/次服务对解析等价于 1.33.5 的 descriptorReadServicePair(service, services)：getPrimaryService
   * 返回 null 表示特征在主服务（service_uuid=特征所属服务），返回非 null 表示特征在次服务
   * （service_uuid=返回的主服务，secondary_service_uuid=特征所属服务）。
   * value 为读取字节的十六进制字符串。字段顺序与类型须与 Dart 侧契约完全一致。
   */
  private buildDescriptorReadResponse(remoteId: string, services: ble.GattService[],
    characteristic: ble.BLECharacteristic, readDescriptor: ble.BLEDescriptor,
    readDescriptorFlag: boolean, errorCode: number, errorMessage: string): void {
    let primaryService: ble.GattService | null = BleGattShared.getPrimaryService(services, characteristic);
    let response: Map<string, string | number> = new Map<string, string | number>();
    response.set('remote_id', remoteId);
    if (primaryService !== null) {
      // 次服务场景：service_uuid 为主服务，secondary_service_uuid 为特征所属（次）服务。
      response.set('service_uuid', BleUtils.uuidStr(primaryService.serviceUuid));
      response.set('secondary_service_uuid', BleUtils.uuidStr(readDescriptor.serviceUuid));
    } else {
      // 主服务场景：service_uuid 即特征所属服务，无 secondary。
      response.set('service_uuid', BleUtils.uuidStr(readDescriptor.serviceUuid));
    }
    response.set('characteristic_uuid', BleUtils.uuidStr(readDescriptor.characteristicUuid));
    response.set('descriptor_uuid', BleUtils.uuidStr(readDescriptor.descriptorUuid));
    response.set('value', HexUtil.formatHexString(new Uint8Array(readDescriptor.descriptorValue)));
    response.set('success', readDescriptorFlag ? 0 : 1);
    response.set('error_code', errorCode);
    response.set('error_string', errorMessage);
    this.plugin.channel?.invokeMethod('OnDescriptorRead', response);
  }

  /**
   * 处理 writeDescriptor：写入指定描述符值（含 MTU 长度校验）并通过 OnDescriptorWritten 回传。
   *
   * 流程：解析 remote_id/service_uuid/secondary_service_uuid/characteristic_uuid/descriptor_uuid/value →
   * 反查已连接 GattClientDevice → getServices → locateCharacteristic → getReadDescriptorFromArray →
   * MTU 长度校验（mtuMap 缺项兜底 23）→ 缓存写入值到 writeDescMap → writeDescriptorValue
   * （then 组装 OnDescriptorWritten 并回传，catch 回 result.error）→ result.success(true)。
   *
   * @param call - 方法调用，args 含 remote_id/service_uuid/secondary_service_uuid/
   * characteristic_uuid/descriptor_uuid/value（十六进制字符串）
   * @param result - 结果回调
   */
  async writeDescriptor(call: MethodCall, result: MethodResult): Promise<void> {
    let data: Map<string, object | string> = call.args;
    let remoteId = data.get('remote_id') as string;
    let uuidArgs: DescriptorUuidArgs = {
      remoteId: remoteId,
      serviceUuid: data.get('service_uuid') as string,
      secondaryServiceUuid: data.get('secondary_service_uuid') as string,
      characteristicUuid: data.get('characteristic_uuid') as string,
      descriptorUuid: data.get('descriptor_uuid') as string,
    };
    let value = data.get('value') as string;
    let gattMaybe: ble.GattClientDevice | undefined =
      this.plugin.connectionManager.connectedDevices.get(remoteId);
    if (gattMaybe === null || gattMaybe === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'writeDescriptor failed: device is disconnected');
      result.error('writeDescriptor', 'device is disconnected', null);
      return;
    }
    // 显式收窄为非空引用，供 runGatt 闭包内使用（闭包是独立作用域，外层判空不传导）。
    let gatt: ble.GattClientDevice = gattMaybe;
    await this.plugin.connectionManager.waitIfBonding();
    // 按设备串行执行 GATT 操作，避免 OHOS BLE 栈 2900011 "operation is busy" 错误。
    // 解析特征/描述符（getServices → locateCharacteristic → getReadDescriptorFromArray）；
    // 解析失败时已在内部 result.error 并返回 null，调用方直接 return。
    await this.plugin.gattCache.runGatt(remoteId, async () => {
      let resolved: DescriptorTarget | null =
        await this.resolveDescriptor('writeDescriptor', gatt, uuidArgs, result);
      if (resolved === null) {
        return;
      }
      // MTU 长度校验：超长时已 result.error 并返回 false。
      let valueBytes: Uint8Array = HexUtil.hexStringToBytes(value) as Uint8Array;
      if (!this.validateDescriptorPayload(remoteId, valueBytes, result)) {
        return;
      }
      // 执行写入 + 回传响应（失败时已在内部 result.error）。
      await this.executeDescriptorWriteAndRespond(gatt, resolved, uuidArgs, value, valueBytes, result);
    });
  }

  /**
   * writeDescriptor 的 MTU 负载校验：描述符负载不得超过 MTU-3（扣除 3 字节 ATT 操作头）。
   * mtuMap 缺项时兜底为默认值 23，避免 undefined-3=NaN 致校验恒放行。超长时 result.error 并返回 false。
   */
  private validateDescriptorPayload(remoteId: string, valueBytes: Uint8Array | null,
    result: MethodResult): boolean {
    let mtu: number | undefined = this.plugin.gattCache.mtuMap.get(remoteId);
    if (mtu === null || mtu === undefined) {
      mtu = 23;
    }
    let valueBytesLength: number = valueBytes !== null ? valueBytes.byteLength : 0;
    if ((mtu - 3) < valueBytesLength) {
      let s: string = 'data longer than mtu allows. dataLength: ' + valueBytesLength + '> max: ' + (mtu - 3);
      BleUtils.log(hilog.LogLevel.ERROR, `writeDescriptor failed: ${s}`);
      result.error('writeDescriptor', s, null);
      return false;
    }
    return true;
  }

  /**
   * writeDescriptor 的缓存写入 + 执行写入 + 响应回传。
   * 失败时（attemptWriteDescriptor 内部）已清理缓存并 result.error。
   */
  private async executeDescriptorWriteAndRespond(gatt: ble.GattClientDevice, resolved: DescriptorTarget,
    uuidArgs: DescriptorUuidArgs, value: string, valueBytes: Uint8Array, result: MethodResult): Promise<void> {
    let characteristic: ble.BLECharacteristic = resolved.characteristic;
    let descriptor: ble.BLEDescriptor = resolved.descriptor;
    // 缓存写入值（writeDescMap，值类型为 Uint8Array），以便回传时取回实际写入的字节。
    // 1.33.5 响应直接回传输入的十六进制 value 字符串，此处缓存用于与 2.1.0 回调式取回保持一致的键语义。
    let key: string = this.buildWriteDescKey(uuidArgs.remoteId, uuidArgs.serviceUuid, uuidArgs.secondaryServiceUuid,
      uuidArgs.characteristicUuid, uuidArgs.descriptorUuid);
    this.plugin.gattCache.writeDescMap.set(key, valueBytes);
    descriptor.descriptorValue = BleUtils.typedArrayToBuffer(valueBytes);
    // 执行写入：失败时已在内部清理缓存并 result.error，返回 false；成功返回 true。
    if (!await this.attemptWriteDescriptor(gatt, descriptor, key, result)) {
      return;
    }
    // 组装 OnDescriptorWritten 并回传（1.33.5 契约，value 回传输入的十六进制字符串；成功路径 success=1）。
    let writeResult: DescriptorWriteResult = {
      value: value,
      writeDescriptorFlag: true,
      errorCode: 0,
      errorMessage: '',
    };
    this.buildDescriptorWrittenResponse(uuidArgs.remoteId, resolved.services, characteristic, descriptor,
      writeResult);
    // 必须返回结果，否则 Dart Future 永不完成。
    result.success(true);
  }

  /**
   * 执行描述符写入并处理失败路径。
   *
   * 失败（writeDescriptorValue 抛异常）时清理 writeDescMap 缓存、记录日志并通过 result.error 回传错误
   * （消息与 1.33.5 原内联逻辑完全一致），返回 false；成功返回 true（响应由调用方处理）。
   * @returns true 表示写入成功；false 表示失败（已 result.error，调用方直接 return）。
   */
  private async attemptWriteDescriptor(gatt: ble.GattClientDevice, descriptor: ble.BLEDescriptor,
    key: string, result: MethodResult): Promise<boolean> {
    try {
      await gatt.writeDescriptorValue(descriptor);
    } catch (e) {
      let errorCode: number = (e as BusinessError)?.code ?? 0;
      let errorMessage: string = (e as BusinessError)?.message ?? '';
      // 写入失败：清理刚缓存的写入值，避免 writeDescMap 残留（clearForDevice 不清此 Map）。
      this.plugin.gattCache.writeDescMap.delete(key);
      BleUtils.log(hilog.LogLevel.ERROR,
        `writeDescriptor failed: gatt.writeDescriptor() returned false, ` +
        `errorCode=${errorCode}, errorMessage=${errorMessage}`);
      result.error('writeDescriptor', 'gatt.writeDescriptor() returned false', null);
      return false;
    }
    return true;
  }

  /**
   * 组装 OnDescriptorWritten 响应 Map 并通过 channel 回传（1.33.5 契约）。
   *
   * 主/次服务对解析等价于 1.33.5 的 readAndWriteServicePair(gattService, characteristic)；
   * value 直接回传输入的十六进制字符串。字段顺序与类型须与 Dart 侧契约完全一致。
   */
  private buildDescriptorWrittenResponse(remoteId: string, gattService: ble.GattService[],
    characteristic: ble.BLECharacteristic, descriptor: ble.BLEDescriptor,
    writeResult: DescriptorWriteResult): void {
    // 主/次服务对解析：等价于 1.33.5 的 readAndWriteServicePair(gattService, characteristic)。
    let primaryService: ble.GattService | null = BleGattShared.getPrimaryService(gattService, characteristic);
    let respServiceUuid: string;
    let respSecondaryServiceUuid: string | null;
    if (primaryService !== null) {
      // 次服务场景：service_uuid 为主服务，secondary_service_uuid 为特征所属（次）服务。
      respServiceUuid = BleUtils.uuidStr(primaryService.serviceUuid);
      respSecondaryServiceUuid = BleUtils.uuidStr(characteristic.serviceUuid);
    } else {
      // 主服务场景：service_uuid 即特征所属服务，无 secondary。
      respServiceUuid = BleUtils.uuidStr(characteristic.serviceUuid);
      respSecondaryServiceUuid = null;
    }
    let respCharacteristicUuid: string = BleUtils.uuidStr(descriptor.characteristicUuid) as string;
    let respDescriptorUuid: string = BleUtils.uuidStr(descriptor.descriptorUuid);
    let response: Map<string, string | number> = new Map<string, string | number>();
    response.set('remote_id', remoteId);
    response.set('service_uuid', respServiceUuid);
    if (respSecondaryServiceUuid !== null) {
      response.set('secondary_service_uuid', respSecondaryServiceUuid);
    }
    response.set('characteristic_uuid', respCharacteristicUuid);
    response.set('descriptor_uuid', respDescriptorUuid);
    response.set('value', writeResult.value);
    response.set('success', writeResult.writeDescriptorFlag ? 1 : 0);
    response.set('error_code', writeResult.errorCode);
    response.set('error_string', writeResult.errorMessage);
    this.plugin.channel?.invokeMethod('OnDescriptorWritten', response);
  }

  /**
   * 构造写描述符缓存键（remoteId:serviceUuid:secondaryServiceUuid:characteristicUuid:descriptorUuid）。
   * primaryServiceUuid 为 null 时归一化为 ''，须与响应侧重建逻辑保持一致。
   * @param remoteId - 设备 ID
   * @param serviceUuid - 主服务 UUID（1.33.5 契约）
   * @param secondaryServiceUuid - 次服务 UUID（可空）
   * @param characteristicUuid - 特征 UUID
   * @param descriptorUuid - 描述符 UUID
   * @returns 缓存键
   */
  private buildWriteDescKey(remoteId: string, serviceUuid: string, secondaryServiceUuid: string,
    characteristicUuid: string, descriptorUuid: string): string {
    let secondary: string = (secondaryServiceUuid === null || secondaryServiceUuid === undefined) ?
      '' : secondaryServiceUuid;
    return remoteId + ':' + serviceUuid + ':' + secondary + ':' +
      characteristicUuid + ':' + descriptorUuid;
  }
}

/**
 * readDescriptor / writeDescriptor 特征+描述符解析子步骤的返回值。
 *
 * 将 locateCharacteristic 解析出的 characteristic、getReadDescriptorFromArray 解析出的 descriptor
 * 与 getServices 返回的服务树打包返回，使解析方法签名收敛为单个返回值（避免多出参）。
 */
class DescriptorTarget {
  /** 定位到的特征。 */
  public characteristic: ble.BLECharacteristic;
  /** 定位到的描述符。 */
  public descriptor: ble.BLEDescriptor;
  /** getServices 返回的服务树（响应构造时定位 primary service）。 */
  public services: ble.GattService[];

  constructor(characteristic: ble.BLECharacteristic, descriptor: ble.BLEDescriptor,
    services: ble.GattService[]) {
    this.characteristic = characteristic;
    this.descriptor = descriptor;
    this.services = services;
  }
}
