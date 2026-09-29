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

import { ble } from '@kit.ConnectivityKit';
import { List } from '@kit.ArkTS';
import { MethodResult } from '@ohos/flutter_ohos';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BleUtils from './BleUtils';

/** locateCharacteristic 查找结果。 */
export class ChrFound {
  public characteristic: ble.BLECharacteristic | null = null;
  public error: string | null = null;

  constructor(characteristic: ble.BLECharacteristic | null, error: string | null) {
    this.characteristic = characteristic;
    this.error = error;
  }
}

/**
 * GATT 写操作的设备/特征身份标识（remoteId + 4 个 UUID/instanceId 定位字段）。
 *
 * 抽成独立值对象，使 {@link GattWriteContext} 构造参数收敛到 ≤5 个；
 * 同时作为 executeWriteCharacteristic / writeNotifyDescriptor / executeWriteDescriptor
 * 构建「写入缓存键」的统一数据源。
 */
export class GattWriteTarget {
  /** 设备 ID（remoteId）。 */
  public remoteId: string;
  /** 主服务 UUID（次服务时为 null/空）。 */
  public primaryServiceUuid: string;
  /** 特征所属服务 UUID。 */
  public serviceUuid: string;
  /** 特征 UUID。 */
  public characteristicUuid: string;
  /** 特征 instanceId。 */
  public instanceId: number;

  constructor(remoteId: string, primaryServiceUuid: string, serviceUuid: string,
    characteristicUuid: string, instanceId: number) {
    this.remoteId = remoteId;
    this.primaryServiceUuid = primaryServiceUuid;
    this.serviceUuid = serviceUuid;
    this.characteristicUuid = characteristicUuid;
    this.instanceId = instanceId;
  }
}

/**
 * GATT 写操作上下文。
 *
 * 封装 executeWriteCharacteristic / writeNotifyDescriptor / executeWriteDescriptor 三个写方法
 * 共享的「定位 + 回传」所需信息（gatt 实例、目标特征、服务树、result 回调，外加 target
 * 身份），将原 11~12 个参数收敛为单个 ctx，且构造参数 ≤5（身份字段经 target 摊平为 ctx.*
 * 直属字段，保持调用方访问不变）。
 */
export class GattWriteContext {
  /** 目标设备的 GattClientDevice。 */
  public gatt: ble.GattClientDevice;
  /** 目标特征。 */
  public characteristic: ble.BLECharacteristic;
  /** 已发现的服务树（用于回传时定位 primary service）。 */
  public gattServices: ble.GattService[];
  /** 设备 ID（remoteId）。 */
  public remoteId: string;
  /** 主服务 UUID（次服务时为 null/空）。 */
  public primaryServiceUuid: string;
  /** 特征所属服务 UUID。 */
  public serviceUuid: string;
  /** 特征 UUID。 */
  public characteristicUuid: string;
  /** 特征 instanceId。 */
  public instanceId: number;
  /** 结果回调。 */
  public result: MethodResult;

  constructor(gatt: ble.GattClientDevice, characteristic: ble.BLECharacteristic,
    gattServices: ble.GattService[], target: GattWriteTarget, result: MethodResult) {
    this.gatt = gatt;
    this.characteristic = characteristic;
    this.gattServices = gattServices;
    this.remoteId = target.remoteId;
    this.primaryServiceUuid = target.primaryServiceUuid;
    this.serviceUuid = target.serviceUuid;
    this.characteristicUuid = target.characteristicUuid;
    this.instanceId = target.instanceId;
    this.result = result;
  }
}

/**
 * 特征定位用的 UUID 组参数对象。
 *
 * 将 resolveCharacteristic / buildCharacteristicWrittenResponse 等方法的
 * remoteId/serviceUuid/secondaryServiceUuid/characteristicUuid 多参数收敛为单个对象,
 * 使方法参数数 ≤5(符合复杂度规范)。
 */
export interface UuidArgs {
  /** 设备 ID（remoteId）。 */
  remoteId: string;
  /** 主服务 UUID（次服务场景为 includer）。 */
  serviceUuid: string;
  /** 次服务 UUID（特征实际所属；无次服务时为 null/空）。 */
  secondaryServiceUuid: string;
  /** 特征 UUID。 */
  characteristicUuid: string;
}

