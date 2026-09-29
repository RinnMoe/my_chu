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
import { ble, connection } from '@kit.ConnectivityKit';
import { List } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BleUtils from './BleUtils';
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/**
 * 蓝牙配对（Bond）管理器。
 *
 * 从 FlutterBluePlusOhosPlugin 剥离的配对状态与方法：持有 bondingDevices（BONDING 态创建的
 * GattClientDevice，用于 close）、bondStateChangeCallback（connection.on('bondStateChange') 回调），
 * 以及 getBondedDevices / getBondState / createBond / removeBond 四个 method handler。
 *
 * 跨 Manager 访问：
 *  - createBond 需读取已连接设备 GattClientDevice，经 plugin.connectionManager.connectedDevices
 *    反向查询（与 BleGattManager 访问 connectedDevices 的方式一致）。
 *  - bondingDevices 内的 GattClientDevice 生命周期跨越连接断开事件，连接侧断开/清理时须调用
 *    clearBondingState 释放该设备的配对态资源（见调用方 disconnect/handleDisconnected/cleanup）。
 *
 * 箭头函数回调保持成员属性形式，保证 connection.on/off 传引用时 this 不丢失。
 * 方法体来源：1.33.5 FlutterBluePlusOhosPlugin（onBondStateChanged/handleGetBondedDevices/
 * handleGetBondState/handleCreateBond/handleRemoveBond），适配 this.X → this.plugin.X。
 */
export default class BleBondManager {
  /** 插件引用，用于访问 connectionManager.connectedDevices、channel。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /** 配对中的设备（BONDING 态创建的 GattClient，用于 close）。 */
  public bondingDevices: Map<string, ble.GattClientDevice> = new Map();

  /**
   * bondStateChange 订阅状态标志位：connection.on('bondStateChange') 注册后置 true，off 后置 false。
   * 追踪订阅状态，使 on/off 能幂等执行并避免无效 off（off 未订阅监听会抛异常/产生噪音）。
   */
  public bondStateSubscribed: boolean = false;

  /**
   * 构造配对管理器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * bondStateChange 回调，成员属性箭头函数，便于 on/off 精确传引用。
   *
   * BONDING 态创建 GattClientDevice 存入 bondingDevices（供后续配对相关操作及 close）；
   * 其他态 close 并移除（若仍存在）。配对状态变化回传 OnBondStateChanged。
   */
  public bondStateChangeCallback: (data: connection.BondStateParam) => void =
    (data: connection.BondStateParam) => {
      let gatt: ble.GattClientDevice | null = null;
      try {
        gatt = ble.createGattClientDevice(data.deviceId);
        if (data.state === connection.BondState.BOND_STATE_BONDING) {
          // 重新进入 BONDING 前，先释放 Map 中可能残留的旧 GattClientDevice，
          // 避免 set 覆盖引用导致旧实例泄漏（原生 BLE 资源未 close）。
          let staleGatt: ble.GattClientDevice | undefined = this.bondingDevices.get(data.deviceId);
          if (staleGatt !== undefined && staleGatt !== gatt) {
            try {
              staleGatt.close();
            } catch (e) {
              BleUtils.log(hilog.LogLevel.ERROR, 'onBondStateChanged stale close: ' + (e as BusinessError)?.message);
            }
          }
          this.bondingDevices.set(data.deviceId, gatt);
        } else {
          // 状态离开 BONDING：BONDING 期间存入的旧实例必须 close（此前仅 delete 未 close，导致原生资源泄漏）；
          // 本次新建的临时实例同样必须 close。
          let bondedGatt: ble.GattClientDevice | undefined = this.bondingDevices.get(data.deviceId);
          this.bondingDevices.delete(data.deviceId);
          if (bondedGatt !== undefined && bondedGatt !== gatt) {
            try {
              bondedGatt.close();
            } catch (e) {
              BleUtils.log(hilog.LogLevel.ERROR, 'onBondStateChanged bonded close: ' + (e as BusinessError)?.message);
            }
          }
          try {
            gatt.close();
          } catch (e) {
            BleUtils.log(hilog.LogLevel.ERROR, 'onBondStateChanged close: ' + (e as BusinessError)?.message);
          }
        }
      } catch (e) {
        BleUtils.log(hilog.LogLevel.ERROR, 'onBondStateChanged createGatt: ' + (e as BusinessError)?.message);
        if (gatt !== null) {
          try {
            gatt.close();
          } catch (e) {
            BleUtils.log(hilog.LogLevel.ERROR, 'onBondStateChanged cleanup close: ' + (e as BusinessError)?.message);
          }
        }
      }
      let map: Map<string, string | number | null> = new Map();
      map.set('remote_id', data.deviceId);
      map.set('bond_state', BleUtils.buildBondStateEnum(data.state));
      map.set('prev_state', null);
      this.plugin.channel?.invokeMethod('OnBondStateChanged', map);
    };

