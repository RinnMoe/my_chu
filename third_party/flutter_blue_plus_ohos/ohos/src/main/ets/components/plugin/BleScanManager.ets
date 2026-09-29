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
import BleDevice from './BleDevice';
import HexUtil from './HexUtil';
import BleUtils from './BleUtils';
import BleAdvParser, { AdvData } from './BleAdvParser';
import BleScanFilterBuilder, { ScanArgsValue } from './BleScanFilterBuilder';
import FlutterBluePlusOhosPlugin from './FlutterBluePlusOhosPlugin';

/** 扫描过滤参数(由 Dart BmStartScanArgs 收窄得到,供 scanCallback 类型安全访问)。 */
interface ScanFilterParams {
  // 是否对同一设备持续上报(为 false 时仅上报首次去重后的广播)。
  continuousUpdates: boolean;
  // 持续上报时的分频因子(每第 N 个回调才上报一次)。
  continuousDivisor: number;
  // 设备名关键词过滤列表,设备名不含任一关键词则跳过。
  withKeywords: List<string>;
}

/**
 * OnScanResponse 单设备广告 Map 的异构值类型(BmScanAdvertisement)。
 * 使用联合类型而非 object,使 set('rssi', number)/set('platform_name', string) 等赋值合法
 * (ArkTS 严格模式下原始类型不能赋给 object)。
 */
type ScanAdvValue = string | number | boolean | string[] | Map<number, string> | Map<string, string>;

/**
 * BLE 扫描管理器。
 *
 * 集中管理 BLE 扫描的启动/停止、扫描结果去重与关键词过滤,以及 onScanResult 回调
 * (成员属性箭头函数,保证 ble.on/off 传引用时 this 不丢失)。持有已见广播去重缓存
 * (advSeen) 与每设备扫描计数 (scanCounts),上限由 MAX_SCAN_CACHE 限制,避免高频扫描下
 * 缓存无限增长。
 *
 * 方法体来源:1.33.5 FlutterBluePlusOhosPlugin(handleStartScan/handleStopScan/scanCallback/
 * resetScanFilters),适配 this.X → this.plugin.X:
 *  - this.scanCallbackRef → onScanResult 箭头字段
 *  - this.scanManager.advSeen/scanCounts → this.advSeen/scanCounts(本管理器自有)
 *  - this.parser.* → BleUtils.* / BleAdvParser.*
 *  - this.scanFilters → 本管理器 scanFilters 字段
 *  - this.log → BleUtils.log
 *  - this.channel → this.plugin.channel
 *  - this.ensurePermissions → this.plugin.permissionManager.ensurePermissions
 * 跨 Manager 共享状态经 plugin 中介访问(权限/channel)。
 */
export default class BleScanManager {
  // 扫描缓存上限,避免高频扫描下无限增长。
  public static readonly MAX_SCAN_CACHE: number = 500;
  /** 插件引用,用于访问 isDetached/channel/permissionManager 等共享状态。 */
  private plugin: FlutterBluePlusOhosPlugin;

  /** 是否正在扫描(由 stopScan/cleanup 复位)。 */
  public isScanning: boolean = false;
  /** 已见广播去重缓存(设备 MAC -> 广播十六进制)。 */
  public advSeen: Map<string, string> = new Map<string, string>();
  /** 每设备扫描计数(用于 continuousUpdates 分频)。 */
  public scanCounts: Map<string, number> = new Map<string, number>();
  /**
   * 每设备已解析设备名缓存(MAC -> 名称)。
   * 防止同一设备不同扫描回调间名称闪烁：设备名仅在 Scan Response 中时,前几次回调
   * deviceName 为空,一旦某个回调解析出非空名称即缓存,后续回调稳定复用,不再回退到 MAC。
   */
  public nameSeenMap: Map<string, string> = new Map<string, string>();
  /** 当前扫描过滤参数(来自 Dart 端 BmStartScanArgs)。 */
  public scanFilters: ScanFilterParams = {
    continuousUpdates: false,
    continuousDivisor: 1,
    withKeywords: new List<string>(),
  };

