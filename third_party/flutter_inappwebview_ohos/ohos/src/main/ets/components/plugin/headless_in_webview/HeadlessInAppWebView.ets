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
import { Disposable } from '../types/Disposable';
import { FlutterWebView } from '../webview/in_app_webview/FlutterWebView';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { HeadlessWebViewChannelDelegate } from './HeadlessWebViewChannelDelegate';
import Size2D from '../types/Size2D';
import Util from '../Util';
import { ComponentContent, OverlayManager } from '@kit.ArkUI';
import window from '@ohos.window';
import { buildHeadlessOhosWebView, HeadlessWebParams } from '../webview/in_app_webview/OhosWebView';

export class HeadlessInAppWebView implements Disposable {
  public static readonly LOG_TAG: string = 'HeadlessInAppWebView';
  public static readonly METHOD_CHANNEL_NAME_PREFIX: string = 'com.pichillilorenzo/flutter_headless_inappwebview_';

  public readonly id: string;
  public channelDelegate: HeadlessWebViewChannelDelegate | null = null;
  public flutterWebView: FlutterWebView | null = null;
  public plugin: InAppWebViewFlutterPlugin | null = null;
  private componentContent: ComponentContent<HeadlessWebParams> | null = null;
  private overlayManager: OverlayManager | null = null;
  private builderParams: HeadlessWebParams | null = null
  private currentSize: Size2D = new Size2D(-1, -1);

  constructor(plugin: InAppWebViewFlutterPlugin, id: string, flutterWebView: FlutterWebView) {
    this.id = id;
    this.plugin = plugin;
    this.flutterWebView = flutterWebView;
    let channel = new MethodChannel(plugin.messenger!, HeadlessInAppWebView.METHOD_CHANNEL_NAME_PREFIX + id);
    this.channelDelegate = new HeadlessWebViewChannelDelegate(this, channel);
  }

  onWebViewCreated(): void {
    if (this.channelDelegate != null) {
      this.channelDelegate.onWebViewCreated();
    }
  }

  prepare(params: Map<string, Any>): void {
    let initialSizeMap: Map<string, Any> = params.get('initialSize') as Map<string, Any>;
    let size: Size2D | null = Size2D.fromMap(initialSizeMap);
    if (size == null) {
      size = new Size2D(-1, -1);
    }
    this.setSize(size);
    this.attachAndLoad(params);
  }

  private async attachAndLoad(params: Map<string, Any>): Promise<void> {
    await this.attachToOverlay();
	if (this.componentContent == null) {
      Log.e(HeadlessInAppWebView.LOG_TAG, 'attachToOverlay failed, skip onWebViewCreated');
      return;
    }
    this.onWebViewCreated();
    if (this.flutterWebView != null) {
      this.flutterWebView.makeInitialLoad(params);
    }
  }

  setSize(size: Size2D): void {
    let scale = Util.getPixelDensity();
    let fullscreenSize = Util.getFullscreenSize();
    let widthPx =
      size.getWidth() == -1 ? fullscreenSize.getWidth() : (size.getWidth() * scale);
    let heightPx =
      size.getHeight() == -1 ? fullscreenSize.getHeight() : (size.getHeight() * scale);
    this.currentSize = new Size2D(widthPx, heightPx);
    let widthVp = widthPx / scale;
    let heightVp = heightPx / scale;
    if (this.builderParams != null) {
      this.builderParams.width = widthVp;
      this.builderParams.height = heightVp;
      if (this.componentContent != null) {
        try {
          this.componentContent.update(this.builderParams);
        } catch (e) {
          Log.e(HeadlessInAppWebView.LOG_TAG, 'applySizeInternal update error: ' + JSON.stringify(e));
        }
      }
    }
  }

  private async attachToOverlay(): Promise<void> {
    try {
      if (this.flutterWebView == null || this.plugin == null) {
        return;
      }
      let context = this.plugin.uiAbility != null ? this.plugin.uiAbility.context : this.plugin.applicationContext;
      if (context == null) {
        return;
      }
      let win = await window.getLastWindow(context);
      let uiContext = win.getUIContext();
      let scale = Util.getPixelDensity();
      let widthVp = this.currentSize.getWidth() / scale;
      let heightVp = this.currentSize.getHeight() / scale;
      this.builderParams = new HeadlessWebParams(this.flutterWebView, widthVp, heightVp);
      this.componentContent = new ComponentContent<HeadlessWebParams>(
        uiContext, wrapBuilder<[HeadlessWebParams]>(buildHeadlessOhosWebView), this.builderParams);
      this.overlayManager = uiContext.getOverlayManager();
      this.overlayManager.addComponentContent(this.componentContent, 0);
    } catch (e) {
      Log.e(HeadlessInAppWebView.LOG_TAG, 'attachToOverlay error: ' + JSON.stringify(e));
    }
  }

  private detachFromOverlay(): void {
    this.detachFromOverlayInternal(true);
  }

  private detachFromOverlayForTransfer(): void {
    this.detachFromOverlayInternal(false);
  }

  private detachFromOverlayInternal(disposeComponent: boolean): void {
    if (this.overlayManager != null && this.componentContent != null) {
      try {
        this.overlayManager.removeComponentContent(this.componentContent);
      } catch (e) {
        Log.e(HeadlessInAppWebView.LOG_TAG, 'detachFromOverlay remove error: ' + JSON.stringify(e));
      }
    }
    if (disposeComponent && this.componentContent != null) {
      try {
        this.componentContent.dispose();
      } catch (e) {
        Log.e(HeadlessInAppWebView.LOG_TAG, 'detachFromOverlay dispose error: ' + JSON.stringify(e));
      }
    }
    this.componentContent = null;
    this.overlayManager = null;
    this.builderParams = null;
  }

  getSize(): Size2D | null {
    if (this.flutterWebView == null) {
      return null;
    }
    let scale = Util.getPixelDensity();
    let fullscreenSize = Util.getFullscreenSize();
    let layoutWidth = this.currentSize.getWidth();
    let layoutHeight = this.currentSize.getHeight();
    return new Size2D(
      fullscreenSize.getWidth() == layoutWidth ? layoutWidth : (layoutWidth / scale),
      fullscreenSize.getHeight() == layoutHeight ? layoutHeight : (layoutHeight / scale)
    );
  }

  disposeAndGetFlutterWebView(): FlutterWebView | null {
    let newFlutterWebView: FlutterWebView | null = this.flutterWebView;
    if (this.flutterWebView != null) {
      this.flutterWebView = null;
      this.detachFromOverlayForTransfer();
      if (this.channelDelegate != null) {
        this.channelDelegate.dispose();
        this.channelDelegate = null;
      }
      if (this.plugin != null) {
        let headlessInAppWebViewManager = this.plugin.headlessInAppWebViewManager;
        if (headlessInAppWebViewManager != null && headlessInAppWebViewManager.webViews.has(this.id)) {
          headlessInAppWebViewManager.webViews.delete(this.id);
        }
      }
      this.plugin = null;
    }
    return newFlutterWebView;
  }

  dispose(): void {
    this.detachFromOverlay();
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    if (this.plugin != null) {
      let headlessInAppWebViewManager = this.plugin.headlessInAppWebViewManager;
      if (headlessInAppWebViewManager != null && headlessInAppWebViewManager.webViews.has(this.id)) {
        headlessInAppWebViewManager.webViews.delete(this.id);
      }
    }
    if (this.flutterWebView != null) {
      this.flutterWebView.dispose();
    }
    this.flutterWebView = null;
    this.plugin = null;
  }
}
