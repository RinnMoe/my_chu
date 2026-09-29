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

import { Any, Log, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Context } from '@kit.AbilityKit';
import { List } from '@kit.ArkTS';
import { ComponentContent, OverlayManager } from '@kit.ArkUI';
import window from '@ohos.window';
import { Disposable } from '../types/Disposable';
import InAppWebView from '../webview/in_app_webview/InAppWebView';
import { InAppBrowserDelegate } from './InAppBrowserDelegate';
import InAppBrowserSettings from './InAppBrowserSettings';
import { ActivityResultListener } from './ActivityResultListener';
import InAppBrowserManager from './InAppBrowserManager';
import InAppBrowserChannelDelegate from './InAppBrowserChannelDelegate';
import InAppBrowserMenuItem from '../types/InAppBrowserMenuItem';
import InAppWebViewSettings from '../webview/in_app_webview/InAppWebViewSettings';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { FlutterWebView } from '../webview/in_app_webview/FlutterWebView';
import WebViewChannelDelegate from '../webview/WebViewChannelDelegate';
import PullToRefreshLayout from '../pull_to_refresh/PullToRefreshLayout';
import {
  buildInAppBrowserOhosWebView,
  InAppBrowserWebParams
} from '../webview/in_app_webview/OhosWebView';

const LOG_TAG = 'InAppBrowserSession';
const METHOD_CHANNEL_NAME_PREFIX = 'com.pichillilorenzo/flutter_inappbrowser_';

export default class InAppBrowserSession implements InAppBrowserDelegate, Disposable {
  public id: string = '';
  public isHidden: boolean = false;
  public customSettings: InAppBrowserSettings = new InAppBrowserSettings();
  public webView: InAppWebView | null = null;
  public flutterWebView: FlutterWebView | null = null;
  public pullToRefreshLayout: PullToRefreshLayout | null = null;
  public manager: InAppBrowserManager | null = null;
  public channelDelegate: InAppBrowserChannelDelegate | null = null;
  public menuItems: List<InAppBrowserMenuItem> = new List<InAppBrowserMenuItem>();
  private activityResultListeners: List<ActivityResultListener> = new List<ActivityResultListener>();
  private componentContent: ComponentContent<InAppBrowserWebParams> | null = null;
  private overlayManager: OverlayManager | null = null;
  private builderParams: InAppBrowserWebParams | null = null;
  private overlayAttached: boolean = false;

  constructor(manager: InAppBrowserManager) {
    this.manager = manager;
  }

  start(plugin: InAppWebViewFlutterPlugin, args: Map<string, Any> | Record<string, Any>): void {
    this.id = InAppBrowserManager.getArg(args, 'id') as string;
    if (this.id == null || this.id.length === 0) {
      Log.e(LOG_TAG, 'start: missing browser id');
      return;
    }

    let settingsMap: Map<string, Any> | Record<string, Any> | null = InAppBrowserManager.getArg(args, 'settings');
    if (settingsMap != null) {
      this.customSettings.parse(InAppBrowserManager.asMap(settingsMap as Record<string, Any>));
      this.isHidden = this.customSettings.hidden;
    }

    this.parseMenuItems(args);

    let context: Context | null = plugin.uiAbility != null ? plugin.uiAbility.context : plugin.applicationContext;
    if (context == null) {
      Log.e(LOG_TAG, 'start: no context');
      return;
    }

    let webViewParams: Map<string, Any> = InAppBrowserManager.buildWebViewParams(args);
    this.flutterWebView = new FlutterWebView(plugin, context, this.id, webViewParams);
    this.webView = this.flutterWebView.getWebView();
    this.pullToRefreshLayout = this.flutterWebView.pullToRefreshLayout;

    if (this.webView != null) {
      this.webView.inAppBrowserDelegate = this;
      let channel = new MethodChannel(plugin.messenger!, METHOD_CHANNEL_NAME_PREFIX + this.id);
      this.channelDelegate = new InAppBrowserChannelDelegate(channel);
      this.webView.channelDelegate = new WebViewChannelDelegate(this.webView, channel);
    }

    this.attachAndLoad(args);
  }

  private parseMenuItems(args: Map<string, Any> | Record<string, Any>): void {
    let menuItemList: Object | null = InAppBrowserManager.getArg(args, 'menuItems');
    if (menuItemList == null || !(menuItemList instanceof Array)) {
      return;
    }
    let items = menuItemList as Array<Object>;
    for (let i = 0; i < items.length; i++) {
      let item = InAppBrowserMenuItem.fromMap(items[i] as Map<string, Any>);
      if (item != null) {
        this.menuItems.add(item);
      }
    }
  }

