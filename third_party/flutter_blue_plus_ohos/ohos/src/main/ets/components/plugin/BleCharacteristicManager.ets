/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
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
import BleGattShared, { ChrFound, UuidArgs, WriteCharacteristicArgs } from './BleGattShared';
import HexUtil from './HexUtil';
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/**
 * 蓝牙特征（Characteristic）读写管理器。
 *
 * 从 FlutterBluePlusOhosPlugin 剥离的特征读写逻辑：handleReadCharacteristic（读取特征值、
 * 回传 OnCharacteristicReceived、并按设备注册/刷新 BLECharacteristicChange 监听）与
 * handleWriteCharacteristic（属性/负载校验后写入并回传 OnCharacteristicWritten）。
 *
 * 业务逻辑体源自 1.33.5 主类 handleReadCharacteristic / handleWriteCharacteristic / getMaxPayload，
 * 保持原语义不变（参数名 service_uuid/secondary_service_uuid、value 为十六进制字符串、
 * read/write 失败文案已对齐 2.1.0 dev 分支/Android/iOS（"gatt.readCharacteristic() failed with error: <msg>"）、
 * 写回传使用输入 value），仅做访问路径适配：
 *  - this.connectedDevices → this.plugin.connectionManager.connectedDevices
 *  - this.waitIfBonding() → this.plugin.connectionManager.waitIfBonding()
 *  - this.mtu → this.plugin.gattCache.mtuMap（经 BleGattShared.getMaxPayload 透传）
 *  - this.writeChr → this.plugin.gattCache.writeChrMap（Map<string, Uint8Array>，存解析后字节数组）
 *  - this.characteristicChangeCallbacks → 本类自有字段（从主类迁入）
 *  - this.parser.locateCharacteristic → BleGattShared.locateCharacteristic（参数语义见 mapServiceArgs）
 *  - this.parser.typedArrayToBuffer → BleUtils.typedArrayToBuffer
 *  - this.log → BleUtils.log
 *  - this.channel → this.plugin.channel
 *  - this.onCharacteristicReceived → this.plugin.onCharacteristicReceived
 *    （onCharacteristicReceived 发射器当前仍在主类；2.1.0 计划迁入 BleNotifyManager，
 *     届时改为 this.plugin.notifyManager.onCharacteristicReceived）
 *
 * 参数语义映射：1.33.5 约定 service_uuid 为主服务、secondary_service_uuid 为次服务（特征实际所在）；
 * BleGattShared.locateCharacteristic 约定 primaryServiceUuid 非空时按次服务查找。两者经
 * {@link mapServiceArgs} 统一映射，instanceId 因 1.33.5 未传递固定为 0（首个匹配）。
 */