/**
 * 描述符定位用的 UUID 组参数对象(在 UuidArgs 基础上加 descriptorUuid)。
 *
 * 用于 resolveDescriptor* / buildDescriptor*Response 等描述符相关方法。
 */
export interface DescriptorUuidArgs extends UuidArgs {
  /** 描述符 UUID。 */
  descriptorUuid: string;
}

/**
 * 描述符写入结果参数对象。
 *
 * 将 buildDescriptorWrittenResponse 的 value/writeDescriptorFlag/errorCode/errorMessage
 * 四个结果参数收敛为单个对象,使方法参数数 ≤5。
 */
export interface DescriptorWriteResult {
  /** 写入值(十六进制字符串)。 */
  value: string;
  /** 是否为描述符写入(非通知 CCCD 写入场景的标记)。 */
  writeDescriptorFlag: boolean;
  /** 错误码(成功为 0)。 */
  errorCode: number;
  /** 错误消息(成功为空串)。 */
  errorMessage: string;
}

/**
 * 通知订阅请求参数对象。
 *
 * 将 applyNotifyAndWriteCccd 的 forceIndications/enable 两个布尔参数收敛,
 * 使方法参数数 ≤5。
 */
export interface NotifyRequest {
  /** 是否强制使用 indication(而非 notification)。 */
  forceIndications: boolean;
  /** 用户请求的启用/禁用通知。 */
  enable: boolean;
}

/**
 * writeCharacteristic 调用参数解析结果。
 *
 * handleWriteCharacteristic 从 call.args 解析出的参数收敛为单个对象,
 * 供 parseWriteCharacteristicArgs 返回,降低主方法行数。
 */
export interface WriteCharacteristicArgs {
  /** UUID 组(含 remoteId/serviceUuid/secondaryServiceUuid/characteristicUuid)。 */
  uuidArgs: UuidArgs;
  /** 写入值(十六进制字符串)。 */
  value: string;
  /** 鸿蒙写入类型(WRITE / WRITE_NO_RESPONSE)。 */
  writeType: number;
  /** Dart 传入的原始写入类型索引(0=withResponse,2=withoutResponse)。 */
  writeTypeInt: number;
  /** 是否允许长写入。 */
  allowLongWrite: boolean;
}

/**
 * 通知/CCCD 写入上下文。
 *
 * 收敛 applyNotifyAndWriteCccd / writeNotifyDescriptor 共享的 gatt/characteristic/
 * gattServices/remoteId 四个参数,使两方法参数数 ≤5。
 */
export interface NotifyWriteContext {
  /** 目标设备 GattClientDevice。 */
  gatt: ble.GattClientDevice;
  /** 目标特征。 */
  characteristic: ble.BLECharacteristic;
  /** 已发现服务树(回传时定位 primary service)。 */
  gattServices: ble.GattService[];
  /** 设备 ID。 */
  remoteId: string;
}

/**
 * GATT 服务树查找工具集（横切关注点，无实例状态）。
 *
 * 从 BleGattManager 剥离的纯静态工具方法：getInstanceId（实例 ID 计算）、getPrimaryService
 * （主服务回溯）、locateCharacteristic（定位特征）及其子 helper getServiceFromArray /
 * getCharacteristicFromArray、getDescriptorFromArray / getReadDescriptorFromArray。
 *
 * 这些方法被 GATT 的 Characteristic/Descriptor/Notify/服务发现等多个功能组共用，
 * 且只依赖入参与 BleUtils / deviceInfo（无 plugin/缓存字段依赖），故抽为独立工具类，
 * 各 Manager 直接以 BleGattShared.xxx(...) 调用，避免子 Manager 间互相持有引用。
 */
export default class BleGattShared {
  /**
   * buildBluetoothService 遍历 included_services 的最大递归深度，防止异常服务树
   * （如环形 include）栈溢出。BLE 规范的 included services 实际仅 1~2 层，10 层为安全上限。
   */
  private static readonly MAX_INCLUDED_SERVICE_DEPTH: number = 10;

