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

import { connection, constant } from '@kit.ConnectivityKit';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import access from '@ohos.bluetooth.access';

/**
 * 蓝牙工具与常量集合（纯静态，无实例状态）。
 *
 * 集中维护 UUID 规范化、字节数组转换、蓝牙适配器/绑定/连接状态枚举映射、
 * hilog 日志级别与输出，以及 BmBluetoothDevice 等 Flutter 端 Map 结构构造。
 * 所有方法均为静态方法，跨 Manager 共享，避免在各类中重复实现。
 *
 * 方法体来源：1.33.5 BleServiceParser（uuid128/uuidStr/stringToArrayBuffer/
 * typedArrayToBuffer/bytesToHexScan/bytesToHexArrayBuffer/buildBluetoothDevice→buildBluetoothDevice/
 * buildAdapterStateEnum→buildAdapterStateEnum/buildBondStateEnum→buildBondStateEnum/
 * buildConnectionStateEnum→buildConnectionStateEnum/isAdapterOn）。
 * utf8BytesToString/delay/log 在 1.33.5 中无独立等价方法（1.33.5 parseAdvHexData 用
 * String.fromCharCode 按单字节解码、日志/loglevel 内联在主插件），此处按 2.1.0 结构补齐。
 */
export default class BleUtils {
  /** CCCD 描述符固定 UUID（16-bit 0x2902），用于开启/关闭特征通知。 */
  public static readonly CCCD: string = '2902';
  /** hilog TAG，统一日志前缀，便于按插件过滤日志。 */
  public static readonly TAG: string = '[FBP-Ohos]';
  /** hilog domain，插件日志域编号。 */
  public static readonly DOMAIN: number = 0x00FF;

  /**
   * 当前日志级别，低于此级别的日志将被忽略。由 handleSetLogLevel 更新。
   *
   * 【设计取舍 · intentional known limitation】此字段为 static，多 FlutterEngine / 多插件实例
   * 场景下实例间共享同一值（无法按实例隔离日志级别）。保留 static 是有意为之：
   *  - 真正隔离需将 logLevel 移至插件实例，并让每个 BleUtils.log(...) 调用点透传实例
   *    （约 105 处、跨 9 个文件），属侵入式重构。
   *  - BLE 插件在单 FlutterEngine 下为单实例（绝大多数应用），多引擎同时使用 BLE 极罕见；
   *    且即便发生，共享的仅是「日志输出粒度」，不影响任何功能正确性。
   *  - 与 Android 上游（FlutterBluePlusPlugin.java）保持一致，其日志级别同样为 static。
   * 故此处显式保留 static 并记录该限制，多引擎隔离留待后续如确有需求再做。
   */
  public static logLevel: hilog.LogLevel = hilog.LogLevel.DEBUG;

  /**
   * 将任意长度 UUID 规范化为 128-bit 小写形式。
   * 4 位 → 16-bit 补全模板，8 位 → 32-bit 补全模板，其它原样小写。
   * @param uuid - 原始 UUID 字符串（4/8/36 字符）
   * @returns 128-bit 小写 UUID 字符串
   */
  static uuid128(uuid: string): string {
    if (uuid.length === 4) {
      // 16-bit uuid
      return `0000${uuid}-0000-1000-8000-00805f9b34fb`.toLowerCase();
    } else if (uuid.length === 8) {
      // 32-bit uuid
      return `${uuid}-0000-1000-8000-00805f9b34fb`.toLowerCase();
    } else {
      // 128-bit uuid
      return uuid.toLowerCase();
    }
  }

