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

/**
 * BLE 扫描设备数据模型,封装设备 MAC、名称、信号强度、广播记录、时间戳与可连接性等字段。
 */
export default class BleDevice {
  public deviceName: string = '';
  public deviceId: string = '';
  public scanRecord: Uint8Array = new Uint8Array();
  public rssi: number = 0;
  public timestampNanos: number = 0;
  public connectable: boolean = false;

  /**
   * 构造一个 BleDevice。
   * @param deviceId 设备 MAC 地址(远程标识)。
   * @param name 设备名称。
   * @param rssi 信号强度(可选)。
   * @param scanRecord 广播记录字节(可选)。
   * @param timestampNanos 发现时间戳(可选)。
   * @param connectable 是否可连接(可选)。
   */
  public constructor(deviceId: string, name: string, rssi?: number, scanRecord ?: Uint8Array, timestampNanos ?: number,
    connectable?: boolean) {
    this.deviceName = name;
    this.deviceId = deviceId;
    if (connectable !== undefined) {
      this.connectable = connectable;
    }
    if (scanRecord) {
      this.scanRecord = scanRecord;
    }
    if (rssi) {
      this.rssi = rssi;
    }
    if (timestampNanos) {
      this.timestampNanos = timestampNanos;
    }
  }

  /**
   * 复制一个 BleDevice 实例。
   * @param device 源设备。
   * @returns 新的 BleDevice 实例。
   */
  public static copy(device: BleDevice): BleDevice {
    return new BleDevice(device.deviceId, device.deviceName, device.rssi, device.scanRecord,
      device.timestampNanos);
  }

  /** 返回设备名称。
   * @returns 设备名称字符串。
   */
  public getName(): string {
    return this.deviceName;
  }

  /** 设置设备名称。
   * @param name 设备名称字符串。
   */
  public setName(name: string): void {
    this.deviceName = name;
  }

  /** 返回设备 MAC 地址。
   * @returns 设备 MAC 地址字符串。
   */
  public getMac(): string {
    return this.deviceId;
  }

  /** 返回由名称与 MAC 拼接的去重键(两者皆空时返回空串)。
   * @returns 名称与 MAC 拼接的去重键,两者皆空时返回空串。
   */
  public getKey(): string {
    if (this.deviceName !== null && this.deviceId !== null) {
      return this.deviceName + this.deviceId;
    }
    return '';
  }

  /** 返回是否可连接。 */
  public getConnectable(): boolean {
    return this.connectable;
  }

  /** 设置是否可连接。
   * @param connectable 是否可连接。
   */
  public setConnectable(connectable: boolean): void {
    this.connectable = connectable;
  }

  /** 返回广播记录字节。 */
  public getScanRecord(): Uint8Array {
    return this.scanRecord;
  }

  /** 设置广播记录字节。
   * @param scanRecord 广播记录字节。
   */
  public setScanRecord(scanRecord: Uint8Array): void {
    this.scanRecord = scanRecord;
  }

  /** 返回信号强度。 */
  public getRssi(): number {
    return this.rssi;
  }

  /** 设置信号强度。
   * @param rssi 信号强度。
   */
  public setRssi(rssi: number): void {
    this.rssi = rssi;
  }

  /** 返回发现时间戳。 */
  public getTimestampNanos(): number {
    return this.timestampNanos;
  }

  /** 设置发现时间戳。
   * @param timestampNanos 发现时间戳。
   */
  public setTimestampNanos(timestampNanos: number): void {
    this.timestampNanos = timestampNanos;
  }
}
