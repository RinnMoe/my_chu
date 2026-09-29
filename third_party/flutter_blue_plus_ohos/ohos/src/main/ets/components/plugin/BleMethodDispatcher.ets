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
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BleUtils from './BleUtils';
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/** 方法处理函数统一签名：(call, result) => Promise<void>。 */
type Handler = (call: MethodCall, result: MethodResult) => Promise<void>;

/**
 * MethodChannel 方法分发器。
 *
 * 用 Map<string, handler> 查找表替代 25 分支 switch：按 call.method 分发到对应 BLE 操作，
 * 降低圈复杂度并便于按方法定位逻辑。顶层 catch 捕获未处理异常并通过 result.error 上报，
 * 未知方法走 result.notImplemented()。handler 为无状态箭头函数闭包，首次构造后缓存复用。
 *
 * 分发去向：
 *  - 适配器/系统类（handle*）：委托宿主插件 FlutterBluePlusOhosPlugin 的同名 handle* 方法；
 *  - 连接/扫描/GATT/通知/MTU/特征值/描述符/绑定类：委托各 Manager 的对应方法。
 * 自身不持有业务状态，故可在插件构造后安全缓存。
 */
export default class BleMethodDispatcher {
  /** 宿主插件引用，用于访问各 Manager / channel / handle* 方法。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /** 方法名 -> 处理函数 的查找表（懒构造，handlers 无状态可安全缓存）。 */
  private methodHandlers: Map<string, (call: MethodCall, result: MethodResult) => Promise<void>> | null = null;

