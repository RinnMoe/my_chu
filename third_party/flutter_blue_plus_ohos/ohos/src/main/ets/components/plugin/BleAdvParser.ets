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

import BleUtils from './BleUtils';

/** 广播数据解析结果。 */
export class AdvData {
  /** Flags（AD type 0x01），十六进制字符串。 */
  public flags: string | null = null;
  /** 服务 UUID 列表（已统一规范化为 128 位字符串）。 */
  public serviceUUIDs: string[] | null = null;
  /** 本地设备名（Local Name，AD type 0x08/0x09，UTF-8 解码后）。 */
  public localName: string | null = null;
  /** TX Power Level（AD type 0x0A），有符号值，单位 dBm。 */
  public txPowerLevel: number | null = null;
  /** 设备外观（Appearance，AD type 0x19）。 */
  public appearance: number | null = null;
  /** 服务数据（UUID -> hex payload 字符串）。 */
  public serviceData: Map<string, string> | null = null;
}

/**
 * BLE 广播数据解析工具集（横切关注点，无实例状态）。
 *
 * 从 BleScanManager 剥离的纯静态工具：parseAdvHexData（解析十六进制广播串为 AdvData）、
 * getManufacturerSpecificData（提取 Manufacturer Specific Data AD type 0xFF），
 * 以及按 AD type 分发的 applyAdvField 与各 parse* 子方法、format128BitUuid。
 *
 * 只依赖入参与 BleUtils（无 plugin/缓存字段依赖），故抽为独立工具类。
 *
 * 方法体来源：
 *  - getManufacturerSpecificData：取自 1.33.5 BleServiceParser.getManufacturerSpecificData
 *    （按 manufacturerId 分组并合并同 id 多块，返回 Map<number, Uint8Array>），
 *    保留该语义以兼容现有 scanCallback 的 manufacturer_data 上报契约。
 *  - parseAdvHexData / applyAdvField / 各 parse* 子方法 / format128BitUuid：取 2.1.0 结构
 *    （覆盖 16/32/128-bit UUID、TX power、外观、服务数据），向下兼容 1.33.5 仅取 localName 的用法。
 */
export default class BleAdvParser {
  /**
   * 从广播字节流中提取 Manufacturer Specific Data（AD type 0xFF）。
   *
   * 同一 manufacturerId 的多块数据按到达顺序合并；返回值不含 manufacturerId 本身，仅含 payload。
   * @param advBytes - 原始广播字节数组
   * @returns manufacturerId -> payload 的映射；无厂商数据返回空 Map
   */
  static getManufacturerSpecificData(advBytes: Uint8Array): Map<number, Uint8Array> {
    const manufacturerDataMap: Map<number, Uint8Array> = new Map<number, Uint8Array>();
    let n: number = 0;
    while (n < advBytes.byteLength) {
      // 广播结构为 TLV: [length][type][value...], fieldLen 计 type+value 字节数, 不含自身长度字节。
      const fieldLen = advBytes[n] & 0xFF;
      if (fieldLen <= 0) {
        break;
      }
      if (n + fieldLen >= advBytes.byteLength) {
        break;
      }
      const dataType = advBytes[n + 1] & 0xFF;
      // AD type 0xFF 为 Manufacturer Specific Data, fieldLen>=3 保证至少含 type(1) + manufacturerId(2)。
      if (dataType === 0xFF && fieldLen >= 3) {
        // manufacturerId 为小端 2 字节: low 在 n+2, high 在 n+3。
        const high = (advBytes[n + 3] & 0xFF) << 8;
        const low = (advBytes[n + 2] & 0xFF);
        const manufacturerId = high | low;
        // msdLen 排除 length(1) + type(1) + manufacturerId(2), 即纯 payload 长度。
        const msdLen = fieldLen - 3;
        const msdPtr = n + 4;
        const existing = manufacturerDataMap.get(manufacturerId);
        if (existing !== undefined && existing !== null) {
          // 同 manufacturerId 多块: 拼接已有 payload 与新 payload。
          const mergedData = new Uint8Array(existing.length + msdLen);
          mergedData.set(existing, 0);
          mergedData.set(advBytes.subarray(msdPtr, msdPtr + msdLen), existing.length);
          manufacturerDataMap.set(manufacturerId, mergedData);
        } else {
          manufacturerDataMap.set(manufacturerId, advBytes.subarray(msdPtr, msdPtr + msdLen));
        }
      }
      // 跳过 length(1) + fieldLen 个字节, 推进到下一个 AD 字段。
      n += fieldLen + 1;
    }
    return manufacturerDataMap;
  }

