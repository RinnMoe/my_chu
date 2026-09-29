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
import { hilog } from '@kit.PerformanceAnalysisKit';
import BleUtils from './BleUtils';

/**
 * GATT 共享缓存层。
 *
 * 集中持有跨功能组共享的 5 个缓存 Map 及按设备串行锁，供 BleGattManager(facade)/
 * BleCharacteristicManager/BleDescriptorManager/BleNotifyManager/BleMtuManager 经
 * plugin.gattCache 统一访问，使各业务 Manager 可独立拆分而无需互相持有引用。
 *
 * 提供聚合清理接口 clearForDevice / clearAll，供 BleConnectionManager 在断开/清理时调用，
 * 避免连接侧穿透到 5 个 Map 逐个操作。
 *
 * 字段语义：
 *  - mtuMap：deviceId → MTU（BleMtuManager 写、getMaxPayload/writeDescriptor 读）。
 *  - writeChrMap：写特征缓存值（key=remoteId:psu:su:cu:instanceId），Characteristic 组独占。
 *  - writeDescMap：写描述符缓存值（key=remoteId:psu:su:cu:instanceId:du）。Notify 组与 Descriptor 组共享。
 *  - deviceServicesMap：deviceId → 已发现服务树（Notify 回调懒加载、readCharacteristic 刷新）。
 *  - gattLockMap：deviceId → 当前正在执行的 GATT 操作 Promise（按设备串行锁，见 runGatt）。
 */
export default class GattCacheHolder {
  /** 每个设备的 MTU（默认 23）。 */
  public mtuMap: Map<string, number> = new Map();
  /** 待写入特征的缓存值（key=remoteId:psu:su:cu:instanceId），用于回传写入数据。 */
  public writeChrMap: Map<string, Uint8Array> = new Map();
  /** 待写入描述符的缓存值（key=remoteId:psu:su:cu:instanceId:du）。 */
  public writeDescMap: Map<string, Uint8Array> = new Map();
  /** 每个设备已发现的服务缓存，onCharacteristicChange 时按 deviceId 取用。 */
  public deviceServicesMap: Map<string, ble.GattService[]> = new Map();
  /**
   * 每个设备的 GATT 操作串行锁（deviceId → 当前正在执行的 Promise）。
   *
   * OHOS BLE 栈同一设备的 GATT 操作不支持并发，并发时返回 2900011 "The operation is busy"。
   * 此锁通过 Promise 链实现按设备串行化：新操作 await 前一个操作的 Promise，
   * 不同设备的操作互不阻塞。
   */
  public gattLockMap: Map<string, Promise<void>> = new Map();

  /**
   * 清理指定设备的缓存：mtuMap + deviceServicesMap。
   *
   * writeChrMap/writeDescMap 的 key 为复合前缀（含 UUID/instanceId），无法按 deviceId 精确删除，
   * 故仅在 clearAll 全量清理；单设备断开时这两个写入缓存残留无害（下次写入会覆盖，且断开后不再回传）。
   *
   * 不删除 gattLockMap：若此时有 GATT 操作正在排队等待（已 await prev 但未完成），
   * 删除条目会导致后续新操作的 runGatt 找不到前一个 Promise 而立即执行，造成并发。
   * gattLockMap 的清理由 runGatt 的 finally 尾部自清理完成（仅当本条目仍是链头 next 时
   * 删除）；单设备断开后最后一个操作完成即自动移除条目，不会随不同设备累积而泄漏。
   * @param remoteId - 设备 ID
   */
  clearForDevice(remoteId: string): void {
    this.mtuMap.delete(remoteId);
    this.deviceServicesMap.delete(remoteId);
  }

  /** 清空全部缓存。disconnectAllDevices / cleanup 全量清理时调用。 */
  clearAll(): void {
    this.mtuMap.clear();
    this.writeChrMap.clear();
    this.writeDescMap.clear();
    this.deviceServicesMap.clear();
    this.gattLockMap.clear();
  }

  /**
   * 按设备串行执行 GATT 操作：等前一个操作完成后再执行本次。
   * 不同设备的操作互不阻塞。
   *
   * 实现方式：每个设备维护一个 Promise 链，新操作 await 前一个操作的 Promise，
   * 完成后 resolve 当前 Promise，使后续操作可以继续。
   *
   * 异常隔离契约：try/finally 保证 resolve() 必被调用（串行链永不因 op 异常而中断），
   * 但 op() 内部抛出的未捕获异常会向调用方传播——此时 result 不会被回传，Dart 侧 Future
   * 将挂起直至超时。故 op() 必须自行 try/catch 所有可能抛错的路径（如 getServices/
   * readCharacteristicValue/writeDescriptorValue），在 catch 中 result.error() + return，
   * 不得依赖 runGatt 兜底回传错误。
   *
   * @param remoteId - 设备 ID
   * @param op - 待执行的异步操作（含 result 回调）
   * @returns op 的返回值
   */
  async runGatt<T>(remoteId: string, op: () => Promise<T>): Promise<T> {
    let prev: Promise<void> = this.gattLockMap.get(remoteId) ?? Promise.resolve();
    let resolve: () => void = () => {};
    let next: Promise<void> = new Promise<void>(r => { resolve = r; });
    this.gattLockMap.set(remoteId, next);
    BleUtils.log(hilog.LogLevel.DEBUG, `runGatt: queuing GATT op for ${remoteId}`);
    await prev;
    BleUtils.log(hilog.LogLevel.DEBUG, `runGatt: starting GATT op for ${remoteId}`);
    try {
      return await op();
    } finally {
      resolve();
      // 尾部自清理：若本操作的 next 仍是链头（无后续操作覆盖），删除条目，避免
      // gattLockMap 随不同设备连接/断开而无限增长（clearForDevice 不删 gattLockMap，
      // 单设备断开后条目仅能靠此处清理）。仅当 gattLockMap.get(remoteId) === next 时删除——
      // 若已被后续操作覆盖为更新的 Promise，说明仍有排队操作，删除会导致其 runGatt 拿不到
      // 前驱而并发执行（JS 单线程，resolve() 与本 get/delete 间无 await，原子安全）。
      if (this.gattLockMap.get(remoteId) === next) {
        this.gattLockMap.delete(remoteId);
      }
      BleUtils.log(hilog.LogLevel.DEBUG, `runGatt: completed GATT op for ${remoteId}`);
    }
  }
}