  /**
   * 计算特征在所属服务中的实例 ID（用于区分同 UUID 多特征）。
   * API>=18 用 characteristicValueHandle 精确匹配；否则用 properties+descriptors.length 近似匹配。
   * 同 UUID 特征数>1 时返回索引+1，否则返回 0。
   * @param target - 目标特征
   * @param services - GATT 服务数组
   * @returns 实例 ID
   */
  static getInstanceId(target: ble.BLECharacteristic, services: ble.GattService[]): number {
    let targetService: ble.GattService | undefined;
    let indexForTarget: number = 0;
    const apiVersion: number = deviceInfo.sdkApiVersion;
    for (let service of services) {
      if (service.characteristics) {
        for (let i = 0; i < service.characteristics.length; i++) {
          let char: ble.BLECharacteristic = service.characteristics[i];
          let isMatch: boolean = false;

          if (char.characteristicUuid === target.characteristicUuid) {
            if (apiVersion >= 18) {
              isMatch = char.characteristicValueHandle === target.characteristicValueHandle;
            } else {
              isMatch = (
                char.properties?.toString() === target.properties?.toString() &&
                  char.descriptors?.length === target.descriptors?.length
              );
            }
          }

          if (isMatch) {
            targetService = service;
            indexForTarget = i;
            break;
          }
        }
        if (targetService) {
          break;
        }
      }
    }

    if (!targetService || !targetService.characteristics) {
      return 0;
    }
    const needle: string = target.characteristicUuid;
    const list: ble.BLECharacteristic[] = targetService.characteristics;
    let sameUuidCount: number = 0;

    for (let c of list) {
      if (c.characteristicUuid === needle) {
        sameUuidCount++;
      }
    }
    return (sameUuidCount > 1) ? indexForTarget + 1 : 0;
  }

  /**
   * 在服务数组中查找特征所属的主服务（针对次级服务回溯 includeServices）。
   * @param services - GATT 服务数组
   * @param characteristic - 目标特征
   * @returns 主服务；特征本身属于主服务或未找到时返回 null
   */
  static getPrimaryService(services: ble.GattService[],
    characteristic: ble.BLECharacteristic): ble.GattService | null {
    let service: ble.GattService | null = null;
    for (let i = 0; i < services.length; i++) {
      if (services[i].serviceUuid === characteristic.serviceUuid) {
        service = services[i];
      }
    }
    if (!service) {
      return null;
    }
    if (service?.isPrimary) {
      return null;
    }
    for (let i = 0; i < services.length; i++) {
      let primaryService: ble.GattService = services[i];
      if (primaryService.includeServices) {
        for (let j = 0; j < primaryService.includeServices.length; j++) {
          let secondaryService: ble.GattService = primaryService.includeServices[j];
          if (secondaryService.serviceUuid === service?.serviceUuid) {
            return primaryService;
          }
        }
      }
    }
    return null;
  }

  /**
   * 在服务数组中按 UUID 查找服务（UUID 规范化为 128-bit 比较）。
   * @param uuid - 目标服务 UUID
   * @param array - 服务数组
   * @returns 匹配的服务；未找到返回 null
   */
  static getServiceFromArray(uuid: string, array: ble.GattService[]): ble.GattService | null {
    for (let i = 0; i < array.length; i++) {
      if (BleUtils.uuid128(uuid) === BleUtils.uuid128(array[i].serviceUuid)) {
        return array[i];
      }
    }
    return null;
  }

  /**
   * 在特征数组中按 UUID+实例 ID 查找特征。
   * 同 UUID 多特征时按 instanceId 精确匹配，否则返回首个。
   * @param uuid - 目标特征 UUID
   * @param array - 特征数组
   * @param services - GATT 服务数组（用于计算实例 ID）
   * @param instanceId - 实例 ID
   * @returns 匹配的特征；未找到返回 null
   */
  static getCharacteristicFromArray(uuid: string, array: ble.BLECharacteristic[],
    services: ble.GattService[], instanceId: number): ble.BLECharacteristic | null {
    let targetUuid: string = BleUtils.uuid128(uuid);
    let matchingChars: ble.BLECharacteristic[] = [];
    for (let characteristic of array) {
      if (BleUtils.uuid128(characteristic.characteristicUuid) === targetUuid) {
        matchingChars.push(characteristic);
      }
    }
    if (matchingChars.length === 0) {
      return null;
    }
    if (matchingChars.length === 1) {
      return matchingChars[0];
    }
    if (instanceId === 0) {
      return matchingChars[0];
    }
    for (let characteristic of matchingChars) {
      let charInstanceId: number = BleGattShared.getInstanceId(characteristic, services);
      if (charInstanceId === instanceId) {
        return characteristic;
      }
    }
    let index: number = instanceId - 1;
    if (index >= 0 && index < matchingChars.length) {
      return matchingChars[index];
    }
    return matchingChars[0];
  }

