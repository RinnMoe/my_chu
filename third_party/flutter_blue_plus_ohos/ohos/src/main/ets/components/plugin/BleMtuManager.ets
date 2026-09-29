/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 ("the License");
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
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/**
 * 蓝牙 MTU 管理器。
 *
 * 集中处理 MTU 协商请求：解析 remote_id/mtu、经 plugin.connectionManager 反查已连接设备的
 * GattClientDevice、等待配绑定收尾（waitIfBonding）、调用 setBLEMtuSize 发起协商，
 * 协商成功后更新 plugin.gattCache.mtuMap 并回传 OnMtuChanged。
 *
 * 跨 Manager 访问（与 BleConnectionManager 访问 gattCache/bondManager 模式一致）：
 *  - 已连接设备 GattClientDevice → plugin.connectionManager.connectedDevices
 *  - 配绑定等待 → plugin.connectionManager.waitIfBonding()
 *  - MTU 缓存 mtuMap（跨组共享，由 gattCache 持有）→ plugin.gattCache.mtuMap
 *  - Flutter 通道 → plugin.channel
 *  - 日志 → BleUtils.log
 *
 * 方法体来源：1.33.5 FlutterBluePlusOhosPlugin.handleRequestMtu，适配 this.X → this.plugin.X。
 */
export default class BleMtuManager {
  /** 插件引用，用于访问 connectionManager.connectedDevices、channel、gattCache.mtuMap。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /**
   * 构造 MTU 管理器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * 处理 requestMtu：发起 MTU 协商并回传 OnMtuChanged。
   *
   * 流程：解析 remote_id/mtu → 反查已连接 GattClientDevice → waitIfBonding →
   * gatt.setBLEMtuSize(mtu)（try-catch 捕获 BusinessError）→ 成功则写 mtuMap 并发
   * OnMtuChanged（remote_id/mtu/success/error_code/error_string）→ result.success(true)。
   *
   * 与 2.1.0 回调式实现不同：1.33.5 采用同步就绪式回传——请求即写 mtuMap 为请求值并
   * 立即回传，Dart 侧 requestMtu 的 onMtuChanged 监听可即时拿到结果。
   * @param call - 方法调用，args 含 remote_id/mtu
   * @param result - 结果回调
   */
  async requestMtu(call: MethodCall, result: MethodResult): Promise<void> {
    let data: Map<string, string | number> = call.args;
    let remoteId: string = data.get('remote_id') as string;
    let mtu: number = data.get('mtu') as number;
    let gatt: ble.GattClientDevice | undefined =
      this.plugin.connectionManager.connectedDevices.get(remoteId);
    if (gatt === null || gatt === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'gatt.requestMtu() returned false');
      result.error('requestMtu', 'gatt.requestMtu() returned false', null);
      return;
    }
    await this.plugin.connectionManager.waitIfBonding();
    let mtuFlag: boolean = true;
    let errCode: number = 0;
    let errMsg: string = 'GATT_SUCCESS';
    try {
      gatt.setBLEMtuSize(mtu);
    } catch (e) {
      errCode = (e as BusinessError)?.code ?? 0;
      errMsg = (e as BusinessError)?.message ?? '';
      mtuFlag = false;
    }
    if (!mtuFlag) {
      BleUtils.log(hilog.LogLevel.ERROR, 'gatt.requestMtu() returned false');
      result.error('requestMtu', 'gatt.requestMtu() returned false', null);
      return;
    }
    this.plugin.gattCache.mtuMap.set(remoteId, mtu);
    let response: Map<string, string | number> = new Map<string, string | number>();
    response.set('remote_id', remoteId);
    response.set('mtu', mtu);
    response.set('success', mtuFlag ? 1 : 0);
    response.set('error_code', errCode);
    response.set('error_string', errMsg);
    this.plugin.channel?.invokeMethod('OnMtuChanged', response);
    result.success(true);
  }
}