export default class BleCharacteristicManager {
  /** 插件引用，用于访问 connectionManager/gattCache/channel/onCharacteristicReceived。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /**
   * 构造特征读写管理器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * 处理 readCharacteristic：读取指定特征值，回传 OnCharacteristicReceived，
   * 并按设备注册/刷新 BLECharacteristicChange 监听（KEEP 1.33.5 原逻辑）。
   *
   * @param call - 方法调用，args 含 remote_id/service_uuid/secondary_service_uuid/characteristic_uuid
   * @param result - 结果回调
   */
  async handleReadCharacteristic(call: MethodCall, result: MethodResult): Promise<void> {
    let data: Map<string, string> = call.args as Map<string, string>;
    let remoteId: string = data.get('remote_id') as string;
    let serviceUuid: string = data.get('service_uuid') as string;
    let secondaryServiceUuid: string = data.get('secondary_service_uuid') as string;
    let characteristicUuid: string = data.get('characteristic_uuid') as string;

    let gattMaybe: ble.GattClientDevice | undefined = this.plugin.connectionManager.connectedDevices.get(remoteId);
    // 先做 null 检查，再调用 getServices()，否则 gatt 为 null 时会崩溃。
    if (gattMaybe === null || gattMaybe === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'readCharacteristic: device is disconnected');
      result.error('readCharacteristic', 'device is disconnected', null);
      return;
    }
    // 显式收窄为非空引用，供 runGatt 闭包内使用（闭包是独立作用域，外层判空不传导）。
    let gatt: ble.GattClientDevice = gattMaybe;
    // 按设备串行执行 GATT 操作，避免 OHOS BLE 栈 2900011 "operation is busy" 错误。
    // 解析特征（getServices → waitIfBonding → locateCharacteristic）；失败时已 result.error 并返回 null。
    await this.plugin.gattCache.runGatt(remoteId, async () => {
      let uuidArgs: UuidArgs = {
        remoteId: remoteId,
        serviceUuid: serviceUuid,
        secondaryServiceUuid: secondaryServiceUuid,
        characteristicUuid: characteristicUuid,
      };
      let resolved: CharacteristicTarget | null =
        await this.resolveCharacteristic('readCharacteristic', gatt, uuidArgs, result);
      if (resolved === null) {
        return;
      }
      let characteristic: ble.BLECharacteristic = resolved.characteristic;
      let services: ble.GattService[] = resolved.services;
      if (!characteristic.properties?.read) {
        BleUtils.log(hilog.LogLevel.ERROR,
          'readCharacteristic: The READ property is not supported by this BLE characteristic');
        result.error('readCharacteristic',
          'The READ property is not supported by this BLE characteristic', null);
        return;
      }

      // 读取特征值；失败按错误类型分流（参照 2.1.0 readCharacteristic 认证容错）。
      // 认证/加密类 2901006（未认证）/ 2901007（加密不足）：主动配对加密链路后重试一次
      // （ensureBondedForRetry：pairDevice → waitIfBonding 轮询 → 终判 BOND_STATE_BONDED → 重试）；
      // 其余错误（含 2900099 Operation failed）直接报错，不重试、不自动配对。
      // 根因：writeNoResp 走 WRITE_NO_RESPONSE 不需认证故 success，同一特征紧随的 read 因链路未加密
      // 被栈拒绝 → 即 “write success 后紧接着 read 报 2901007”；配对加密链路后即可正常读取。
      let readCharacteristic: ble.BLECharacteristic | null = null;
      try {
        readCharacteristic = await gatt.readCharacteristicValue(characteristic);
      } catch (e) {
        let readError: BusinessError = e as BusinessError;
        BleUtils.log(hilog.LogLevel.ERROR,
          `readCharacteristic failed: gatt.readCharacteristicValue() threw: ${JSON.stringify(e)}`);
        if (readError.code === 2901006 || readError.code === 2901007) {
          // 认证/加密不足：主动配对后重试一次。配对会弹系统配对框，配对完成链路加密后再读。
          BleUtils.log(hilog.LogLevel.WARN,
            `readCharacteristic: auth error ${readError.code}, attempting bond + retry`);
          let bonded: boolean = await this.plugin.bondManager.ensureBondedForRetry(remoteId);
          if (!bonded) {
            result.error('readCharacteristic',
              `gatt.readCharacteristic() failed with error: ${readError.message || 'unknown error'}` +
              ' (bonding failed or timed out)',
              null);
            return;
          }
          try {
            readCharacteristic = await gatt.readCharacteristicValue(characteristic);
            BleUtils.log(hilog.LogLevel.DEBUG, 'readCharacteristic: retry succeeded after bonding');
          } catch (e2) {
            let retryError: BusinessError = e2 as BusinessError;
            BleUtils.log(hilog.LogLevel.ERROR,
              `readCharacteristic retry after bond failed: ${JSON.stringify(e2)}`);
            result.error('readCharacteristic',
              `gatt.readCharacteristic() failed with error: ${retryError.message || 'unknown error'}`,
              null);
            return;
          }
        } else {
          result.error('readCharacteristic',
            `gatt.readCharacteristic() failed with error: ${readError.message || 'unknown error'}`,
            null);
          return;
        }
      }

      this.plugin.onCharacteristicReceived(remoteId, services, readCharacteristic);

      // BLECharacteristicChange 监听已由 BleNotifyManager 在 handleConnected 时统一注册,
      // readCharacteristic 仅回传读取结果,不再刷新监听,避免同一 gatt 上双重监听导致事件重复。
      result.success(true);
    });
  }

  /**
   * read/write 共用的特征解析子步骤（getServices → waitIfBonding → mapServiceArgs →
   * locateCharacteristic → found 空检查与 error 检查）。
   *
   * read 与 write 的 locate 流程完全一致（getServices 后 await waitIfBonding，参数经 mapServiceArgs 映射），
   * 故抽为单个方法、以 methodName 区分错误码/日志前缀。解析失败时通过 result.error 回传错误
   * （错误码/消息与 1.33.5 原内联逻辑完全一致）并返回 null，调用方见 null 即 return。
   * @param methodName 'readCharacteristic' 或 'writeCharacteristic'（错误码与 not-found 日志前缀）。
   * @returns 解析结果（characteristic/services）；失败返回 null。
   */
  private async resolveCharacteristic(methodName: string, gatt: ble.GattClientDevice,
    args: UuidArgs, result: MethodResult): Promise<CharacteristicTarget | null> {
    // 优先使用 deviceServicesMap 缓存，cache miss 时才调 getServices() 并写回缓存，
    // 减少与 BLE 栈的异步交互次数（OHOS 的 gatt.getServices() 是异步操作，每次调用
    // 可能增加与其它 GATT 操作的并发冲突概率，导致 read/write 间歇性返回 2900099）。
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
    await this.plugin.connectionManager.waitIfBonding();
    let serviceArgs: ServiceArgs = this.mapServiceArgs(args.serviceUuid, args.secondaryServiceUuid);
    let found: ChrFound | undefined = await BleGattShared.locateCharacteristic(serviceArgs.primaryServiceUuid,
      serviceArgs.serviceUuid, args.characteristicUuid, 0, services);
    if (found === undefined || found === null) {
      BleUtils.log(hilog.LogLevel.ERROR, methodName + ': characteristic not found');
      result.error(methodName, 'characteristic not found', null);
      return null;
    }
    if (found.error !== null) {
      let errMsg: string = found.error as string;
      BleUtils.log(hilog.LogLevel.ERROR, errMsg);
      result.error(methodName, errMsg, null);
      return null;
    }
    let characteristic: ble.BLECharacteristic = found.characteristic as ble.BLECharacteristic;
    return new CharacteristicTarget(characteristic, services);
  }

  /**
   * 处理 writeCharacteristic：按写入类型写特征值，校验属性与负载长度后写入并回传 OnCharacteristicWritten。
   *
   * @param call - 方法调用，args 含 remote_id/service_uuid/secondary_service_uuid/characteristic_uuid
   *               /value(十六进制字符串)/write_type/allow_long_write
   * @param result - 结果回调
   */
  async handleWriteCharacteristic(call: MethodCall, result: MethodResult): Promise<void> {
    let args: WriteCharacteristicArgs = this.parseWriteCharacteristicArgs(call);
    let remoteId: string = args.uuidArgs.remoteId;

    let gattMaybe: ble.GattClientDevice | undefined = this.plugin.connectionManager.connectedDevices.get(remoteId);
    if (gattMaybe === null || gattMaybe === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'writeCharacteristic: device is disconnected');
      result.error('writeCharacteristic', 'device is disconnected', null);
      return;
    }
    // 显式收窄为非空引用，供 runGatt 闭包内使用（闭包是独立作用域，外层判空不传导）。
    let gatt: ble.GattClientDevice = gattMaybe;
    // 按设备串行执行 GATT 操作，避免 OHOS BLE 栈 2900011 "operation is busy" 错误。
    // 解析特征（getServices → waitIfBonding → locateCharacteristic）；失败时已 result.error 并返回 null。
    await this.plugin.gattCache.runGatt(remoteId, async () => {
      let resolved: CharacteristicTarget | null =
        await this.resolveCharacteristic('writeCharacteristic', gatt, args.uuidArgs, result);
      if (resolved === null) {
        return;
      }
      // 属性 + 负载校验；不支持或超长时已 result.error 并返回 false。
      if (!this.validateWriteRequest(args, resolved.characteristic, result)) {
        return;
      }
      // 执行写入 + 回传响应（失败时已在内部 result.error）。
      await this.executeWriteAndRespond(gatt, resolved.characteristic, args, result);
    });
  }

  /**
   * 解析 writeCharacteristic 调用参数：从 call.args 收窄为强类型 WriteCharacteristicArgs。
   * 含 UUID 组、value、writeType 映射、allowLongWrite。
   */
  private parseWriteCharacteristicArgs(call: MethodCall): WriteCharacteristicArgs {
    let data: Map<string, string | number> = call.args as Map<string, string | number>;
    let writeTypeInt: number = data.get('write_type') as number;
    // WRITE 1 表示写入特征值，需要对端设备的回复。
    // WRITE_NO_RESPONSE 2 表示写入特征值，不需要对端设备的回复。
    let writeType: number = writeTypeInt === 0 ? ble.GattWriteType.WRITE : ble.GattWriteType.WRITE_NO_RESPONSE;
    return {
      uuidArgs: {
        remoteId: data.get('remote_id') as string,
        serviceUuid: data.get('service_uuid') as string,
        secondaryServiceUuid: data.get('secondary_service_uuid') as string,
        characteristicUuid: data.get('characteristic_uuid') as string,
      },
      value: data.get('value') as string,
      writeType: writeType,
      writeTypeInt: writeTypeInt,
      allowLongWrite: data.get('allow_long_write') as number !== 0,
    };
  }

  /**
   * writeCharacteristic 的属性校验 + 负载长度校验。
   * 不支持属性或负载超长时已 result.error 并返回 false；通过返回 true。
   */
  private validateWriteRequest(args: WriteCharacteristicArgs, characteristic: ble.BLECharacteristic | null,
    result: MethodResult): boolean {
    if (!this.validateWriteProperties(args.writeType, characteristic, result)) {
      return false;
    }
    let valueBytes: Uint8Array | null = HexUtil.hexStringToBytes(args.value);
    let tooLongStr: string | null = this.checkPayloadTooLong(args.uuidArgs.remoteId, args.writeType,
      args.writeTypeInt, args.allowLongWrite, valueBytes);
    if (tooLongStr !== null) {
      BleUtils.log(hilog.LogLevel.ERROR, tooLongStr);
      result.error('writeCharacteristic', tooLongStr, null);
      return false;
    }
    return true;
  }

  /**
   * writeCharacteristic 的缓存写入 + 执行写入 + 响应回传。
   * valueBytes 经 validateWriteRequest 校验过，此处重新解析（校验与执行分离，避免返回多值）。
   */
  private async executeWriteAndRespond(gatt: ble.GattClientDevice, characteristic: ble.BLECharacteristic,
    args: WriteCharacteristicArgs, result: MethodResult): Promise<void> {
    let valueBytes: Uint8Array = HexUtil.hexStringToBytes(args.value) as Uint8Array;
    let key: string = args.uuidArgs.remoteId + ':' + args.uuidArgs.serviceUuid + ':' + args.uuidArgs.characteristicUuid;
    // 缓存写入值（writeChrMap 为 Map<string, Uint8Array>），用于回传时按相同键取回。
    this.plugin.gattCache.writeChrMap.set(key, valueBytes);
    characteristic.characteristicValue = BleUtils.typedArrayToBuffer(valueBytes);
    // 执行写入：失败时已在内部清理缓存并 result.error，返回 false；成功返回 true。
    if (!await this.attemptWriteCharacteristic(gatt, characteristic, args.writeType, key, result)) {
      return;
    }
    // 写入成功：清理缓存键（1.33.5 原逻辑回传使用输入 value，缓存值仅作 round-trip 清理）。
    this.plugin.gattCache.writeChrMap.delete(key);
    // 组装 OnCharacteristicWritten 并回传（1.33.5 契约，value 回传输入的十六进制字符串）。
    this.buildCharacteristicWrittenResponse(args.uuidArgs, args.value, false);
    result.success(true);
  }

  /**
   * 执行特征值写入并处理失败路径。
   *
   * 失败（writeCharacteristicValue 抛异常）时清理 writeChrMap 缓存、记录日志并通过 result.error 回传错误
   * （消息与 1.33.5 原内联逻辑完全一致），返回 false；成功返回 true（缓存清理与响应由调用方处理）。
   * @returns true 表示写入成功；false 表示失败（已 result.error，调用方直接 return）。
   */
  private async attemptWriteCharacteristic(gatt: ble.GattClientDevice,
    characteristic: ble.BLECharacteristic | null, writeType: number, key: string,
    result: MethodResult): Promise<boolean> {
    try {
      await gatt.writeCharacteristicValue(characteristic, writeType);
    } catch (e) {
      let businessError: BusinessError = e as BusinessError;
      // 写入失败：清理刚缓存的写入值，避免 writeChrMap 残留。
      this.plugin.gattCache.writeChrMap.delete(key);
      BleUtils.log(hilog.LogLevel.ERROR,
        `writeCharacteristic failed: errorCode=${businessError.code}, errmessage=${businessError.message}`);
      // 直接报错，不重试，对齐 Android/iOS 行为（文案与 2.1.0 dev 分支一致）。
      // 2900099 等错误由 runGatt 串行锁从源头减少并发冲突概率；
      // 对标准 GATT 服务(0x1800/0x1801 等)特征写入被 OHOS BLE 栈拒绝属平台限制(见 CHANGELOG)。
      result.error('writeCharacteristic',
        `gatt.writeCharacteristic() failed with error: ${businessError.message || 'unknown error'}`,
        null);
      return false;
    }
    return true;
  }

  /**
   * 清空回调引用占位。
   *
   * BLECharacteristicChange 监听已统一由 BleNotifyManager 管理(registerCharacteristicChangeCallback,
   * 在 handleConnected 注册),本类不再持有回调 Map。保留空 clearAll() 仅维持 cleanup 调用兼容,
   * 实际清理由 notifyManager.clearAll() 完成。
   */
  clearAll(): void {
    // no-op: 监听已迁至 BleNotifyManager,本类无回调 Map 需清理。
  }

  /**
   * 校验写入属性是否被特征支持（WRITE / WRITE_NO_RESPONSE）。
   * 不支持时通过 result.error 回传错误（消息与 1.33.5 原内联逻辑完全一致）并返回 false，调用方见 false 即 return。
   * @returns true 表示属性支持可继续；false 表示已回传错误。
   */
  private validateWriteProperties(writeType: number, characteristic: ble.BLECharacteristic | null,
    result: MethodResult): boolean {
    if (writeType === ble.GattWriteType.WRITE) {
      if (!characteristic?.properties?.write) {
        BleUtils.log(hilog.LogLevel.ERROR,
          'writeCharacteristic: The WRITE property is not supported by this BLE characteristic');
        result.error('writeCharacteristic',
          'The WRITE property is not supported by this BLE characteristic', null);
        return false;
      }
    } else {
      if (!characteristic?.properties?.writeNoResponse) {
        BleUtils.log(hilog.LogLevel.ERROR,
          'writeCharacteristic: The WRITE_NO_RESPONSE property is not supported by this BLE characteristic');
        result.error('writeCharacteristic',
          'The WRITE_NO_RESPONSE property is not supported by this BLE characteristic', null);
        return false;
      }
    }
    return true;
  }

  /**
   * 校验写入负载长度是否超过最大允许值（MTU-3 或 512）。
   * @returns 超长时返回错误描述字符串（调用方据此 log + result.error + return）；未超长返回 null。
   */
  private checkPayloadTooLong(remoteId: string, writeType: number, writeTypeInt: number,
    allowLongWrite: boolean, valueBytes: Uint8Array | null): string | null {
    let maxLen: number = this.getMaxPayload(remoteId, writeType, allowLongWrite);
    let dataLen: number = valueBytes?.byteLength as number;
    if (dataLen > maxLen) {
      let a: string = writeTypeInt === 0 ? 'withResponse' : 'withoutResponse';
      let b: string = writeTypeInt === 0 ? (allowLongWrite ? ', allowLongWrite' : ', noLongWrite') : '';
      let str: string =
        'data longer than allowed. dataLen: ' + dataLen + ' > max: ' + maxLen + ' (' + a + b + ')';
      return str;
    }
    return null;
  }

  /**
   * 组装 OnCharacteristicWritten 响应 Map 并通过 channel 回传（1.33.5 契约）。
   * value 直接回传输入的十六进制字符串；success/error_code/error_string 在成功路径上固定为 1/0/''。
   * 字段顺序与类型须与 Dart 侧契约完全一致。
   */
  private buildCharacteristicWrittenResponse(args: UuidArgs, value: string, writeFlag: boolean): void {
    let response: Map<string, string | number> = new Map<string, string | number>();
    response.set('remote_id', args.remoteId);
    response.set('service_uuid', args.serviceUuid);
    if (args.secondaryServiceUuid !== null) {
      response.set('secondary_service_uuid', args.secondaryServiceUuid);
    }
    response.set('characteristic_uuid', args.characteristicUuid);
    response.set('value', value);
    response.set('success', writeFlag ? 0 : 1);
    response.set('error_code', 0);
    response.set('error_string', '');
    this.plugin.channel?.invokeMethod('OnCharacteristicWritten', response);
  }

  /**
   * 计算指定设备与写入方式下的最大可写入字节数（KEEP 1.33.5 逻辑）。
   *
   * 无响应写入或禁止长写入时上限为 MTU-3（扣除 3 字节 ATT 操作头），
   * 带响应且允许长写入时上限为 GATT 最大属性长度 512 字节。
   * MTU 缺失时回退 23（BLE 规范最小 MTU），该回退逻辑由 BleGattShared.getMaxPayload
   * 以 `mtu === null || mtu === undefined` 形式实现（本会话加固）。
   *
   * @param remoteId - 设备远程标识
   * @param writeType - 写入类型（WITH_RESPONSE / WITHOUT_RESPONSE）
   * @param allowLongWrite - 是否允许长写入
   * @returns 最大载荷字节数
   */
  private getMaxPayload(remoteId: string, writeType: number, allowLongWrite: boolean): number {
    return BleGattShared.getMaxPayload(this.plugin.gattCache.mtuMap, remoteId, writeType, allowLongWrite);
  }

  /**
   * 将 1.33.5 参数语义映射到 BleGattShared.locateCharacteristic 的参数语义。
   *
   * 1.33.5：service_uuid 为主服务、secondary_service_uuid 为特征实际所在的次服务（可空）。
   * BleGattShared：primaryServiceUuid 非空时按「主服务 → includeServices 中的次服务」查找，
   * 为 null/undefined 时直接以 serviceUuid 作为主服务查找。
   *
   * 故次服务存在时：primaryServiceUuid=serviceUuid(主)、serviceUuid=secondaryServiceUuid(次)；
   * 次服务不存在时：primaryServiceUuid=secondaryServiceUuid(此时为 null/undefined)、serviceUuid=serviceUuid(主)。
   *
   * @param serviceUuid - 1.33.5 service_uuid（主服务）
   * @param secondaryServiceUuid - 1.33.5 secondary_service_uuid（次服务，可空）
   * @returns 映射后的 primaryServiceUuid / serviceUuid
   */
  private mapServiceArgs(serviceUuid: string, secondaryServiceUuid: string): ServiceArgs {
    let isSecondary: boolean =
      secondaryServiceUuid !== null && secondaryServiceUuid !== undefined && secondaryServiceUuid.length > 0;
    let args: ServiceArgs = new ServiceArgs();
    if (isSecondary) {
      args.primaryServiceUuid = serviceUuid;
      args.serviceUuid = secondaryServiceUuid;
    } else {
      // secondaryServiceUuid 在非次服务场景为 null/undefined，直接作为 primaryServiceUuid 传入，
      // BleGattShared.locateCharacteristic 检测到 == null 时回退以 serviceUuid 作主服务查找。
      args.primaryServiceUuid = secondaryServiceUuid;
      args.serviceUuid = serviceUuid;
    }
    return args;
  }
}

/**
 * locateCharacteristic 参数映射中间结构。
 * primaryServiceUuid 为 null/undefined 时表示特征位于主服务（非次服务场景）。
 */
class ServiceArgs {
  /** 主服务 UUID（次服务场景）；null/undefined 表示特征在主服务。 */
  public primaryServiceUuid: string = '';
  /** 特征实际所在服务 UUID（次服务场景为 secondaryServiceUuid，否则为 serviceUuid）。 */
  public serviceUuid: string = '';
}

/**
 * read/write 特征解析子步骤（resolveCharacteristic）的返回值。
 * 将定位到的 characteristic 与 getServices 返回的服务树打包，使解析方法签名收敛为单个返回值。
 */
class CharacteristicTarget {
  /** 定位到的特征。 */
  public characteristic: ble.BLECharacteristic;
  /** getServices 返回的服务树（回传/监听注册时定位 primary service）。 */
  public services: ble.GattService[];

  constructor(characteristic: ble.BLECharacteristic, services: ble.GattService[]) {
    this.characteristic = characteristic;
    this.services = services;
  }
}
