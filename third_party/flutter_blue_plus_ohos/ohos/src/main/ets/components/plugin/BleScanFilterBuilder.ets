/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 ("the License");
 *
 * you may not use this file except in compliance with the License.
 * you may obtain a copy of the License at
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
import { HashMap, List } from '@kit.ArkTS';
import BleUtils from './BleUtils';

/**
 * startScan 参数 Map 的异构值类型(BmStartScanArgs.toMap)。
 * 使用联合类型而非 object,使 as number/as string/as boolean/as List<string> 等收窄转换合法
 * (ArkTS 严格模式下 object 与原始类型不重叠,直接 as 会报错)。
 */
export type ScanArgsValue = string | number | boolean | List<string> | List<object>;

/**
 * BLE 扫描过滤器构建器。
 *
 * 根据 Dart 端 BmStartScanArgs 的各维度(with_services/with_remote_ids/with_names/
 * with_msd/with_service_data)构造 ble.ScanFilter 数组。各维度由独立 append* 方法构造,
 * 便于阅读与维护;缺省维度取空 List,等价于该维度不过滤。
 *
 * 从 BleScanManager 剥离:纯构建逻辑,无实例状态依赖,可安全静态化。
 */
export default class BleScanFilterBuilder {
  /**
   * 构造 ble.ScanFilter 数组(可能为空)。
   * @param data Dart 端 BmStartScanArgs 的 Map 形式。
   * @returns ScanFilter 数组。
   */
  static buildScanFilters(data: Map<string, ScanArgsValue>): ble.ScanFilter[] {
    let withServices: List<string> = (data.get('with_services') as List<string>) ?? new List<string>();
    let withRemoteIds: List<string> = (data.get('with_remote_ids') as List<string>) ?? new List<string>();
    let withNames: List<string> = (data.get('with_names') as List<string>) ?? new List<string>();
    let withMsd: List<object> = (data.get('with_msd') as List<object>) ?? new List<object>();
    let withServiceData: List<object> = (data.get('with_service_data') as List<object>) ?? new List<object>();
    let filterArray: ble.ScanFilter[] = [];
    BleScanFilterBuilder.appendServiceFilters(filterArray, withServices);
    BleScanFilterBuilder.appendRemoteIdFilters(filterArray, withRemoteIds);
    BleScanFilterBuilder.appendNameFilters(filterArray, withNames);
    BleScanFilterBuilder.appendManufacturerDataFilters(filterArray, withMsd);
    BleScanFilterBuilder.appendServiceDataFilters(filterArray, withServiceData);
    return filterArray;
  }

  /** 按 service UUID 追加过滤器。 */
  private static appendServiceFilters(filterArray: ble.ScanFilter[], withServices: List<string>): void {
    for (let i = 0; i < withServices.length; i++) {
      let filter: ble.ScanFilter = {
        serviceUuid: withServices[i]
      };
      filterArray.push(filter);
    }
  }

  /** 按 remoteId(deviceId)追加过滤器。 */
  private static appendRemoteIdFilters(filterArray: ble.ScanFilter[], withRemoteIds: List<string>): void {
    for (let i = 0; i < withRemoteIds.length; i++) {
      let filter: ble.ScanFilter = {
        deviceId: withRemoteIds[i]
      };
      filterArray.push(filter);
    }
  }

  /** 按设备名追加过滤器。 */
  private static appendNameFilters(filterArray: ble.ScanFilter[], withNames: List<string>): void {
    for (let i = 0; i < withNames.length; i++) {
      let filter: ble.ScanFilter = {
        name: withNames[i]
      };
      filterArray.push(filter);
    }
  }

  /**
   * 按制造商数据(manufacturer_id/data/mask)追加过滤器。
   * data/mask 为 Dart 端传入的 UTF-8 字符串,经 stringToArrayBuffer 转为 ArrayBuffer。
   */
  private static appendManufacturerDataFilters(filterArray: ble.ScanFilter[],
    withMsd: List<object>): void {
    for (let i = 0; i < withMsd.length; i++) {
      let m: HashMap<string, ScanArgsValue> = withMsd.get(i) as HashMap<string, ScanArgsValue>;
      let id: number = (m.get('manufacturer_id') ?? 0) as number;
      let dataStr: string = m.get('data') as string;
      let maskStr: string = m.get('mask') as string;
      let filter: ble.ScanFilter = {
        manufactureId: id,
        manufactureData: BleUtils.stringToArrayBuffer(dataStr),
        manufactureDataMask: BleUtils.stringToArrayBuffer(maskStr),
      };
      filterArray.push(filter);
    }
  }

  /**
   * 按服务数据(service/data/mask)追加过滤器。
   * data/mask 为 Dart 端传入的 UTF-8 字符串,经 stringToArrayBuffer 转为 ArrayBuffer。
   */
  private static appendServiceDataFilters(filterArray: ble.ScanFilter[],
    withServiceData: List<object>): void {
    for (let i = 0; i < withServiceData.length; i++) {
      let m: HashMap<string, ScanArgsValue> = withServiceData.get(i) as HashMap<string, ScanArgsValue>;
      let serviceUuid: string = m.get('service') as string;
      let mdataStr: string = m.get('data') as string;
      let maskStr: string = m.get('mask') as string;
      let filter: ble.ScanFilter = {
        serviceUuid: serviceUuid,
        serviceData: BleUtils.stringToArrayBuffer(mdataStr),
        serviceDataMask: BleUtils.stringToArrayBuffer(maskStr),
      };
      filterArray.push(filter);
    }
  }
}