  /**
   * 设备断开/清理时调用：关闭并移除该设备在 BONDING 态创建的 GattClientDevice，
   * 避免原生 BLE 资源泄漏。幂等。
   *
   * 连接侧（BleConnectionManager.disconnect / handleDisconnected / disconnectAllDevices / cleanup）
   * 必须在断开该设备时调用此方法，以闭环释放 bondingDevices 中的资源。
   * @param deviceId - 设备 ID
   */
  clearBondingState(deviceId: string): void {
    let bondingGatt: ble.GattClientDevice | undefined = this.bondingDevices.get(deviceId);
    if (bondingGatt !== null && bondingGatt !== undefined) {
      try {
        bondingGatt.close();
      } catch (e) {
        BleUtils.log(hilog.LogLevel.WARN, 'clearBondingState close failed: ' + (e as BusinessError)?.message);
      }
    }
    this.bondingDevices.delete(deviceId);
  }

  /**
   * 清空所有配对态资源。cleanup 全局清理时调用。
   */
  clearAll(): void {
    this.bondingDevices.forEach((gatt: ble.GattClientDevice) => {
      try {
        gatt.close();
      } catch (e) {
        BleUtils.log(hilog.LogLevel.WARN, 'clearAll close gatt failed: ' + (e as BusinessError)?.message);
      }
    });
    this.bondingDevices.clear();
  }

  /**
   * 处理 getBondedDevices：返回系统已配对设备列表（含设备名）。
   * 不访问任何连接状态字段，仅依赖 connection.getPairedDevices + 局部 gatt + BleUtils。
   * @param call - 方法调用
   * @param result - 结果回调
   */
  async getBondedDevices(call: MethodCall, result: MethodResult): Promise<void> {
    let devices: string[] = connection.getPairedDevices();
    let deviceList: List<Map<string, object | string>> = new List();
    // forEach(async) 不会等待，result 在名称就绪前就返回，改用 for 循环 + await。
    // 临时 GattClientDevice 用 try-finally close，避免每次泄漏。
    for (let device of devices) {
      let name: string = '';
      let gatt: ble.GattClientDevice = ble.createGattClientDevice(device);
      try {
        name = await gatt.getDeviceName();
      } catch (e) {
        BleUtils.log(hilog.LogLevel.ERROR, 'getBondedDevices getDeviceName: ' + (e as BusinessError)?.message);
      } finally {
        try {
          gatt.close();
        } catch (e) {
          BleUtils.log(hilog.LogLevel.ERROR, 'getBondedDevices gatt close: ' + (e as BusinessError)?.message);
        }
      }
      deviceList.add(BleUtils.buildBluetoothDevice(device, name));
    }
    let response: Map<string, object | string> = new Map<string, object | string>();
    response.set('devices', deviceList);
    result.success(response);
  }

