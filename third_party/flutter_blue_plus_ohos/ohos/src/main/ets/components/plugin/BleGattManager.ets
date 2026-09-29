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
import { List } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BleUtils from './BleUtils';
import BleGattShared from './BleGattShared';
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/**
 * 蓝牙 GATT 管理器（facade）。
 *
 * 集中管理 GATT 服务发现（discoverServices）与 RSSI 读取（readRssi），以及服务发现
 * 完成后的回传回调 onDiscoveredServices。读写/通知/MTU 等业务委托给对应子 Manager，
 * 本类只承担"服务发现 + RSSI + 服务树回传"这三项 GATT facade 职责。
 *
 * 设计说明：
 *  - onCharacteristicReceived（读取/通知特征值回传）按 2.1.0 结构归属 BleNotifyManager，
 *    本类不重复实现（通知回调与 CCCD 写入强相关，放通知管理器更内聚）。
 *  - 跨 Manager 共享状态经 plugin 中介访问，避免子 Manager 间互相持有引用：
 *    已连接设备/等待配对经 plugin.connectionManager，平台通道经 plugin.channel。
 *
 * 方法体来源：1.33.5 FlutterBluePlusOhosPlugin（handleReadRssi/handleDiscoverServices/
 * onDiscoveredServices），适配 this.connectedDevices → this.plugin.connectionManager.connectedDevices、
 * this.waitIfBonding() → this.plugin.connectionManager.waitIfBonding()、
 * this.parser.buildBluetoothService → BleGattShared.buildBluetoothService、
 * this.log → BleUtils.log、this.channel → this.plugin.channel。
 */
export default class BleGattManager {
  /** 插件引用，用于访问 connectionManager/channel 等共享状态。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /**
   * 构造 GATT 管理器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * 处理 readRssi：读取已连接设备的 RSSI 值并通过 OnReadRssi 回传。
   *
   * RSSI=0 dBm 是 BLE 规范中的合法读数（设备贴近时常见的强信号），仅在 getRssiValue
   * 返回 null/undefined 时视为失败；getRssiValue 出错会抛异常被 catch 捕获，不会返回 0，
   * 故此处用 `=== null || === undefined` 判定失败，绝不能用 `=== 0`（会把合法的 0dBm 误判为错误）。
   *
   * @param call - 方法调用，args 为 remoteId
   * @param result - 结果回调，用于向 Flutter 返回成功或错误
   */
  async readRssi(call: MethodCall, result: MethodResult): Promise<void> {
    let remoteId: string = call.args as string;
    // check connection
    let gattMaybe: ble.GattClientDevice | undefined = this.plugin.connectionManager.connectedDevices.get(remoteId);
    if (gattMaybe === null || gattMaybe === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'device is disconnected');
      result.error('readRssi', 'device is disconnected', null);
      return;
    }
    // 显式收窄为非空引用，供 runGatt 闭包内使用（闭包是独立作用域，外层判空不传导）。
    let gatt: ble.GattClientDevice = gattMaybe;
    // wait if any device is bonding (increases reliability)
    await this.plugin.connectionManager.waitIfBonding();
    let readRssiFlag: boolean = true;
    let rssiValue: number = 0;
    let errcode: number = 0;
    let errMsg: string = 'GATT_SUCCESS';
    // 按设备串行执行 GATT 操作，避免与其它 GATT 操作并发冲突。
    try {
      await this.plugin.gattCache.runGatt(remoteId, async () => {
        rssiValue = await gatt.getRssiValue();
      });
    } catch (e) {
      readRssiFlag = false;
      BleUtils.log(hilog.LogLevel.ERROR, 'readRssi getRssiValue: ' + (e as BusinessError)?.message);
    }
    // read rssi: 仅当读取结果为 null/undefined 视为失败。RSSI 0 dBm 是合法信号强度，不视为错误。
    if (rssiValue === null || rssiValue === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'gatt.readRemoteRssi() returned null');
      result.error('readRssi', 'gatt.readRemoteRssi() returned null', null);
      return;
    }
    result.success(true);
    let response: Map<string, string | number> = new Map();
    response.set('remote_id', remoteId);
    response.set('rssi', rssiValue);
    response.set('success', readRssiFlag ? 1 : 0);
    response.set('error_code', errcode);
    response.set('error_string', errMsg);
    this.plugin.channel?.invokeMethod('OnReadRssi', response);
  }

  /**
   * 处理 discoverServices：发现已连接设备的 GATT 服务并回传 OnDiscoveredServices。
   *
   * OHOS 的 getServices 为一次性同步获取（系统在连接后已发现），空结果视为失败；
   * 发现成功后调用 onDiscoveredServices 组装服务树回传 Dart 侧。
   *
   * @param call - 方法调用，args 为 remoteId
   * @param result - 结果回调，用于向 Flutter 返回成功或错误
   */
  async discoverServices(call: MethodCall, result: MethodResult): Promise<void> {
    let remoteId: string = call.args as string;
    // check connection
    let gattMaybe: ble.GattClientDevice | undefined = this.plugin.connectionManager.connectedDevices.get(remoteId);
    if (gattMaybe === null || gattMaybe === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'device is disconnected');
      result.error('discoverServices', 'device is disconnected', null);
      return;
    }
    // 显式收窄为非空引用，供 runGatt 闭包内使用（闭包是独立作用域，外层判空不传导）。
    let gatt: ble.GattClientDevice = gattMaybe;
    // wait if any device is bonding (increases reliability)
    await this.plugin.connectionManager.waitIfBonding();
    // 按设备串行执行 GATT 操作，避免 OHOS BLE 栈 2900011 "operation is busy" 错误。
    // discoverServices 必须加锁：它调 gatt.getServices()，且完成后 Flutter 端会自动
    // 触发 setNotifyValue（如 1801/2a05 Service Changed），如果 discoverServices 还没完成，
    // setNotifyValue 就会与它冲突。
    await this.plugin.gattCache.runGatt(remoteId, async () => {
      // discover services
      let services: ble.GattService[] = await gatt.getServices();
      if (services === null || services.length === 0) {
        BleUtils.log(hilog.LogLevel.ERROR, 'gatt.discoverServices() returned false');
        result.error('discoverServices', 'gatt.discoverServices() returned false', null);
        return;
      }
      // 缓存发现的服务，后续 read/write/setNotifyValue 可直接使用，避免重复调 getServices()
      this.plugin.gattCache.deviceServicesMap.set(remoteId, services);
      this.onDiscoveredServices(services, remoteId);
      result.success(true);
    });
  }

  /**
   * 服务发现完成后回传 OnDiscoveredServices（含 BmBluetoothService 树）。
   *
   * 遍历顶层 GATT 服务，逐个构造 BmBluetoothService（primaryService 传 null 表示顶层主服务），
   * 连同 remote_id/success/error_code/error_string 一并通过 OnDiscoveredServices 回传，
   * 供 Dart 侧构建其服务/特征/描述符模型。
   *
   * @param gattServices - 已发现的 GATT 服务数组
   * @param remoteId - 设备 ID
   */
  onDiscoveredServices(gattServices: ble.GattService[], remoteId: string): void {
    let services: List<object> = new List<object>();
    gattServices.forEach((service) => {
      services.add(BleGattShared.buildBluetoothService(service, null, remoteId, gattServices));
    });
    let response: Map<string, object | string | number> = new Map();
    response.set('success', 1);
    response.set('error_code', 0);
    response.set('error_string', 'GATT_SUCCESS');
    response.set('remote_id', remoteId as string);
    response.set('services', services);
    this.plugin.channel?.invokeMethod('OnDiscoveredServices', response);
  }
}
