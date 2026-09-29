/*
* Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
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

import { MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import ChannelResultUtil from '../types/ChannelResultUtil';
import PullToRefreshLayout from './PullToRefreshLayout';

const LOG_TAG = 'PullToRefreshChannelDelegate'

export default class PullToRefreshChannelDelegate extends ChannelDelegateImpl {
  private pullToRefreshView: PullToRefreshLayout | null;

  constructor(pullToRefreshView: PullToRefreshLayout, channel: MethodChannel) {
    super(channel);
    this.pullToRefreshView = pullToRefreshView;
  }

  public onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case "setEnabled":
          if (this.pullToRefreshView != null) {
            let enabled: boolean = call.argument("enabled") as boolean;
            this.pullToRefreshView.settings.enabled = enabled; // used by InAppWebView.onOverScrolled
            this.pullToRefreshView.setEnabled(enabled);
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case "isEnabled":
          if (this.pullToRefreshView != null) {
            result.success(this.pullToRefreshView.isEnabled());
          } else {
            result.success(false);
          }
          break;
        case "setRefreshing":
          if (this.pullToRefreshView != null) {
            let refreshing: boolean = call.argument("refreshing") as boolean;
            this.pullToRefreshView.setRefreshing(refreshing);
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case "isRefreshing":
          result.success(this.pullToRefreshView != null && this.pullToRefreshView.isRefreshing());
          break;
        case "setColor":
          if (this.pullToRefreshView != null) {
            let color: string = call.argument("color");
            this.pullToRefreshView.setColor(color);
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case "setBackgroundColor":
          if (this.pullToRefreshView != null) {
            let color: string = call.argument("color");
            this.pullToRefreshView.setBackgroundColor(color);
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case "setDistanceToTriggerSync":
          if (this.pullToRefreshView != null) {
            let distanceToTriggerSync: number = call.argument("distanceToTriggerSync");
            this.pullToRefreshView.setDistanceToTriggerSync(distanceToTriggerSync);
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case "setSlingshotDistance":
          if (this.pullToRefreshView != null) {
            let slingshotDistance: number = call.argument("slingshotDistance");
            this.pullToRefreshView.setSlingshotDistance(slingshotDistance);
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case "getDefaultSlingshotDistance":
          result.success(this.pullToRefreshView != null &&
            this.pullToRefreshView.settings.slingshotDistance != null ?
            this.pullToRefreshView.settings.slingshotDistance : 100);
          break;
        case "setSize":
          if (this.pullToRefreshView != null) {
            let size: number = call.argument("size");
            this.pullToRefreshView.setSize(size);
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      let err: Error = e as Error;
      ChannelResultUtil.reportError(LOG_TAG, call.method, result, err as Object);
    }
  }

  public onRefresh(): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<String, Object> = new Map<String, Object>();
    channel.invokeMethod("onRefresh", obj);
  }

  public dispose(): void {
    super.dispose();
    this.pullToRefreshView = null;
  }
}