  /**
   * 解析广播十六进制字符串为 AdvData（服务 UUID/名称/TX power/外观/服务数据等）。
   * 支持 16/32/128-bit UUID 小端转换、本地名 UTF-8 解码等。各 AD type 由独立方法处理。
   * @param hexString - 广播数据的十六进制字符串
   * @returns 解析后的 AdvData
   */
  static parseAdvHexData(hexString: string): AdvData {
    let result: AdvData = new AdvData();
    let index: number = 0;
    result.serviceUUIDs = [];
    result.serviceData = new Map<string, string>();

    while (index < hexString.length) {
      // 每个字段为 [length][type][value]: length 计 type+value 字节数, 此处取 2 位 hex 为十进制长度。
      const length = Number.parseInt(hexString.substring(index, index + 2), 16);
      if (length === 0) {
        break;
      }
      const type = Number.parseInt(hexString.substring(index + 2, index + 4), 16);
      // value 占 (length-1) 字节, 转为 hex 后为 (length*2-2) 个字符。
      const data = hexString.substring(index + 4, index + 4 + (length * 2 - 2));
      BleAdvParser.applyAdvField(result, type, data);
      // 推进 length(1) + type+value(length) 个字节, 即 (length+1)*2 个 hex 字符。
      index += (length + 1) * 2;
    }
    return result;
  }

  /** 按 AD type 分发到对应解析方法。 */
  private static applyAdvField(result: AdvData, type: number, data: string): void {
    switch (type) {
      case 0x01:
        result.flags = data;
        break;
      case 0x02: // Incomplete List of 16-bit Service UUIDs
      case 0x03: // Complete List of 16-bit Service UUIDs
        BleAdvParser.parse16BitServiceUuids(result, data);
        break;
      case 0x04: // Incomplete List of 32-bit Service UUIDs
      case 0x05: // Complete List of 32-bit Service UUIDs
        BleAdvParser.parse32BitServiceUuids(result, data);
        break;
      case 0x06: // Incomplete List of 128-bit Service UUIDs
      case 0x07: // Complete List of 128-bit Service UUIDs
        BleAdvParser.parse128BitServiceUuids(result, data);
        break;
      case 0x08: // Short Local Name
      case 0x09: // Complete Local Name
        BleAdvParser.parseLocalName(result, data);
        break;
      case 0x0A: // TX Power Level
        BleAdvParser.parseTxPower(result, data);
        break;
      case 0x16: // Service Data - 16-bit UUID
        BleAdvParser.parseServiceData16(result, data);
        break;
      case 0x20: // Service Data - 32-bit UUID
        BleAdvParser.parseServiceData32(result, data);
        break;
      case 0x21: // Service Data - 128-bit UUID
        BleAdvParser.parseServiceData128(result, data);
        break;
      case 0x19: // Appearance
        BleAdvParser.parseAppearance(result, data);
        break;
      default:
        break;
    }
  }

  /** 解析 16-bit 服务 UUID 列表（小端 → 大端 → 128 位展开），追加到 result.serviceUUIDs。 */
  private static parse16BitServiceUuids(result: AdvData, data: string): void {
    for (let i = 0; i < data.length; i += 4) {
      if (i + 4 <= data.length) {
        let le = data.substring(i, i + 4);
        // 16-bit UUID 为小端: 交换高低字节得到大端, 再展开为 128 位规范串。
        let be = le.substring(2, 4) + le.substring(0, 2);
        result.serviceUUIDs?.push(BleUtils.uuid128(be));
      }
    }
  }

  /** 解析 32-bit 服务 UUID 列表（小端 → 大端 → 128 位展开），追加到 result.serviceUUIDs。 */
  private static parse32BitServiceUuids(result: AdvData, data: string): void {
    for (let i = 0; i < data.length; i += 8) {
      if (i + 8 <= data.length) {
        let le = data.substring(i, i + 8);
        // 32-bit UUID 为小端: 按 2 字节为单位逆序重排为 4 段大端, 再展开为 128 位规范串。
        let be = le.substring(6, 8) + le.substring(4, 6) + le.substring(2, 4) + le.substring(0, 2);
        result.serviceUUIDs?.push(BleUtils.uuid128(be));
      }
    }
  }