  /**
   * 处理 getBondState：返回指定设备的配对状态。不访问连接状态字段。
   *
   * getPairState 在蓝牙关闭等场景下会抛异常，必须 try-catch 捕获后回传 result.error，
   * 否则会向上抛出导致 Dart 侧 Future 永久挂起（1.33.5 质量加固项）。
   * @param call - 方法调用，args 为 remoteId
   * @param result - 结果回调
   */
  getBondState(call: MethodCall, result: MethodResult): void {
    let remoteId: string = call.args as string;
    let res: connection.BondState;
    try {
      res = connection.getPairState(remoteId);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'getBondState getPairState: ' + (e as BusinessError)?.message);
      result.error('getBondState', 'getPairState failed: ' + ((e as BusinessError)?.message ?? ''), null);
      return;
    }
    let response: Map<string, string | number | null> = new Map();
    response.set('remote_id', remoteId);
    response.set('bond_state', BleUtils.buildBondStateEnum(res));
    response.set('prev_state', null);
    result.success(response);
  }

  /**
   * 处理 createBond：对已连接设备发起配对，已配对/配对中则直接返回。
   *
   * 需读取已连接设备 GattClientDevice 发起配对，经 plugin.connectionManager.connectedDevices
   * 反向查询（跨 Manager 唯一锚点）。pairDevice 异常返回 error。
   * getPairState 同样 try-catch（蓝牙关闭时会抛）。
   * @param call - 方法调用，args 为 remoteId
   * @param result - 结果回调
   */
  createBond(call: MethodCall, result: MethodResult): void {
    let remoteId: string = call.args as string;
    let gatt: ble.GattClientDevice | undefined = this.plugin.connectionManager.connectedDevices.get(remoteId);
    if (gatt === null || gatt === undefined) {
      BleUtils.log(hilog.LogLevel.ERROR, 'device is disconnected');
      result.error('createBond', 'device is disconnected', null);
      return;
    }
    let res: connection.BondState;
    try {
      res = connection.getPairState(remoteId);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'createBond getPairState: ' + (e as BusinessError)?.message);
      result.error('createBond', 'getPairState failed: ' + ((e as BusinessError)?.message ?? ''), null);
      return;
    }
    // already bonded?
    if (res === connection.BondState.BOND_STATE_BONDED) {
      result.success(false); // no work to do;
      return;
    }
    // bonding already in progress?
    if (res === connection.BondState.BOND_STATE_BONDING) {
      result.success(true); // caller must wait for bond completion;
      return;
    }
    try {
      connection.pairDevice(remoteId);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'device.createBond() returned false');
      result.error('createBond', 'device.createBond() returned false', null);
      return;
    }
    result.success(true);
  }

  /**
   * 读取加密/授权特征失败（2901006/2901007）时，主动发起配对并等待完成，供 read 重试前调用。
   *
   * 背景：OHOS 对加密/授权特征读取会报 2901006（未认证）/ 2901007（加密不足），需先配对加密链路。
   * 参照 2.1.0 FlutterBluePlusOhosPlugin.readCharacteristic 的认证错误容错（pairDevice → 重试）。
   * 与 2.1.0 的差异：2.1.0 pairDevice 后仅单次 getPairState 检查，配对是异步的，极易取到 BONDING
   * 误判为失败；此处复用 connectionManager.waitIfBonding 轮询 bondingDevices 至配对完成，再以
   * getPairState 终判，更稳且退化安全（未 BONDED 则返回 false，调用方不重试、报原错，不会误读）。
   *
   * 跨 Manager：waitIfBonding 在 connectionManager，经 plugin.connectionManager 反向调用。
   * @param remoteId - 设备远程标识
   * @returns true 表示已 BOND_STATE_BONDED 可重试读取；false 表示未配对/配对失败/超时。
   */
  async ensureBondedForRetry(remoteId: string): Promise<boolean> {
    // 已配对：无需再配，直接放行重试。
    try {
      if (connection.getPairState(remoteId) === connection.BondState.BOND_STATE_BONDED) {
        return true;
      }
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'ensureBondedForRetry pre getPairState: ' + (e as BusinessError)?.message);
      return false;
    }
    // 主动发起配对（pairDevice 异步触发 bondStateChange，bondingDevices 在 BONDING 态被填充）。
    try {
      connection.pairDevice(remoteId);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'ensureBondedForRetry pairDevice: ' + (e as BusinessError)?.message);
      return false;
    }
    // 等待配对完成：轮询 bondingDevices，BONDED 事件清空后退出（默认至多 3000ms）。
    await this.plugin.connectionManager.waitIfBonding();
    // 终判：是否真正 BONDED（waitIfBonding 超时早退时此处取到非 BONDED，安全退化为不重试）。
    try {
      return connection.getPairState(remoteId) === connection.BondState.BOND_STATE_BONDED;
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'ensureBondedForRetry final getPairState: ' + (e as BusinessError)?.message);
      return false;
    }
  }

  /**
   * 处理 removeBond：取消设备配对（解绑）。
   *
   * 平台限制（经核实）：鸿蒙 @ohos.bluetooth.connection 模块仅暴露 pairDevice()
   * 用于发起配对，未提供任何取消配对/解绑的公开 API（unpairDevice/cancelPair/
   * removeBond 均不存在，已对照 OpenHarmony API 21 connection.d.ts 确认）。
   * 该模块为鸿蒙蓝牙框架的逆向能力缺失，无替代实现路径，判定为平台限制而非适配缺陷。
   *
   * 实现策略：
   *  - 设备已是未配对态（BOND_STATE_INVALID）：直接返回 false（无变更，与 Android 行为一致，
   *    Dart 侧 removeBond 据此跳过等待 OnBondStateChanged）。
   *  - 设备已配对/配对中：同样返回 false（平台不支持代码取消配对）。Dart 侧 removeBond Future
   *    正常完成而非抛 PlatformException。若未来 SDK 暴露解绑 API，在此补充调用即可。
   *
   * getPairState 同样 try-catch（蓝牙关闭时会抛）。
   * @param call - 方法调用，args 为 remoteId
   * @param result - 结果回调
   */
  removeBond(call: MethodCall, result: MethodResult): void {
    let remoteId: string = call.args as string;
    let res: connection.BondState;
    try {
      res = connection.getPairState(remoteId);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'removeBond getPairState: ' + (e as BusinessError)?.message);
      result.error('removeBond', 'getPairState failed: ' + ((e as BusinessError)?.message ?? ''), null);
      return;
    }
    // already unbonded?
    if (res === connection.BondState.BOND_STATE_INVALID) {
      result.success(false); // no work to do;
      return;
    }
    BleUtils.log(hilog.LogLevel.WARN, 'removeBond: OHOS has no unpair API (platform limitation), returning false');
    result.success(false);
  }
}