  /**
   * 定位特征：按主服务/次服务/特征 UUID/实例 ID 在服务树中查找。
   * @param primaryServiceUuid - 主服务 UUID（可空）
   * @param serviceUuid - 服务 UUID
   * @param characteristicUuid - 特征 UUID
   * @param instanceId - 实例 ID
   * @param gattServices - GATT 服务数组
   * @returns ChrFound（含特征或错误信息）
   */
  static async locateCharacteristic(primaryServiceUuid: string, serviceUuid: string,
    characteristicUuid: string, instanceId: number,
    gattServices: ble.GattService[]): Promise<ChrFound | undefined> {
    let isSecondaryService: boolean = primaryServiceUuid !== null;
    if (primaryServiceUuid === null) {
      primaryServiceUuid = serviceUuid;
    }
    let primaryService: ble.GattService | null =
      BleGattShared.getServiceFromArray(primaryServiceUuid, gattServices);
    if (primaryService === null) {
      let result: ChrFound = new ChrFound(null, 'primary service not found \'' + primaryServiceUuid + '\'');
      return result;
    }
    let secondaryService: ble.GattService | null = null;
    if (isSecondaryService) {
      if (primaryService.includeServices) {
        secondaryService = BleGattShared.getServiceFromArray(serviceUuid, primaryService.includeServices);
      }
      if (secondaryService === null) {
        return new ChrFound(null,
          'secondary service not found \'' + serviceUuid + '\' (primary service \'' + primaryServiceUuid + '\')');
      }
    }
    let service: ble.GattService = (secondaryService !== null) ? secondaryService : primaryService;
    let characteristic: ble.BLECharacteristic | null =
      BleGattShared.getCharacteristicFromArray(characteristicUuid, service.characteristics, gattServices, instanceId);
    if (characteristic === null) {
      return new ChrFound(null, 'characteristic not found in service ' +
        '(chr: \'' + characteristicUuid + '\' svc: \'' + serviceUuid + '\')');
    }
    return new ChrFound(characteristic, null);
  }

  /**
   * 查找描述符数组中匹配 UUID 的描述符（UUID 先规范化为 128-bit 比较）。
   * @param uuid - 目标描述符 UUID
   * @param array - 描述符数组
   * @returns 匹配的描述符；未找到返回 null
   */
  static getDescriptorFromArray(uuid: string, array: ble.BLEDescriptor[]): ble.BLEDescriptor | null {
    for (let i = 0; i < array.length; i++) {
      if (BleUtils.uuid128(array[i].descriptorUuid) === BleUtils.uuid128(uuid)) {
        return array[i];
      }
    }
    return null;
  }

  /**
   * 查找描述符数组中匹配 UUID 的描述符（读取场景使用，行为同 getDescriptorFromArray）。
   * @param uuid - 目标描述符 UUID
   * @param array - 描述符数组
   * @returns 匹配的描述符；未找到返回 null
   */
  static getReadDescriptorFromArray(uuid: string, array: ble.BLEDescriptor[]): ble.BLEDescriptor | null {
    for (let i = 0; i < array.length; i++) {
      if (BleUtils.uuid128(array[i].descriptorUuid) === BleUtils.uuid128(uuid)) {
        return array[i];
      }
    }
    return null;
  }

