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

import { DVModel } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformWebView from '../PlatformWebView';
import InAppWebViewFlutterPlugin from '../../InAppWebViewFlutterPlugin';
import InAppWebView from './InAppWebView';
import InAppWebViewSettings from './InAppWebViewSettings';
import URLRequest from '../../types/URLRequest';
import UserScript from '../../types/UserScript';
import { Any, Log } from '@ohos/flutter_ohos';
import PullToRefreshLayout from '../../pull_to_refresh/PullToRefreshLayout';
import { DisplayListenerProxy } from './DisplayListenerProxy';
import PullToRefreshSettings from '../../pull_to_refresh/PullToRefreshSettings';
import { FindInteractionController } from '../../find_interaction/FindInteractionController';

const LOG_TAG: string = "IAWFlutterWebView";

export class FlutterWebView extends PlatformWebView {
  private webView: InAppWebView | null;
  private displayListenerProxy: DisplayListenerProxy | null = null;
  public pullToRefreshLayout: PullToRefreshLayout | null = null;
  public keepAliveId: string | null = null

  constructor(plugin: InAppWebViewFlutterPlugin, context: Context, id: string, params: Map<string, Any>) {
    super();
    this.displayListenerProxy = new DisplayListenerProxy();
    //TODO
    // let displayManager: DisplayManager = (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
    // displayListenerProxy.onPreWebViewInitialization(displayManager);

    this.keepAliveId = params.get("keepAliveId") as string

    let initialSettings: Map<string, Any> = params.get("initialSettings");
    let contextMenu: Map<string, Any> = params.get("contextMenu");
    let windowId = params.get("windowId") as number;
    let initialUserScripts: Array<Map<string, Any>> = params.get("initialUserScripts");
    let pullToRefreshInitialSettings: Map<string, Any> = params.get("pullToRefreshSettings");

    let customSettings: InAppWebViewSettings = new InAppWebViewSettings();
    customSettings.parse(initialSettings);

    let userScripts: Array<UserScript> = new Array<UserScript>();
    if (initialUserScripts != null) {
      initialUserScripts.forEach((item: Map<string, Any>) => {
        let script = UserScript.fromMap(item);
        if (script != null)
          userScripts.push(script);
      })
    }

    this.webView = new InAppWebView(context, plugin, id, windowId, customSettings, userScripts, contextMenu)
    this.displayListenerProxy.onPostWebViewInitialization(); //displayListenerProxy.onPostWebViewInitialization(displayManager);

    // set MATCH_PARENT layout params to the WebView, otherwise it won't take all the available space!
    //TODO
    let pullToRefreshSettings: PullToRefreshSettings = new PullToRefreshSettings();
    pullToRefreshSettings.parse(pullToRefreshInitialSettings);
    this.pullToRefreshLayout = new PullToRefreshLayout(plugin, id, pullToRefreshSettings);
    this.pullToRefreshLayout.addView(this.webView);
    // this.pullToRefreshLayout.prepare();

    let findInteractionController: FindInteractionController = new FindInteractionController(this.webView, plugin, id, null);
    this.webView.findInteractionController = findInteractionController;
    // findInteractionController.prepare();

    this.webView.prepare()
  }

  getView(): WrappedBuilder<[Params]> {
    // return this.pullToRefreshLayout != null ? this.pullToRefreshLayout : this.webView;
    return this.webView!.getView()
  }

  getController() {
    return this.webView!.getController();
  }

  getWebView() {
    return this.webView;
  }

  makeInitialLoad(params: Map<string, Any>): void {
    if (this.webView == null) {
      return;
    }
    let windowId = params.get("windowId") as number;
    let initialUrlRequest: Map<string, Any> = params.get("initialUrlRequest");
    let initialFile = params.get("initialFile") as string;
    let initialData: Map<string, Any> = params.get("initialData");
    if (windowId != null && windowId != undefined) {
      // Popup WebviewController is bound in onWindowNew; user scripts load in onControllerAttached.
    } else if (initialFile != null) {
      try {
        this.webView!.loadFile(initialFile);
      } catch (e) {
        let err: Error = e as Error;
        Log.e(LOG_TAG, "loadFile failed: " + JSON.stringify(err));
      }
    } else if (initialData != null) {
      let data = initialData.get("data") as string;
      let mimeType = initialData.get("mimeType") as string;
      let encoding = initialData.get("encoding") as string;
      let baseUrl = initialData.get("baseUrl") as string;
      let historyUrl = initialData.get("historyUrl") as string;
      this.webView!.loadDataWithBaseURL(baseUrl, data, mimeType, encoding, historyUrl);
    } else if (initialUrlRequest != null) {
      let urlRequest = URLRequest.fromMap(initialUrlRequest);
      if (urlRequest != null) {
        this.webView!.loadUrl(urlRequest);
      }
    }
  }

  dispose(): void {
    if (this.displayListenerProxy != null) {
      this.displayListenerProxy.dispose();
      this.displayListenerProxy = null;
    }
    if (this.webView != null) {
      let manager = this.webView.plugin?.inAppWebViewManager;
      if (manager != null) {
        manager.unregisterPlatformWebView(this.webView.id);
      }
    }
    if (this.keepAliveId == null && this.webView != null) {
      if (!this.webView.isDisposed()) {
        this.webView.releaseWebComponentResources();
      }
      this.webView.dispose();
      this.webView = null;
      // PullToRefreshLayout is disposed inside InAppWebView.dispose(); only drop our reference here.
      this.pullToRefreshLayout = null;
    }
  }

  public onInputConnectionLocked(): void {
    if (this.webView != null && this.webView.inAppBrowserDelegate == null && !this.webView.customSettings.useHybridComposition) {
      //TODO
      // this.webView.lockInputConnection();
    }
  }

  public onInputConnectionUnlocked(): void {
    if (this.webView != null && this.webView.inAppBrowserDelegate == null && !this.webView.customSettings.useHybridComposition) {
      //TODO
      // this.webView.unlockInputConnection();
    }
  }

  public onFlutterViewAttached(flutterView: DVModel): void {
    if (this.webView != null && !this.webView.customSettings.useHybridComposition) {
      //TODO
      // this.webView.setContainerView(flutterView);
    }
  }

  public onFlutterViewDetached(): void {
    // PlatformView detached from Flutter surface — release Web GPU resources promptly.
    if (this.keepAliveId == null) {
      this.dispose();
    }
    if (this.webView != null && !this.webView.customSettings.useHybridComposition) {
      //TODO
      // this.webView.setContainerView(null);
    }
  }
}