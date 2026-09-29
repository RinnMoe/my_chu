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

import { MethodCall, MethodChannel, Log } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView'
import { DVModel, DVModelParameters } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import { FlutterWebView } from './in_app_webview/FlutterWebView';
import { Context } from '@kit.AbilityKit';
import web_webview from '@ohos.web.webview';
import business_error from '@ohos.base';
import { webview } from '@kit.ArkWeb';
import ChannelResultUtil from '../types/ChannelResultUtil';
import { deviceInfo } from '@kit.BasicServicesKit';
import { BuilderNodeManager } from './in_app_webview/BuilderNodeManager';

const LOG_TAG = 'InAppWebViewManager'
const METHOD_CHANNEL_NAME = 'com.pichillilorenzo/flutter_inappwebview_manager'
const SDK_API_VERSION_18 = 18;

export class InAppWebViewManager extends ChannelDelegateImpl {

  private static arkWebEngineInitialized: boolean = false;

  /**
   * ArkWeb static APIs (e.g. getDefaultUserAgent) require the web engine to be
   * initialized before any Web component is created. Android WebSettings does not.
   */
  static ensureArkWebEngineInitialized(): void {
    if (InAppWebViewManager.arkWebEngineInitialized) {
      return;
    }
    try {
      webview.WebviewController.initializeWebEngine();
      InAppWebViewManager.arkWebEngineInitialized = true;
    } catch (error) {
      Log.e(LOG_TAG, `ensureArkWebEngineInitialized failed: ${JSON.stringify(error)}`);
    }
  }

  ensureArkWebEngineInitialized(): void {
    InAppWebViewManager.ensureArkWebEngineInitialized();
  }

  private plugin: InAppWebViewFlutterPlugin | null = null

  public keepAliveWebViews: Map<string, FlutterWebView | undefined> = new Map<string, FlutterWebView | undefined>()

  /** Active platform WebViews keyed by InAppWebView id (for explicit dispose from Dart). */
  public platformWebViews: Map<string, FlutterWebView> = new Map<string, FlutterWebView>();

  public controller: web_webview.WebviewController | null = null;

  public windowWebViewMessages: Map<number, ControllerHandler> = new Map<number, ControllerHandler>()

  /** Popup WebviewControllers created synchronously in onWindowNew (required by ArkWeb). */
  public windowWebViewControllers: Map<number, web_webview.WebviewController> =
    new Map<number, web_webview.WebviewController>();

  /** Target URLs for popup windows keyed by windowId. */
  public windowWebViewUrls: Map<number, string> = new Map<number, string>();

  public windowAutoincrementId: number = 0

  public debuggingEnabled = false;
  public builderNodeManager: BuilderNodeManager = new BuilderNodeManager();
  private disposed: boolean = false;