  /**
   * 计算指定写入类型下的最大负载长度（MTU-3 或 512）。
   * @param mtuMap - MTU 缓存（设备 -> MTU）
   * @param remoteId - 设备 ID
   * @param writeType - 写入类型
   * @param allowLongWrite - 是否允许长写入
   * @returns 最大负载字节数
   */
  static getMaxPayload(mtuMap: Map<string, number>, remoteId: string,
    writeType: number, allowLongWrite: boolean): number {
    let maxAttrLen: number = 512;
    // if no response, we can only write up to MTU-3.
    if (writeType === ble.GattWriteType.WRITE_NO_RESPONSE || allowLongWrite === false) {
      let mtu: number | undefined = mtuMap.get(remoteId);
      if (mtu === null || mtu === undefined) {
        mtu = 23;
      }
      return Math.min(mtu - 3, maxAttrLen);
    } else {
      return maxAttrLen;
    }
  }

  /**
   * 构造 BmBluetoothService Map（remote_id/primary_service_uuid/service_uuid/characteristics）。
   * @param service - GATT 服务
   * @param primaryService - 关联主服务（次级服务时传入）
   * @param remoteId - 设备 ID
   * @param gattServices - GATT 服务数组（用于实例 ID 计算）
   * @returns BmBluetoothService Map
   */
  static buildBluetoothService(service: ble.GattService, primaryService: ble.GattService | null, remoteId: string,
    gattServices: ble.GattService[], depth: number = 0): Map<string, object | string | number> {
    let characteristics: List<object> = new List<object>();
    service.characteristics.forEach((characteristic) => {
      characteristics.add(BleGattShared.buildBluetoothCharacteristic(remoteId, characteristic, gattServices));
    });
    // Dart 侧 BmBluetoothService.fromMap 要求 included_services 字段（for-in 遍历），
    // 缺失会导致 null 遍历异常 → OnDiscoveredServices 解析失败 → discoverServices 超时。
    // 递归深度限制（MAX_INCLUDED_SERVICE_DEPTH）：防止异常/恶意服务树（如 A↔B 互相 include）
    // 造成无限递归栈溢出；配合下方 serviceUuid 自引用跳过，覆盖所有现实场景。
    let includedServices: List<object> = new List<object>();
    try {
      if (service.includeServices && depth < BleGattShared.MAX_INCLUDED_SERVICE_DEPTH) {
        for (let i = 0; i < service.includeServices.length; i++) {
          if (service.serviceUuid === service.includeServices[i].serviceUuid) {
            continue; // skip, infinite recursion (self-reference)
          }
          includedServices.add(BleGattShared.buildBluetoothService(service.includeServices[i], service, remoteId,
            gattServices, depth + 1));
        }
      } else if (service.includeServices) {
        BleUtils.log(hilog.LogLevel.WARN,
          'buildBluetoothService: included_services depth limit reached, truncating');
      }
    } catch (e) {
      // includeServices 访问可能抛异常（部分设备/服务不支持），吞掉以保证
      // 主服务树正常回传。
    }
    let map: Map<string, object | string | number> = new Map();
    map.set('remote_id', remoteId);
    if (primaryService !== null) {
      map.set('primary_service_uuid', BleUtils.uuidStr(primaryService.serviceUuid));
    }
    map.set('service_uuid', BleUtils.uuidStr(service.serviceUuid));
    map.set('is_primary', service.isPrimary ? 1 : 0);
    map.set('characteristics', characteristics);
    map.set('included_services', includedServices);
    return map;
  }

