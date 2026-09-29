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

import { Log, PlatformView, PlatformViewFactory, StandardMessageCodec } from '@ohos/flutter_ohos';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { FlutterWebView } from './in_app_webview/FlutterWebView';
import { Any } from '@ohos/flutter_ohos';
import { HeadlessInAppWebViewManager } from '../headless_in_webview/HeadlessInAppWebViewManager';
import { HeadlessInAppWebView } from '../headless_in_webview/HeadlessInAppWebView';
import { InAppWebViewManager } from './InAppWebViewManager';

const TAG: string = 'FlutterWebViewFactory';

export default class FlutterWebViewFactory extends PlatformViewFactory {
  public static VIEW_TYPE_ID = 'com.pichillilorenzo/flutter_inappwebview';
  private plugin: InAppWebViewFlutterPlugin | null;

  constructor(plugin: InAppWebViewFlutterPlugin) {
    super(StandardMessageCodec.INSTANCE);
    this.plugin = plugin;
  }

  public create(context: Context, id: number, args: Any): PlatformView {
    try {
      Log.d(TAG, 'create')
      if (this.plugin == null) {
        throw new Error('FlutterWebViewFactory: plugin is null');
      }
      let params: Map<string, Any> = args as Map<string, Any>;
      let flutterWebView: FlutterWebView | undefined = undefined;
      let viewId: number | string = id;

      let keepAliveId: string = params.get('keepAliveId') as string;
      let headlessWebViewId: string = params.get('headlessWebViewId') as string;

      let headlessInAppWebViewManager: HeadlessInAppWebViewManager | null = this.plugin.headlessInAppWebViewManager;
      if (headlessWebViewId != null && headlessInAppWebViewManager != null) {
        let headlessInAppWebView: HeadlessInAppWebView | undefined =
        headlessInAppWebViewManager.webViews.get(headlessWebViewId);
        if (headlessInAppWebView != undefined) {
          let disposedWebView = headlessInAppWebView.disposeAndGetFlutterWebView();
          if (disposedWebView != null) {
            disposedWebView.keepAliveId = keepAliveId;
            flutterWebView = disposedWebView;
          }
        }
      }

      let inAppWebViewManager: InAppWebViewManager | null = this.plugin.inAppWebViewManager;
      if (keepAliveId != null && flutterWebView == null && inAppWebViewManager != null) {
        flutterWebView = inAppWebViewManager.keepAliveWebViews.get(keepAliveId);
        if (flutterWebView != null) {
          // be sure to remove the view from the previous parent.
          let view = flutterWebView.getView();
          // if (view != null) {
          //   let parent:ViewGroup = view.getParent() ;
          //   if (parent != null) {
          //     parent.removeView(view);
          //   }
          // }
        }
      }

      let shouldMakeInitialLoad: boolean = flutterWebView == null;
      if (flutterWebView == null) {
        this.plugin.inAppWebViewManager?.ensureArkWebEngineInitialized();
        if (keepAliveId != null) {
          viewId = keepAliveId;
        }
        flutterWebView = new FlutterWebView(this.plugin, context, viewId.toString(), params);
      }

      if (shouldMakeInitialLoad) {
        flutterWebView.makeInitialLoad(params);
      }

      if (keepAliveId != null && inAppWebViewManager != null) {
        inAppWebViewManager.keepAliveWebViews.set(keepAliveId, flutterWebView);
      }

      if (inAppWebViewManager != null) {
        // 使用 PlatformView 工厂 id 注册，与 Dart onPlatformViewCreated 的 viewId 一致
        inAppWebViewManager.registerPlatformWebView(id, flutterWebView);
        let webView = flutterWebView.getWebView();
        if (webView != null && String(webView.id) !== String(id)) {
          inAppWebViewManager.registerPlatformWebView(webView.id, flutterWebView);
        }
      }

      return flutterWebView;
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'create failed: ' + JSON.stringify(err));
      throw new Error(err.message);
    }
  }

  dispose(): void {
    this.plugin = null;
  }
}