  /** 解析 128-bit 服务 UUID 列表（按字节反转后格式化），追加到 result.serviceUUIDs。 */
  private static parse128BitServiceUuids(result: AdvData, data: string): void {
    for (let i = 0; i < data.length; i += 32) {
      if (i + 32 <= data.length) {
        result.serviceUUIDs?.push(BleAdvParser.format128BitUuid(data.substring(i, i + 32)));
      }
    }
  }

  /** 解析本地名（UTF-8 解码），写入 result.localName。 */
  private static parseLocalName(result: AdvData, data: string): void {
    let nameBytes: number[] = [];
    for (let i = 0; i < data.length; i += 2) {
      nameBytes.push(Number.parseInt(data.substring(i, i + 2), 16));
    }
    result.localName = BleUtils.utf8BytesToString(nameBytes);
  }

  /** 解析 TX Power Level（有符号字节），写入 result.txPowerLevel。 */
  private static parseTxPower(result: AdvData, data: string): void {
    if (data.length >= 2) {
      let txPower = Number.parseInt(data.substring(0, 2), 16);
      // 广播中 TX power 为有符号字节, 超过 127 表示负数, 需减 256 转回有符号值。
      if (txPower > 127) {
        txPower -= 256;
      }
      result.txPowerLevel = txPower;
    }
  }

  /** 解析 16-bit 服务数据（UUID + hex payload），写入 result.serviceData。 */
  private static parseServiceData16(result: AdvData, data: string): void {
    if (data.length >= 4) {
      // 前 2 字节为 16-bit UUID(小端, 交换高低字节), 其余为服务数据 hex payload。
      let le = data.substring(0, 4);
      let be = le.substring(2, 4) + le.substring(0, 2);
      result.serviceData?.set(BleUtils.uuid128(be), data.substring(4));
    }
  }

  /** 解析 32-bit 服务数据（UUID + hex payload），写入 result.serviceData。 */
  private static parseServiceData32(result: AdvData, data: string): void {
    if (data.length >= 8) {
      // 前 4 字节为 32-bit UUID(小端, 按 2 字节逆序重排), 其余为服务数据 hex payload。
      let le = data.substring(0, 8);
      let be = le.substring(6, 8) + le.substring(4, 6) + le.substring(2, 4) + le.substring(0, 2);
      result.serviceData?.set(BleUtils.uuid128(be), data.substring(8));
    }
  }

  /** 解析 128-bit 服务数据（UUID + hex payload），写入 result.serviceData。 */
  private static parseServiceData128(result: AdvData, data: string): void {
    if (data.length >= 32) {
      // 前 16 字节为 128-bit UUID(小端, 整体字节反转), 其余为服务数据 hex payload。
      result.serviceData?.set(BleAdvParser.format128BitUuid(data.substring(0, 32)), data.substring(32));
    }
  }

  /** 解析 Appearance（小端 16-bit），写入 result.appearance。 */
  private static parseAppearance(result: AdvData, data: string): void {
    if (data.length >= 4) {
      // Appearance 为小端 16-bit: 交换高低字节得大端后解析为数值。
      let le = data.substring(0, 4);
      let be = le.substring(2, 4) + le.substring(0, 2);
      result.appearance = Number.parseInt(be, 16);
    }
  }

  /** 将 32 字符小端 128-bit UUID 串反转字节序并格式化为标准 8-4-4-4-12 形式（小写）。 */
  static format128BitUuid(uuid128LittleEndian: string): string {
    let reversedBytes: string = '';
    // 128-bit UUID 按小端字节序传输: 从末尾以 2 字符(1 字节)为步长逆序拼接, 转为大端。
    for (let j = uuid128LittleEndian.length - 2; j >= 0; j -= 2) {
      reversedBytes += uuid128LittleEndian.substring(j, j + 2);
    }
    let formatted: string = `${reversedBytes.substring(0, 8)}-${reversedBytes.substring(8, 12)}` +
      `-${reversedBytes.substring(12, 16)}-${reversedBytes.substring(16, 20)}-${reversedBytes.substring(20, 32)}`;
    return formatted.toLowerCase();
  }
}
