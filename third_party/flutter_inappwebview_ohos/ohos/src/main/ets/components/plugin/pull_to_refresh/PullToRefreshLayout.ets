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

import { Log, MethodChannel } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { Disposable } from '../types/Disposable';
import PullToRefreshChannelDelegate from './PullToRefreshChannelDelegate';
import PullToRefreshSettings from './PullToRefreshSettings';
import InAppWebView from '../webview/in_app_webview/InAppWebView';
import EventConstant from '../EventConstant'

const LOG_TAG = "PullToRefreshLayout";
const METHOD_CHANNEL_NAME_PREFIX = "com.pichillilorenzo/flutter_inappwebview_pull_to_refresh_";

export default class PullToRefreshLayout implements Disposable {
  channelDelegate: PullToRefreshChannelDelegate | null;
  settings: PullToRefreshSettings = new PullToRefreshSettings();
  enabled: boolean = false
  public webView: InAppWebView | null = null
  private refreshing: boolean = false
  /** When true, the next UI onRefreshing is from setRefreshing(true), not a user gesture. */
  private suppressOnRefreshCallback: boolean = false

  constructor(plugin: InAppWebViewFlutterPlugin | null, id: Object | null = null, settings: PullToRefreshSettings) {
    this.settings = settings;
    let channel: MethodChannel = new MethodChannel(plugin!.messenger!, METHOD_CHANNEL_NAME_PREFIX + id);
    this.channelDelegate = new PullToRefreshChannelDelegate(this, channel);
  }

  setEnabled(enable: boolean) {
    this.settings.enabled = enable;
    this.emitAppearanceUpdate();
  }

  setColor(color: string): void {
    this.settings.color = color;
    this.emitAppearanceUpdate();
  }

  setBackgroundColor(color: string): void {
    this.settings.backgroundColor = color;
    this.emitAppearanceUpdate();
  }

  setDistanceToTriggerSync(distance: number): void {
    this.settings.distanceToTriggerSync = distance;
    this.emitAppearanceUpdate();
  }

  setSlingshotDistance(distance: number): void {
    this.settings.slingshotDistance = distance;
    this.emitAppearanceUpdate();
  }

  setSize(size: number): void {
    this.settings.size = size;
    this.emitAppearanceUpdate();
  }

  private emitAppearanceUpdate(): void {
    if (this.webView == null) {
      return;
    }
    try {
      let context = this.webView.context as common.UIAbilityContext;
      context.eventHub.emit(EventConstant.EVENT_PULL_UPDATE_APPEARANCE, this.settings);
    } catch (e) {
      let err: Error = e as Error;
      Log.e(LOG_TAG, 'emitAppearanceUpdate failed: ' + JSON.stringify(err));
    }
  }

  isEnabled(): boolean {
    return this.settings.enabled
  }

  setRefreshing(refreshing: boolean) {
    this.refreshing = refreshing;
    // Match Android SwipeRefreshLayout: programmatic setRefreshing(true) must not
    // fire OnRefreshListener. OHOS Refresh.onRefreshing can fire when state flips.
    // Keep the suppress flag until onRefresh consumes it (even if endRefreshing
    // runs first), so a delayed UI callback does not notify Dart.
    if (refreshing) {
      this.suppressOnRefreshCallback = true;
    }
    if (this.webView == null) {
      return;
    }
    try {
      let context = this.webView.context as common.UIAbilityContext;
      context.eventHub.emit(EventConstant.EVENT_PULL_SETREFRESHING, refreshing)
    } catch (e) {
      let err: Error = e as Error;
      Log.e(LOG_TAG, 'setRefreshing emit failed: ' + JSON.stringify(err));
    }
  }

  isRefreshing(): boolean {
    return this.refreshing
  }

  onRefresh() {
    if (this.suppressOnRefreshCallback) {
      this.suppressOnRefreshCallback = false;
      return;
    }
    if (this.channelDelegate == null) {
      this.setRefreshing(false);
      return;
    }
    this.refreshing = true;
    this.channelDelegate!!.onRefresh();
  }

  addView(webView: InAppWebView): void {
    this.webView = webView;
    webView.setPullToRefreshLayout(this);
  }

  public prepare(): void {
    if (this.webView != null) {
      this.webView.refresh()
      this.webView.scrollToTop()
    }
  }

  dispose(): void {
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    this.refreshing = false;
    this.suppressOnRefreshCallback = false;
    this.webView = null;
  }
}