  /**
   * 构造分发器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * MethodChannel 方法分发入口：按 call.method 在查找表中分发到对应 BLE 操作。
   * 顶层 catch 捕获未处理异常并通过 result.error 上报；未知方法返回 notImplemented。
   * @param call - 方法调用，含方法名与参数
   * @param result - 结果回调，用于向 Flutter 端返回成功/错误
   */
  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      let handler: Handler | undefined = this.getMethodHandlers().get(call.method);
      if (handler !== null && handler !== undefined) {
        await handler(call, result);
      } else {
        result.notImplemented();
      }
    } catch (e) {
      let error: BusinessError = e as BusinessError;
      let msg: string = error?.message ?? `unknown error: ${JSON.stringify(e)}`;
      BleUtils.log(hilog.LogLevel.ERROR,
        `onMethodCall: unhandled exception for method='${call.method}', ` +
        `code=${error?.code}, msg=${msg}`);
      try {
        result.error(call.method, msg, null);
      } catch (resultErr) {
        // result 可能已被对应 case 处理过，忽略 double-response
      }
      return;
    }
  }

  /**
   * 构建并缓存 方法名 -> 处理函数 的查找表。
   * handlers 为无状态箭头函数闭包，首次构造后缓存到 methodHandlers，后续直接复用。
   * 所有 handler 统一为 async (call, result) => Promise<void>，保证 Map 类型一致。
   * @returns 方法名到处理函数的 Map
   */
  private getMethodHandlers(): Map<string, Handler> {
    if (this.methodHandlers !== null) {
      return this.methodHandlers;
    }
    let handlers: Map<string, Handler> = new Map<string, Handler>();
    this.registerAdapterHandlers(handlers);
    this.registerConnectionScanHandlers(handlers);
    this.registerGattHandlers(handlers);
    this.registerCharacteristicDescriptorHandlers(handlers);
    this.registerBondPlatformHandlers(handlers);
    this.methodHandlers = handlers;
    return handlers;
  }

  /** 注册适配器/系统类 handler(委托宿主插件 handle* 方法)。 */
  private registerAdapterHandlers(handlers: Map<string, Handler>): void {
    handlers.set('flutterRestart', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.handleFlutterRestart(call, result);
    });
    handlers.set('connectedCount', async (call: MethodCall, result: MethodResult) => {
      this.plugin.handleConnectedCount(call, result);
    });
    handlers.set('setOptions', async (call: MethodCall, result: MethodResult) => {
      this.plugin.handleSetOptions(call, result);
    });
    handlers.set('getAdapterState', async (call: MethodCall, result: MethodResult) => {
      this.plugin.handleGetAdapterState(call, result);
    });
    handlers.set('getAdapterName', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.handleGetAdapterName(call, result);
    });
    handlers.set('isSupported', async (call: MethodCall, result: MethodResult) => {
      this.plugin.handleIsSupported(call, result);
    });
    handlers.set('getSystemDevices', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.handleGetSystemDevices(call, result);
    });
    handlers.set('turnOn', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.handleTurnOn(call, result);
    });
    handlers.set('turnOff', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.handleTurnOff(call, result);
    });
    handlers.set('setLogLevel', async (call: MethodCall, result: MethodResult) => {
      this.plugin.handleSetLogLevel(call, result);
    });
    handlers.set('clearGattCache', async (call: MethodCall, result: MethodResult) => {
      this.plugin.handleClearGattCache(call, result);
    });
  }

  /** 注册连接/扫描 handler(委托 ConnectionManager / ScanManager)。 */
  private registerConnectionScanHandlers(handlers: Map<string, Handler>): void {
    handlers.set('connect', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.connectionManager.connect(call, result);
    });
    handlers.set('disconnect', async (call: MethodCall, result: MethodResult) => {
      this.plugin.connectionManager.disconnect(call, result);
    });
    handlers.set('startScan', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.scanManager.startScan(call, result);
    });
    handlers.set('stopScan', async (call: MethodCall, result: MethodResult) => {
      // ScanManager.stopScan 仅接收 result，此处包装为 (call, result) 形式以统一 Map 类型。
      this.plugin.scanManager.stopScan(result);
    });
  }

  /** 注册 GATT/通知/MTU handler(委托 GattManager / NotifyManager / MtuManager)。 */
  private registerGattHandlers(handlers: Map<string, Handler>): void {
    handlers.set('readRssi', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.gattManager.readRssi(call, result);
    });
    handlers.set('discoverServices', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.gattManager.discoverServices(call, result);
    });
    handlers.set('setNotifyValue', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.notifyManager.setNotifyValue(call, result);
    });
    handlers.set('requestMtu', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.mtuManager.requestMtu(call, result);
    });
  }

  /** 注册特征值/描述符 handler(委托 CharacteristicManager / DescriptorManager)。 */
  private registerCharacteristicDescriptorHandlers(handlers: Map<string, Handler>): void {
    handlers.set('readCharacteristic', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.characteristicManager.handleReadCharacteristic(call, result);
    });
    handlers.set('writeCharacteristic', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.characteristicManager.handleWriteCharacteristic(call, result);
    });
    handlers.set('readDescriptor', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.descriptorManager.readDescriptor(call, result);
    });
    handlers.set('writeDescriptor', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.descriptorManager.writeDescriptor(call, result);
    });
  }

  /** 注册绑定 handler(委托 BondManager) + 平台限制占位(PHY/连接优先级)。 */
  private registerBondPlatformHandlers(handlers: Map<string, Handler>): void {
    handlers.set('getBondedDevices', async (call: MethodCall, result: MethodResult) => {
      await this.plugin.bondManager.getBondedDevices(call, result);
    });
    handlers.set('getBondState', async (call: MethodCall, result: MethodResult) => {
      this.plugin.bondManager.getBondState(call, result);
    });
    handlers.set('createBond', async (call: MethodCall, result: MethodResult) => {
      this.plugin.bondManager.createBond(call, result);
    });
    handlers.set('removeBond', async (call: MethodCall, result: MethodResult) => {
      this.plugin.bondManager.removeBond(call, result);
    });
    // OHOS BLE 接口未暴露 PHY 支持 API，getPhySupport 返回错误以表明平台不支持。
    handlers.set('getPhySupport', async (call: MethodCall, result: MethodResult) => {
      result.error('getPhySupport', 'OHOS platform does not support PHY API', null);
    });
    // OHOS BLE 接口未暴露连接优先级/PHY 设置 API，与 getPhySupport 一致返回 error 表明平台不支持。
    // Dart 侧 requestConnectionPriority/setPreferredPhy 已由 isAndroid 守卫在 OHOS 抛 "android-only"，
    // 此处为防御性兜底：若被直接调用则如实返回 error，而非伪装 success(true) 误导调用方。
    handlers.set('requestConnectionPriority', async (call: MethodCall, result: MethodResult) => {
      result.error('requestConnectionPriority', 'OHOS platform does not support connection priority API', null);
    });
    handlers.set('setPreferredPhy', async (call: MethodCall, result: MethodResult) => {
      result.error('setPreferredPhy', 'OHOS platform does not support PHY API', null);
    });
  }
}