  /**
   * 构造扫描管理器。
   * @param plugin - 宿主插件引用
   */
  constructor(plugin: FlutterBluePlusOhosPlugin) {
    this.plugin = plugin;
  }

  /**
   * ble.on('BLEDeviceFind') 回调:保持成员属性箭头函数形式,
   * 保证 ble.on/off 传引用时 this 不丢失。引擎分离后直接返回。
   */
  public onScanResult = async (data: ble.ScanResult[]) => {
    if (this.plugin.isDetached) {
      return;
    }
    await this.scanCallback(data);
  };

  /**
   * 处理 startScan:解析过滤参数、申请权限、校验适配器状态、注册扫描回调并启动 BLE 扫描。
   * android_scan_mode 映射到鸿蒙 ScanDuty(lowLatency/balanced/lowPower)。
   * 异常路径必须回传 result.error,否则 Dart 侧 Future 将永久挂起。
   * @param call 方法调用,含 with_services/with_remote_ids/with_names/with_msd/
   *             with_service_data/with_keywords/continuous_updates/continuous_divisor/
   *             android_scan_mode 等过滤参数。
   * @param result 结果回调,用于向 Flutter 返回成功或错误。
   */
  async startScan(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      let data: Map<string, ScanArgsValue> = call.args as Map<string, ScanArgsValue>;
      if (data === null || data === undefined) {
        result.error('startScan', 'args is null', null);
        return;
      }
      if (!await this.plugin.permissionManager.ensurePermissions(result, 'startScan')) {
        return;
      }
      if (!BleUtils.isAdapterOn()) {
        BleUtils.log(hilog.LogLevel.ERROR, 'bluetooth must be turned on');
        result.error('startScan', 'bluetooth must be turned on', null);
        return;
      }
      let filterArray: ble.ScanFilter[] = BleScanFilterBuilder.buildScanFilters(data);
      let scanOption: ble.ScanOptions = this.buildScanOption((data.get('android_scan_mode') as number) ?? 0);
      // 注册扫描回调:失败时已 result.error 并返回 false。
      if (!this.registerScanCallback(result)) {
        return;
      }
      this.parseAndApplyScanFilters(data);
      this.startBLEScanWithFilters(filterArray, scanOption);
      this.isScanning = true;
    } catch (err) {
      BleUtils.log(hilog.LogLevel.ERROR, 'startScan error: ' + (err as BusinessError)?.message);
      // 异常必须回传 Flutter 并提前返回,否则扫描失败仍返回成功,Dart 侧会无限等待。
      this.isScanning = false;
      result.error('startScan', (err as BusinessError)?.message ?? 'scan failed', null);
      return;
    }
    result.success(true);
  }

  /**
   * 根据 Dart 传入的 android_scan_mode 映射到鸿蒙扫描占空比,构造 ScanOptions。
   * lowLatency(2)->低延迟, balanced(1)->均衡, lowPower(0)/其他->低功耗。
   */
  private buildScanOption(androidScanMode: number): ble.ScanOptions {
    let duty: ble.ScanDuty = ble.ScanDuty.SCAN_MODE_LOW_POWER;
    if (androidScanMode === 2) {
      duty = ble.ScanDuty.SCAN_MODE_LOW_LATENCY;
    } else if (androidScanMode === 1) {
      duty = ble.ScanDuty.SCAN_MODE_BALANCED;
    }
    return {
      dutyMode: duty,
      matchMode: ble.MatchMode.MATCH_MODE_AGGRESSIVE,
      interval: 0,
    };
  }

  /**
   * 注册 BLEDeviceFind 扫描回调(off 旧→on 新,同一引用避免累积)。
   * 注册失败时 result.error 并返回 false;成功返回 true。
   */
  private registerScanCallback(result: MethodResult): boolean {
    try {
      ble.off('BLEDeviceFind', this.onScanResult);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'startScan off BLEDeviceFind: ' + (e as BusinessError)?.message);
    }
    try {
      ble.on('BLEDeviceFind', this.onScanResult);
    } catch (e) {
      // 注册失败必须回传错误并提前返回,否则扫描失败仍返回成功,Dart 侧会无限等待。
      BleUtils.log(hilog.LogLevel.ERROR, 'startScan on BLEDeviceFind: ' + (e as BusinessError)?.message);
      this.isScanning = false;
      result.error('startScan', 'register BLEDeviceFind listener failed: ' + (e as BusinessError)?.message, null);
      return false;
    }
    return true;
  }

  /**
   * 从平台通道 Map 收窄为强类型 ScanFilterParams(供 scanCallback 类型安全访问),
   * 清空去重/计数缓存。可选过滤项未传时给默认值,避免 scanCallback 访问 undefined。
   */
  private parseAndApplyScanFilters(data: Map<string, ScanArgsValue>): void {
    let keywordsRaw: List<string> = data.get('with_keywords') as List<string>;
    let divisorRaw: number = data.get('continuous_divisor') as number;
    this.scanFilters = {
      continuousUpdates: data.get('continuous_updates') as boolean,
      continuousDivisor: divisorRaw !== undefined && divisorRaw !== null && divisorRaw > 0 ? divisorRaw : 1,
      withKeywords: keywordsRaw !== undefined && keywordsRaw !== null ? keywordsRaw : new List<string>(),
    };
    this.advSeen.clear();
    this.scanCounts.clear();
    this.nameSeenMap.clear();
  }

  /**
   * 按过滤条件启动 BLE 扫描:无过滤条件时传 null 表示不过滤(OHOS ble.startBLEScan 的 napi 层
   * 要求 filter 数组长度 > 0,传空数组 [] 会触发 "Requires array length > 0" 断言并抛 401,
   * 故无过滤时必须传 null 而非 []),扫描全部设备。
   */
  private startBLEScanWithFilters(filterArray: ble.ScanFilter[], scanOption: ble.ScanOptions): void {
    if (filterArray.length === 0) {
      ble.startBLEScan(null, scanOption);
    } else {
      ble.startBLEScan(filterArray, scanOption);
    }
  }

  /**
   * 处理 stopScan:停止 BLE 扫描、注销回调并清理扫描状态与过滤参数。
   * @param result 结果回调,用于向 Flutter 返回成功。
   */
  async stopScan(result: MethodResult): Promise<void> {
    try {
      ble.stopBLEScan();
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'stopScan stopBLEScan: ' + (e as BusinessError)?.message);
    }
    // 用注册时保存的同一引用 off,才能真正取消监听。
    try {
      ble.off('BLEDeviceFind', this.onScanResult);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'stopScan off BLEDeviceFind: ' + (e as BusinessError)?.message);
    }
    this.isScanning = false;
    // 扫描停止后过滤器数据已无用,清理避免残留。
    this.resetScanFilters();
    result.success(true);
  }

  /**
   * 将扫描过滤参数重置为默认值(非连续上报、分频 1、空关键词列表)。
   * ScanFilterParams 不是 Map,无法 clear,故用重置默认对象替代,清理上轮扫描残留参数。
   */
  resetScanFilters(): void {
    this.scanFilters = {
      continuousUpdates: false,
      continuousDivisor: 1,
      withKeywords: new List<string>(),
    };
    // 停止扫描时清空本轮全部扫描缓存（去重/计数/设备名），与 startScan 的
    // parseAndApplyScanFilters 对齐：扫描已停止，缓存随即失效，立即释放而非等下次 startScan。
    this.advSeen.clear();
    this.scanCounts.clear();
    this.nameSeenMap.clear();
  }

  /**
   * 根据 with_services/with_remote_ids/with_names/with_msd/with_service_data 各维度
   * 构造 ble.ScanFilter 数组。已迁移至 {@link BleScanFilterBuilder}(纯构建逻辑,无实例状态)。
   */

  /**
   * 处理 BLE 扫描结果:解析厂商数据,通过短生命周期的 GATT 客户端解析设备名
   * (在 finally 中关闭以避免每次回调泄漏),按当前扫描选项应用关键字/去重/分频过滤,
   * 并发出 OnScanResponse。去重与每设备计数缓存由 MAX_SCAN_CACHE 限制上限,
   * 避免高频扫描下无限增长。
   *
   * 响应字段集与 1.33.5 Dart 层契约保持一致(manufacturer_data 为 Map<number,string>
   * 十六进制,不含 tx_power_level/appearance/service_uuids/service_data 等扩展字段)。
   * @param data BLE 栈交付的扫描结果。
   */
  async scanCallback(data: ble.ScanResult[]): Promise<void> {
    // 空数组防护:data[0] 访问越界会抛异常,先校验。整体异常保护:回调无法向 Flutter 回传错误,
    // 异常会导致扫描结果静默丢失。
    if (data === null || data === undefined || data.length === 0) {
      return;
    }
    // 引擎已分离则短路退出,避免在 onScanResult 入口检查之后、此处仍创建临时 GattClientDevice
    // (getDeviceName) 浪费系统资源 —— onScanResult 入口的 isDetached 检查无法保证到达此处时
    // 引擎仍未分离(回调间存在异步窗口)。
    if (this.plugin.isDetached) {
      return;
    }
    try {
      let item: ble.ScanResult = data[0];
      // 解析厂商数据为十六进制 Map(键=manufacturer_id,值=十六进制字符串)。
      let manufDataB: Map<number, string> = this.parseManufacturerData(new Uint8Array(item.data));
      // 解码成 BleDevice。
      let device: BleDevice =
        new BleDevice(item.deviceId, '', item.rssi, new Uint8Array(item.data), new Date().getTime(),
          item.connectable);
      let remoteId: string = device.getMac();
      let scanRecord: Uint8Array = device.getScanRecord();
      let advHex: string = HexUtil.formatHexString(scanRecord);
      // 非连续模式:按 remoteId+advHex 去重,同一设备同一广播仅上报首次。
      if (this.scanFilters.continuousUpdates === false) {
        if (this.isDuplicateAdv(remoteId, advHex)) {
          return;
        }
      }
      // 设备名解析:优先使用 OHOS 栈已解析的 ScanResult.deviceName(含 Scan Response 名称),
      // 其次回退到广播 AD type 0x08/0x09 解析的 localName,再回退 nameSeenMap 缓存。
      // Scan Response 中的名称不在 item.data 中,但 OHOS 栈会合并到 deviceName 字段;
      // 设备名仅在 Scan Response 中时,前几次回调 deviceName 为空,缓存命中后稳定显示名称,
      // 避免同一设备名称/MAC 交替闪烁。不创建临时 GATT 客户端读取名称——高频扫描下会
      // 耗尽系统 BLE 资源并干扰正常连接。
      let advData: AdvData = BleAdvParser.parseAdvHexData(advHex);
      let deviceName: string = item.deviceName || '';
      if (deviceName === '') {
        deviceName = advData.localName || '';
      }
      if (deviceName !== '') {
        this.nameSeenMap.set(remoteId, deviceName);
      } else {
        let cached: string | undefined = this.nameSeenMap.get(remoteId);
        if (cached !== null && cached !== undefined) {
          deviceName = cached;
        }
      }
      if (deviceName !== '') {
        device.setName(deviceName);
      }
      // 关键词/分频过滤:任一不满足则丢弃本次。
      let name: string = device.getName() !== null ? device.getName() : '';
      if (!this.applyScanFilters(name, remoteId)) {
        return;
      }
      // 组装 OnScanResponse 并回传(字段集与 1.33.5 Dart 层契约一致)。
      this.buildScanResponseMap(device, manufDataB, advData);
    } catch (e) {
      BleUtils.log(hilog.LogLevel.ERROR, 'scanCallback error: ' + (e as BusinessError)?.message);
    }
  }

  /**
   * 解析广播报文中的厂商数据,返回 manufacturer_id -> 十六进制字符串 的 Map。
   * 1.33.5 契约:manufacturer_data 为 Map<number,string>,值为 bytesToHexScan 编码结果。
   * @param uint8Msg 广播原始字节。
   * @returns 厂商数据 Map(无厂商数据时为空 Map)。
   */
  private parseManufacturerData(uint8Msg: Uint8Array): Map<number, string> {
    let manufData: Map<number, Uint8Array> = BleAdvParser.getManufacturerSpecificData(uint8Msg);
    let manufDataB: Map<number, string> = new Map<number, string>();
    if (manufData !== null && manufData !== undefined) {
      manufData.forEach((value: Uint8Array, key: number) => {
        manufDataB.set(key, BleUtils.bytesToHexScan(value));
      });
    }
    return manufDataB;
  }

  /**
   * 非连续模式的去重判定:按 remoteId+advHex 检测重复,同时更新 advSeen 缓存并在超限时裁剪。
   * @param remoteId 设备 MAC。
   * @param advHex 本次广播十六进制。
   * @returns true 表示重复(调用方应 return 跳过),false 表示首次/变化应继续上报。
   */
  private isDuplicateAdv(remoteId: string, advHex: string): boolean {
    let prevAdv: string | undefined = this.advSeen.get(remoteId);
    let isDuplicate: boolean = this.advSeen.has(remoteId) && prevAdv === advHex;
    this.advSeen.set(remoteId, advHex);
    // 缓存上限,避免高频扫描下无限增长。
    if (this.advSeen.size > BleScanManager.MAX_SCAN_CACHE) {
      this.trimAdvSeen();
    }
    return isDuplicate;
  }

  /**
   * 应用扫描过滤:关键词过滤(设备名不含任一关键词则丢弃)+ 连续模式分频(divisor 除数降频)。
   * @param name 设备名(用于关键词匹配,空字符串等价于 device.getName() 为 null)。
   * @param remoteId 设备 MAC(用于扫描计数分频)。
   * @returns true 表示通过过滤应继续上报,false 表示被过滤掉(调用方应 return)。
   */
  private applyScanFilters(name: string, remoteId: string): boolean {
    // 关键词过滤:设备名不含任一关键词则丢弃。
    let keywords: List<string> = this.scanFilters.withKeywords;
    if (this.filterKeywords(keywords, name) === false) {
      return false;
    }
    // 连续模式:按 divisor 除数降频,仅 count 整除 divisor 时上报,否则丢弃本次。
    if (this.scanFilters.continuousUpdates !== false) {
      let count: number = this.scanCountIncrement(remoteId);
      // 计数缓存上限。
      if (this.scanCounts.size > BleScanManager.MAX_SCAN_CACHE) {
        this.trimScanCounts();
      }
      let divisor: number = this.scanFilters.continuousDivisor;
      if ((count % divisor) !== 0) {
        return false;
      }
    }
    return true;
  }

  /**
   * 组装 OnScanResponse 并通过 channel 回传。字段集与 1.33.5 Dart 层契约一致
   * (manufacturer_data 为 Map<number,string> 十六进制,adv_name/tx_power_level/appearance/
   * service_uuids/service_data 由广播解析)。
   * @param device 已填充设备名/可连接标志/RSSI 的 BleDevice。
   * @param manufDataB 厂商数据 Map(十六进制字符串)。
   * @param advData 已解析的广播数据(scanCallback 中解析并用于取名,避免重复解析)。
   */
  private buildScanResponseMap(device: BleDevice, manufDataB: Map<number, string>, advData: AdvData): void {
    let deviceList: List<Map<string, ScanAdvValue>> = new List<Map<string, ScanAdvValue>>();
    let map: Map<string, ScanAdvValue> = new Map<string, ScanAdvValue>();
    let response: Map<string, object> = new Map<string, object>();
    map.set('manufacturer_data', manufDataB);
    if (device.getName() !== null) {
      map.set('platform_name', device.getName());
    } else {
      map.set('platform_name', '');
    }
    if (device.getMac() !== null) {
      map.set('remote_id', device.getMac());
    }
    if (device.getConnectable()) {
      map.set('connectable', device.getConnectable());
    }
    // RSSI 0 dBm 是合法信号强度(设备贴近时常见),不能按 !==0 过滤;仅 null/undefined 不上报。
    let rssi: number | null = device.getRssi();
    if (rssi !== null && rssi !== undefined) {
      map.set('rssi', rssi);
    }
    // 广播字段（adv_name / tx_power_level / appearance / service_uuids / service_data）。
    if (advData.localName !== null && advData.localName !== undefined) {
      map.set('adv_name', advData.localName);
    }
    if (advData.txPowerLevel !== null && advData.txPowerLevel !== undefined) {
      map.set('tx_power_level', advData.txPowerLevel);
    }
    if (advData.appearance !== null && advData.appearance !== undefined) {
      map.set('appearance', advData.appearance);
    }
    if (advData.serviceUUIDs !== null && advData.serviceUUIDs !== undefined && advData.serviceUUIDs.length > 0) {
      map.set('service_uuids', advData.serviceUUIDs);
    }
    if (advData.serviceData !== null && advData.serviceData !== undefined && advData.serviceData.size > 0) {
      map.set('service_data', advData.serviceData);
    }
    deviceList.add(map);
    response.set('advertisements', deviceList);
    if (this.plugin.channel !== null && this.plugin.channel !== undefined) {
      this.plugin.channel.invokeMethod('OnScanResponse', response);
    }
  }

  /**
   * 自增并返回每设备扫描结果计数器,供连续更新分频过滤使用。
   * @param remoteId 远端设备 MAC 地址。
   * @returns 自增前的计数值(从 0 起)。
   */
  scanCountIncrement(remoteId: string): number {
    // Map.get() 对缺失键返回 undefined(非 null),用 has() 判断更准确,避免初始化逻辑永不执行。
    if (!this.scanCounts.has(remoteId)) {
      this.scanCounts.set(remoteId, 0);
    }
    let count: number = this.scanCounts.get(remoteId) as number;
    this.scanCounts.set(remoteId, count + 1);
    return count;
  }

  /**
   * 当已见广播缓存超过上限时,删除前一半条目,避免高频扫描下无限增长。
   */
  trimAdvSeen(): void {
    if (this.advSeen.size <= BleScanManager.MAX_SCAN_CACHE) {
      return;
    }
    let keys: string[] = [];
    this.advSeen.forEach((_: string, key: string) => {
      keys.push(key);
    });
    let toRemove: number = Math.floor(keys.length / 2);
    for (let i = 0; i < toRemove; i++) {
      this.advSeen.delete(keys[i]);
    }
  }

  /**
   * 当扫描计数缓存超过上限时,删除前一半条目,避免高频扫描下无限增长。
   */
  trimScanCounts(): void {
    if (this.scanCounts.size <= BleScanManager.MAX_SCAN_CACHE) {
      return;
    }
    let keys: string[] = [];
    this.scanCounts.forEach((_: number, key: string) => {
      keys.push(key);
    });
    let toRemove: number = Math.floor(keys.length / 2);
    for (let i = 0; i < toRemove; i++) {
      this.scanCounts.delete(keys[i]);
    }
  }

  /**
   * 关键词过滤:任一关键词被设备名包含即通过;关键词列表为空/null 时无条件通过。
   * @param keywords 关键词列表。
   * @param target 设备名。
   * @returns 是否通过过滤。
   */
  filterKeywords(keywords: List<string>, target: string): boolean {
    // 先判 null 再访问 length:keywords 为 null/undefined(Dart 未传 withKeywords)时直接放行,
    // 否则 ArkTS 严格模式下访问 undefined.length 会抛异常。
    if (keywords === null || keywords === undefined || keywords.length === 0) {
      return true;
    }
    if (target === null || target === undefined) {
      return false;
    }
    for (let i = 0; i < keywords.length; i++) {
      if (target.includes(keywords[i])) {
        return true;
      }
    }
    return false;
  }
}