  private async attachAndLoad(args: Map<string, Any> | Record<string, Any>): Promise<void> {
    await this.ensureOverlayAttached();
    if (this.webView != null) {
      await this.webView.prepare();
    }
    if (this.flutterWebView != null) {
      let loadParams: Map<string, Any> = InAppBrowserManager.buildLoadParams(args);
      this.flutterWebView.makeInitialLoad(loadParams);
    }
    if (this.channelDelegate != null) {
      this.channelDelegate.onBrowserCreated();
    }
  }

  private async ensureOverlayAttached(): Promise<void> {
    if (this.overlayAttached || this.flutterWebView == null || this.manager == null ||
      this.manager.plugin == null) {
      return;
    }
    try {
      let plugin = this.manager.plugin!;
      let context = plugin.uiAbility != null ? plugin.uiAbility.context : plugin.applicationContext;
      if (context == null) {
        return;
      }
      let win = await window.getLastWindow(context);
      let uiContext = win.getUIContext();
      this.builderParams = new InAppBrowserWebParams(this.flutterWebView!, !this.isHidden);
      this.componentContent = new ComponentContent<InAppBrowserWebParams>(
        uiContext, wrapBuilder<[InAppBrowserWebParams]>(buildInAppBrowserOhosWebView), this.builderParams);
      this.overlayManager = uiContext.getOverlayManager();
      this.overlayManager.addComponentContent(this.componentContent, 1);
      this.overlayAttached = true;
    } catch (e) {
      Log.e(LOG_TAG, 'ensureOverlayAttached error: ' + JSON.stringify(e));
    }
  }

  private updateOverlayVisibility(visible: boolean): void {
    if (this.builderParams != null) {
      this.builderParams.visible = visible;
      if (this.componentContent != null) {
        try {
          this.componentContent.update(this.builderParams);
        } catch (e) {
          Log.e(LOG_TAG, 'updateOverlayVisibility error: ' + JSON.stringify(e));
        }
      }
    }
  }

  private detachOverlay(): void {
    if (this.overlayManager != null && this.componentContent != null) {
      try {
        this.overlayManager.removeComponentContent(this.componentContent);
      } catch (e) {
        Log.e(LOG_TAG, 'detachOverlay remove error: ' + JSON.stringify(e));
      }
    }
    if (this.componentContent != null) {
      try {
        this.componentContent.dispose();
      } catch (e) {
        Log.e(LOG_TAG, 'detachOverlay dispose error: ' + JSON.stringify(e));
      }
    }
    this.componentContent = null;
    this.overlayManager = null;
    this.builderParams = null;
    this.overlayAttached = false;
  }

  public getCustomSettings(): Map<string, Any> | null {
    let webViewSettingsMap: Map<string, Any> | null =
      this.webView != null ? this.webView.getCustomSettings() : null;
    if (webViewSettingsMap == null) {
      return null;
    }
    let settingsMap: Map<string, Any> = this.customSettings.getRealSettings(this);
    let keys = webViewSettingsMap.keys();
    for (let key of keys) {
      settingsMap.set(key, webViewSettingsMap.get(key));
    }
    return settingsMap;
  }

  public setSettings(newSettings: InAppBrowserSettings, newSettingsMap: Map<string, Any>): void {
    let newInAppWebViewSettings: InAppWebViewSettings = new InAppWebViewSettings();
    newInAppWebViewSettings.parse(newSettingsMap);
    if (this.webView != null) {
      this.webView.setSettings(newInAppWebViewSettings, newSettingsMap);
    }
    if (newSettingsMap.get('hidden') != null && this.customSettings.hidden != newSettings.hidden) {
      if (newSettings.hidden) {
        this.hide();
      } else {
        this.show();
      }
    }
    this.customSettings = newSettings;
  }

  public hide(): void {
    this.isHidden = true;
    this.updateOverlayVisibility(false);
  }

  public show(): void {
    this.isHidden = false;
    if (!this.overlayAttached) {
      this.ensureOverlayAttached();
    }
    this.updateOverlayVisibility(true);
  }

  public close(result: MethodResult | null): void {
    if (this.channelDelegate != null) {
      this.channelDelegate.onExit();
    }
    this.dispose();
    if (result != null) {
      result.success(true);
    }
  }

  getActivityResultListeners(): List<ActivityResultListener> {
    return this.activityResultListeners;
  }

  didChangeTitle(_title: string): void {
  }

  didStartNavigation(_url: string): void {
  }

  didUpdateVisitedHistory(_url: string): void {
  }

  didFinishNavigation(_url: string): void {
  }

  didFailNavigation(_url: string, _errorCode: number, _description: string): void {
  }

  didChangeProgress(_progress: number): void {
  }

  dispose(): void {
    this.detachOverlay();
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    this.activityResultListeners.clear();
    this.menuItems.clear();
    if (this.flutterWebView != null) {
      this.flutterWebView.dispose();
      this.flutterWebView = null;
      this.webView = null;
      this.pullToRefreshLayout = null;
    }
    if (this.manager != null) {
      this.manager.removeBrowser(this.id);
    }
    this.manager = null;
  }
}