  /**
   * 构造 BmBluetoothCharacteristic Map。
   * @param remoteId - 设备 ID
   * @param characteristic - BLE 特征
   * @param gattServices - GATT 服务数组（用于实例 ID 计算）
   * @returns BmBluetoothCharacteristic Map
   */
  static buildBluetoothCharacteristic(remoteId: string, characteristic: ble.BLECharacteristic,
    gattServices: ble.GattService[]): Map<string, object | string | number> {
    let descriptors: List<object> = new List<object>();
    characteristic.descriptors?.forEach((d) => {
      descriptors.add(BleGattShared.buildBluetoothDescriptor(remoteId, characteristic, d, gattServices));
    });
    let primaryService: ble.GattService | null = null;
    if (gattServices) {
      primaryService = BleGattShared.getPrimaryService(gattServices, characteristic);
    }
    let map: Map<string, object | string | number> = new Map<string, object | string | number>();
    map.set('remote_id', remoteId);
    if (primaryService !== null) {
      // 特征位于次（included）服务：对齐 Android pair.primary 语义——
      // service_uuid 填主服务（includer），secondary_service_uuid 填特征所属次服务。
      // 若 service_uuid 误填次服务自身（characteristic.serviceUuid），Dart 侧会得到
      // serviceUuid==secondaryServiceUuid==次服务UUID，read 时 mapServiceArgs 误判为
      // "主=次" 导致 "secondary service not found '<次>' (primary service '<次>')" 报错。
      map.set('primary_service_uuid', BleUtils.uuidStr(primaryService.serviceUuid));
      map.set('secondary_service_uuid', BleUtils.uuidStr(characteristic.serviceUuid));
      map.set('service_uuid', BleUtils.uuidStr(primaryService.serviceUuid));
    } else {
      map.set('service_uuid', BleUtils.uuidStr(characteristic.serviceUuid));
    }
    map.set('characteristic_uuid', BleUtils.uuidStr(characteristic.characteristicUuid));
    let instanceId: number = 0;
    if (gattServices) {
      instanceId = BleGattShared.getInstanceId(characteristic, gattServices);
    }
    map.set('instance_id', instanceId);
    map.set('descriptors', descriptors);
    map.set('properties', BleGattShared.buildCharacteristicProperties(characteristic));
    return map;
  }

  /**
   * 构造特征属性 Map（read/write/notify/indicate 等布尔转 0/1）。
   * OHOS 不支持的字段（broadcast/authenticated_signed_writes 等）固定 0。
   * @param characteristic - BLE 特征
   * @returns 属性 Map
   */
  static buildCharacteristicProperties(characteristic: ble.BLECharacteristic): Map<string, number> {
    let props: Map<string, number> = new Map<string, number>();
    if (characteristic.properties) {
      characteristic.properties.write ? props.set('write', 1) : props.set('write', 0);
      characteristic.properties.writeNoResponse ? props.set('write_without_response', 1) :
        props.set('write_without_response', 0);
      characteristic.properties.read ? props.set('read', 1) : props.set('read', 0);
      characteristic.properties.notify ? props.set('notify', 1) : props.set('notify', 0);
      characteristic.properties.indicate ? props.set('indicate', 1) : props.set('indicate', 0);
      props.set('broadcast', 0);
      props.set('authenticated_signed_writes', 0);
      props.set('extended_properties', 0);
      props.set('notify_encryption_required', 0);
      props.set('indicate_encryption_required', 0);
    }
    return props;
  }

  /**
   * 构造 BmBluetoothDescriptor Map。
   * @param remoteId - 设备 ID
   * @param characteristic - 所属特征
   * @param descriptor - BLE 描述符
   * @param gattServices - GATT 服务数组（用于实例 ID 计算）
   * @returns BmBluetoothDescriptor Map
   */
  static buildBluetoothDescriptor(remoteId: string, characteristic: ble.BLECharacteristic,
    descriptor: ble.BLEDescriptor,
    gattServices: ble.GattService[]): Map<string, object | string | number> {
    let primaryService: ble.GattService | null = BleGattShared.getPrimaryService(gattServices, characteristic);
    let map: Map<string, object | string | number> = new Map<string, object | string | number>();
    map.set('remote_id', remoteId);
    if (primaryService !== null) {
      // 次服务场景对齐 Android：service_uuid 填主服务，避免 serviceUuid==secondaryServiceUuid。
      map.set('primary_service_uuid', BleUtils.uuidStr(primaryService.serviceUuid));
      map.set('service_uuid', BleUtils.uuidStr(primaryService.serviceUuid));
    } else {
      map.set('service_uuid', BleUtils.uuidStr(descriptor.serviceUuid));
    }
    map.set('descriptor_uuid', BleUtils.uuidStr(descriptor.descriptorUuid));
    map.set('characteristic_uuid', BleUtils.uuidStr(descriptor.characteristicUuid));
    let instanceId: number = BleGattShared.getInstanceId(characteristic!, gattServices);
    map.set('instance_id', instanceId);
    return map;
  }
}