  constructor(plugin: InAppWebViewFlutterPlugin) {
    if (plugin.messenger == null) {
      throw new Error('InAppWebViewManager: plugin.messenger is null');
    }
    super(new MethodChannel(plugin.messenger, METHOD_CHANNEL_NAME));
    this.plugin = plugin
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getDefaultUserAgent':
        try {
		  InAppWebViewManager.ensureArkWebEngineInitialized();
          result.success(webview.WebviewController.getDefaultUserAgent());
        } catch (error) {
          ChannelResultUtil.reportError(LOG_TAG, 'getDefaultUserAgent', result, error as Object);
        }
        break;
      case 'clearClientCertPreferences':
        try{
          InAppWebViewManager.ensureArkWebEngineInitialized();
          if (this.controller == null) {
            this.controller = new web_webview.WebviewController();
          }
          this.controller?.clearClientAuthenticationCache();
          result.success(true);
        } catch (error) {
          ChannelResultUtil.reportError(LOG_TAG, 'clearClientCertPreferences', result, error as Object);
        }
        break;
      case 'getSafeBrowsingPrivacyPolicyUrl':
      /// OHOS 无对应 API，返回 null 表示平台不支持
        result.success(null);
        break;
      case 'setSafeBrowsingAllowlist':
      /// 配置一组免于安全浏览检查的主机（域名/IP地址）
      /// ohos非法和欺诈网站是强制启用的，此处返回 true 表示调用成功（与 Android API 契约一致）。
        result.success(true);
        break;
      case 'getCurrentWebViewPackage':
      /// Android专属API，OHOS不支持。
      /// ArkWeb是系统内置组件，不存在独立的WebView Provider包概念，
      /// 因此无法像Android那样通过WebViewCompat.getCurrentWebViewPackage()获取WebView渲染引擎包信息。
      /// 返回null表示平台不支持此功能。
        Log.w(LOG_TAG, 'getCurrentWebViewPackage is not supported on OHOS. ArkWeb is a system built-in component.');
        result.success(null);
        break;
      case 'setWebContentsDebuggingEnabled':
        try {
          this.debuggingEnabled = call.argument('debuggingEnabled') as boolean;
          web_webview.WebviewController.setWebDebuggingAccess(this.debuggingEnabled)
          result.success(true);
        } catch (error) {
          ChannelResultUtil.reportError(LOG_TAG, 'setWebContentsDebuggingEnabled', result, error as Object);
        }
        break;
      case 'getVariationsHeader':
      /// 获取编码后用作X-Client-Data HTTP标头的WebView变体，未找到实现
        result.success(null);
        break;
      case 'isMultiProcessEnabled':
      /// 监测WebView是否在多进程模式下运行，未找到对应实现
        result.success(false);
        break;
      case 'disableWebView':
        try {
          this.controller?.stop()
          result.success(true);
        } catch (error) {
          ChannelResultUtil.reportError(LOG_TAG, 'disableWebView', result, error as Object);
        }
        break;
      case 'disposeKeepAlive':
        try {
          let keepAliveId: string = call.argument('keepAliveId') as string;
          if (keepAliveId != null) {
            this.disposeKeepAlive(keepAliveId);
          }
          result.success(true);
        } catch (error) {
          let err: Error = error as Error;
          ChannelResultUtil.reportError(LOG_TAG, 'disposeKeepAlive', result, err as Object);
        }
        break;
      case 'disposeWebView':
        try {
          let disposeViewIdArg: number | string | null = call.argument('viewId') as number | string | null;
          if (disposeViewIdArg != null) {
            this.disposePlatformWebView(disposeViewIdArg);
          }
          result.success(true);
        } catch (error) {
          let err: Error = error as Error;
          ChannelResultUtil.reportError(LOG_TAG, 'disposeWebView', result, err as Object);
        }
        break;
      case 'clearAllCache':
          if (deviceInfo.sdkApiVersion >= SDK_API_VERSION_18) {
            try {
			      InAppWebViewManager.ensureArkWebEngineInitialized();
              let includeDiskFiles: boolean = call.argument('includeDiskFiles') as boolean;
              webview.WebviewController.removeAllCache(includeDiskFiles);
              result.success(true);
            } catch (error) {
              ChannelResultUtil.reportError(LOG_TAG, 'clearAllCache', result, error as Object);
              return;
            }
          } else {
            Log.w(LOG_TAG, "Failed to call the clearAllCache. " +
            "Cause: The 'removeAllCache' API is supported since SDK version 18. " +
            "Please upgrade the SDK version or switch to call the 'clearCache' API on the business side.");
            result.success(false);
        }
          break;
      default:
        result.notImplemented();
    }
  }
  public registerPlatformWebView(viewId: number | string, flutterWebView: FlutterWebView): void {
    if (this.disposed) {
      return;
    }
    this.platformWebViews.set(String(viewId), flutterWebView);
  }

  public unregisterPlatformWebView(viewId: number | string): void {
    if (this.disposed) {
      return;
    }
    this.platformWebViews.delete(String(viewId));
  }

  public disposePlatformWebView(viewId: number | string): void {
    if (this.disposed) {
      return;
    }
    let key = String(viewId);
    let flutterWebView: FlutterWebView | undefined = this.platformWebViews.get(key);
    if (flutterWebView != null) {
      Log.d(LOG_TAG, `disposePlatformWebView: ${key}`);
      this.platformWebViews.delete(key);
      flutterWebView.dispose();
    } else {
      Log.w(LOG_TAG, `disposePlatformWebView: not found ${key}`);
    }
  }

  public cleanupStaleWindowState(): void {
    this.windowWebViewMessages.forEach((handler: ControllerHandler, windowId: number) => {
      try {
        handler.setWebController(null);
      } catch (error) {
        Log.e(LOG_TAG, `cleanupStaleWindowState windowId=${windowId} failed: ${JSON.stringify(error)}`);
      }
    });
    this.windowWebViewMessages.clear();
    this.windowWebViewControllers.clear();
    this.windowWebViewUrls.clear();
    // Keep windowAutoincrementId monotonic so recycled IDs do not collide with
    // Flutter widgets that still hold a previous windowId briefly.
  }

  public disposeKeepAlive(keepAliveId: string): void {
    let flutterWebView: FlutterWebView | undefined = this.keepAliveWebViews.get(keepAliveId)
    if (flutterWebView != null) {
      flutterWebView.keepAliveId = null;
      // be sure to remove the view from the previous parent.
      let view: WrappedBuilder<[Params]> = flutterWebView.getView();
      if (view != null) {
        // let parent: ViewGroup = view.getParent();
        // if (parent != null) {
        //   parent.removeView(view);
        // }
      }
      flutterWebView.dispose();
    }
    if (this.keepAliveWebViews.has(keepAliveId)) {
      this.keepAliveWebViews.delete(keepAliveId);
    }
    this.builderNodeManager.removeWebViewNode(keepAliveId);
  }

  public clearAllCache(context: Context, includeDiskFiles: boolean): void {
    // let tempWebView: WebView = new WebView(context)
    // tempWebView.clearCache(includeDiskFiles);
    // tempWebView.destroy();
  }

  public dispose(): void {
    super.dispose();
    this.platformWebViews.forEach((flutterWebView: FlutterWebView) => {
      try {
        flutterWebView.dispose();
      } catch (e) {
        Log.e(LOG_TAG, 'dispose: platformWebView dispose failed: ' + JSON.stringify(e));
      }
    });
    this.platformWebViews.clear();
    this.keepAliveWebViews.forEach((flutterWebView: FlutterWebView | undefined) => {
      if (flutterWebView != undefined) {
        flutterWebView.keepAliveId = null;
        try {
          flutterWebView.dispose();
        } catch (e) {
          Log.e(LOG_TAG, 'dispose: keepAliveWebView dispose failed: ' + JSON.stringify(e));
        }
      }
    });
    this.keepAliveWebViews.clear();
    this.windowWebViewMessages.clear();
    this.windowWebViewControllers.clear();
    this.windowWebViewUrls.clear();
    this.builderNodeManager.dispose();
    this.controller = null;
    this.disposed = true;
    this.plugin = null;
  }
}