  /**
   * 将 UUID 转换为最短可读形式（16/32/128-bit）。
   * 128-bit 若符合蓝牙基础模板则截取为 16-bit 或 32-bit，否则返回完整 128-bit。
   * @param uuid - 原始 UUID 字符串
   * @returns 最短可读 UUID 字符串
   */
  static uuidStr(uuid: string): string {
    uuid = BleUtils.uuid128(uuid);
    let starts: boolean = uuid.startsWith('0000');
    let ends: boolean = uuid.endsWith('-0000-1000-8000-00805f9b34fb');
    if (starts && ends) {
      // 16-bit
      return uuid.substring(4, 8);
    } else if (ends) {
      // 32-bit
      return uuid.substring(0, 8);
    } else {
      // 128-bit
      return uuid;
    }
  }

  /**
   * 将 UTF-8 字节数组解码为字符串（手动解码，不依赖 TextDecoder）。
   * 支持 1-4 字节 UTF-8 码点。
   * @param bytes - UTF-8 字节数组
   * @returns 解码后的字符串
   */
  static utf8BytesToString(bytes: number[]): string {
    let result: string = '';
    let i: number = 0;
    while (i < bytes.length) {
      let byte: number = bytes[i];
      let codePoint: number;

      if (byte < 0x80) {
        // 1 字节序列：0xxxxxxx，码点即首字节本身
        codePoint = byte;
        i++;
      } else if (byte < 0xE0) {
        // 2 字节序列：110xxxxx 10xxxxxx，取首字节低 5 位与续字节低 6 位拼接
        codePoint = ((byte & 0x1F) << 6) | (bytes[i + 1] & 0x3F);
        i += 2;
      } else if (byte < 0xF0) {
        // 3 字节序列：1110xxxx + 两个续字节，分别取 4/6/6 位拼接
        codePoint = ((byte & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F);
        i += 3;
      } else {
        // 4 字节序列：11110xxx + 三个续字节，分别取 3/6/6/6 位拼接
        codePoint = ((byte & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) |
          ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
        i += 4;
      }

      result += String.fromCodePoint(codePoint);
    }
    return result;
  }

  /**
   * 将字节数组转换为小写十六进制字符串（用于扫描数据等场景）。
   * @param bytes - 字节数组，为 null 时返回空串
   * @returns 小写十六进制字符串
   */
  static bytesToHexScan(bytes: Uint8Array): string {
    if (bytes === null) {
      return '';
    }
    let hexString: string = '';
    for (let i = 0; i < bytes.length; i++) {
      const hex = bytes[i].toString(16);
      hexString += (hex.length === 1 ? '0' : '') + hex;
    }
    return hexString;
  }

  /**
   * 将字节数组转换为小写十六进制字符串（用于 ArrayBuffer 场景）。
   * 与 bytesToHexScan 行为一致，保留以兼容既有调用点。
   * @param bytes - 字节数组，为 null 时返回空串
   * @returns 小写十六进制字符串
   */
  static bytesToHexArrayBuffer(bytes: Uint8Array): string {
    if (bytes === null) {
      return '';
    }
    let hexString: string = '';
    for (let i = 0; i < bytes.length; i++) {
      const hex = bytes[i].toString(16);
      hexString += (hex.length === 1 ? '0' : '') + hex;
    }
    return hexString;
  }

  /**
   * 将字符串编码为 ArrayBuffer（UTF-8）。
   * @param str - 输入字符串
   * @returns UTF-8 编码的 ArrayBuffer
   */
  static stringToArrayBuffer(str: string): ArrayBuffer {
    const buffers = buffer.from(str, 'utf8');
    return buffers.buffer.slice(buffers.byteOffset, buffers.byteOffset + buffers.length);
  }

  /**
   * 将 Uint8Array 转换为独立的 ArrayBuffer（拷贝，避免视图共享底层 buffer 带来的越界问题）。
   * @param array - 输入 Uint8Array
   * @returns 对应字节范围的 ArrayBuffer
   */
  static typedArrayToBuffer(array: Uint8Array): ArrayBuffer {
    return array.buffer.slice(array.byteOffset, array.byteLength + array.byteOffset);
  }

  /**
   * 构造 BmBluetoothDevice Map（remote_id + platform_name）。
   * @param deviceAddress - 设备 MAC 地址
   * @param name - 可选设备名称，传入则填充 platform_name
   * @returns 包含 remote_id（与可选 platform_name）的 Map
   */
  static buildBluetoothDevice(deviceAddress: string, name?: string): Map<string, string> {
    let map: Map<string, string> = new Map();
    map.set('remote_id', deviceAddress);
    if (name) {
      map.set('platform_name', name);
    }
    return map;
  }

  /**
   * 将 OHOS 适配器状态枚举映射为 Flutter 端约定数值。
   * @param as - access.BluetoothState 原始枚举值
   * @returns Flutter 端 adapter_state 数值
   */
  static buildAdapterStateEnum(as: number): number {
    switch (as) {
      case access.BluetoothState.STATE_OFF:
        return 6;
      case access.BluetoothState.STATE_ON:
        return 4;
      case access.BluetoothState.STATE_TURNING_OFF:
        return 5;
      case access.BluetoothState.STATE_TURNING_ON:
        return 3;
      default:
        return 0;
    }
  }

  /**
   * 将 OHOS 绑定状态枚举映射为 Flutter 端约定数值。
   * @param bs - connection.BondState 原始枚举值
   * @returns Flutter 端 bond_state 数值
   */
  static buildBondStateEnum(bs: number): number {
    switch (bs) {
      case connection.BondState.BOND_STATE_INVALID:
        return 0;
      case connection.BondState.BOND_STATE_BONDING:
        return 1;
      case connection.BondState.BOND_STATE_BONDED:
        return 2;
      default:
        return 0;
    }
  }

  /**
   * 将 OHOS 连接状态枚举映射为 Flutter 端约定数值。
   * @param cs - constant.ProfileConnectionState 原始枚举值
   * @returns Flutter 端 connection_state 数值
   */
  static buildConnectionStateEnum(cs: number): number {
    switch (cs) {
      case constant.ProfileConnectionState.STATE_DISCONNECTED:
        return 0;
      case constant.ProfileConnectionState.STATE_CONNECTED:
        return 1;
      default:
        return 0;
    }
  }

  /**
   * 判断蓝牙适配器是否已开启（STATE_ON）。
   * 读取状态失败时返回 false，避免异常冒泡。
   * @returns 适配器是否开启
   */
  static isAdapterOn(): boolean {
    try {
      return access.getState() === access.BluetoothState.STATE_ON;
    } catch (e) {
      return false;
    }
  }

  /**
   * 异步等待指定毫秒数。用于重试/退避等场景。
   * @param milliseconds - 等待毫秒数
   * @returns 在指定时间后 resolve 的 Promise
   */
  static delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, milliseconds);
    });
  }

  /**
   * 按当前 loglevel 输出 hilog 日志。低于 loglevel 的级别直接返回。
   * @param level - 日志级别
   * @param message - 日志内容
   */
  static log(level: hilog.LogLevel, message: string): void {
    // hilog 级别数值越大越严重（DEBUG=3…FATAL=7），故小于当前级别的为更宽松日志，直接丢弃
    if (level < BleUtils.logLevel) {
      return;
    }
    switch (level) {
      case hilog.LogLevel.DEBUG:
        hilog.debug(BleUtils.DOMAIN, BleUtils.TAG, message);
        break;
      case hilog.LogLevel.INFO:
        hilog.info(BleUtils.DOMAIN, BleUtils.TAG, message);
        break;
      case hilog.LogLevel.WARN:
        hilog.warn(BleUtils.DOMAIN, BleUtils.TAG, message);
        break;
      case hilog.LogLevel.ERROR:
        hilog.error(BleUtils.DOMAIN, BleUtils.TAG, message);
        break;
      case hilog.LogLevel.FATAL:
        hilog.fatal(BleUtils.DOMAIN, BleUtils.TAG, message);
        break;
      default:
        hilog.debug(BleUtils.DOMAIN, BleUtils.TAG, message);
        break;
    }
  }
}
