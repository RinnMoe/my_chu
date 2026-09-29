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

import { MethodResult } from '@ohos/flutter_ohos';
import { abilityAccessCtrl, bundleManager, Permissions, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BleUtils from './BleUtils';

/**
 * 蓝牙权限管理器。
 *
 * 封装 OHOS ACCESS_BLUETOOTH 权限的检测、申请与状态查询。
 * 在 Ability 附加时由 Plugin 注入 context；各业务 manager 调用
 * ensurePermissions 在执行 BLE 操作前完成权限校验与申请。
 * 自包含：仅依赖 context，不持有任何设备映射状态。
 */
export default class BlePermissionManager {
  /** 鸿蒙蓝牙访问权限名。 */
  public static readonly ACCESS_BLUETOOTH_PERMISSION: Permissions = 'ohos.permission.ACCESS_BLUETOOTH';

  /** Ability context，用于 requestPermissionsFromUser。由 Plugin 在 onAttachedToAbility 注入，onDetachedFromAbility 置 null。 */
  public context: common.Context | null = null;

  /**
   * 在执行特权操作前确保已授予 OHOS 蓝牙权限。拒绝或失败时用 error 解析 MethodResult
   * 并返回 false，使调用方可短路退出。
   * @param result 失败时待解析的 MethodResult。
   * @param errorCode 失败时报出的平台通道错误码。
   * @returns 操作可继续时返回 true。
   */
  async ensurePermissions(result: MethodResult, errorCode: string): Promise<boolean> {
    let checkPermissionStatus: boolean =
      await this.checkSelfPermission(BlePermissionManager.ACCESS_BLUETOOTH_PERMISSION);
    let permissionStatus: boolean = true;
    if (checkPermissionStatus) {
      let isPermission: boolean | string = await this.requestPermissions();
      if (typeof isPermission === 'boolean' && !(isPermission as boolean)) {
        // 权限被拒属错误而非"成功但无操作",统一用 result.error 让 Dart 侧走异常路径提示用户,
        // 与 isPermission===string(申请失败)的回传语义保持一致,避免调用方据 success(false) 误判为正常完成。
        let deniedMsg: string = 'FlutterBluePlus requires ohos.permission.ACCESS_BLUETOOTH, but it was denied';
        BleUtils.log(hilog.LogLevel.ERROR, deniedMsg);
        result.error(errorCode, deniedMsg, null);
        permissionStatus = false;
      } else if (typeof isPermission === 'string') {
        BleUtils.log(hilog.LogLevel.ERROR, isPermission as string);
        result.error(errorCode, isPermission as string, null);
        permissionStatus = false;
      }
    }
    return permissionStatus;
  }

  /**
   * 通过系统弹窗引导用户授予蓝牙权限。
   * @returns 授予返回 true；否则返回拒绝或失败的可读原因串（由调用方经 MethodResult 上报）。
   */
  async requestPermissions(): Promise<boolean | string> {
    let result: boolean | string = false;
    // context 在 onAttachedToAbility 绑定前可能为 null，缺失时无法唤起权限弹窗，直接返回失败。
    if (this.context === null || this.context === undefined) {
      result = 'FlutterBluePlus requires Ability context to request ohos.permission.ACCESS_BLUETOOTH';
      return result;
    }
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    // requestPermissionsFromUser 会判断权限的授权状态来决定是否唤起弹窗
    await atManager.requestPermissionsFromUser(this.context, [BlePermissionManager.ACCESS_BLUETOOTH_PERMISSION])
      .then((data) => {
        let grantStatus: number[] = data.authResults;
        if (grantStatus.length > 0 && grantStatus[0] === 0) {
          result = true;
        } else {
          // 用户拒绝授权，提示用户必须授权才能访问当前页面的功能，并引导用户到系统设置中打开相应的权限
          result = 'FlutterBluePlus requires ohos Permission ohos.permission.ACCESS_BLUETOOTH';
        }
      })
      .catch((err: BusinessError) => {
        result = `Failed to request permissions from user. Code is ${err.code}, message is ${err.message}`;
      });
    return result;
  }

  /**
   * 检查权限当前是否未授予。token 缺少该权限时返回 true（即调用方应去申请）。
   * @param permission 待检查的 OHOS 权限 token。
   * @returns 权限被拒（应申请）返回 true，已授予返回 false。
   */
  async checkSelfPermission(permission: Permissions): Promise<boolean> {
    let tokenId: number = 0;
    let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let bundleInfo: bundleManager.BundleInfo =
      await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    let appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
    tokenId = appInfo.accessTokenId;
    grantStatus = await atManager.checkAccessToken(tokenId, permission);
    return grantStatus === -1;
  }
}
