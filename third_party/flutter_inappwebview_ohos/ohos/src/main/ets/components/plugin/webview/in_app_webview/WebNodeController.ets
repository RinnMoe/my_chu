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

import { BuilderNode, FrameNode, NodeController } from '@kit.ArkUI';
import { Log } from '@ohos/flutter_ohos';
import web_webview from '@ohos.web.webview';
import InAppWebView from './InAppWebView';
import InAppWebViewClient from './InAppWebViewClient';

const TAG = 'WebNodeController'

@Observed
export class WebBuilderParams {
  public controller: web_webview.WebviewController;
  public inAppWebView: InAppWebView;
  public cacheEnabled: boolean = true;
  public transparentBackground: boolean = false;
  public startScripts: Array<ScriptItem> = [];
  public onControllerAttached: () => void = () => {};
  public onAreaChange: (oldValue: Area, newValue: Area) => void = (_oldValue: Area, _newValue: Area) => {};
  public getAliveClient: () => InAppWebViewClient | null = () => null;
  public setPathAllowingUniversalAccess: () => void = () => {};
  public setWebSchemeHandler: () => void = () => {};

  constructor(
    controller: web_webview.WebviewController,
    inAppWebView: InAppWebView,
    cacheEnabled: boolean,
    transparentBackground: boolean,
    startScripts: Array<ScriptItem>,
    onControllerAttached: () => void,
    onAreaChange: (oldValue: Area, newValue: Area) => void,
    getAliveClient: () => InAppWebViewClient | null,
    setPathAllowingUniversalAccess: () => void,
    setWebSchemeHandler: () => void
  ) {
    this.controller = controller;
    this.inAppWebView = inAppWebView;
    this.cacheEnabled = cacheEnabled;
    this.transparentBackground = transparentBackground;
    this.startScripts = startScripts;
    this.onControllerAttached = onControllerAttached;
    this.onAreaChange = onAreaChange;
    this.getAliveClient = getAliveClient;
    this.setPathAllowingUniversalAccess = setPathAllowingUniversalAccess;
    this.setWebSchemeHandler = setWebSchemeHandler;
  }
}

@Builder
function buildWebNode(params: WebBuilderParams) {
  Web({
    src: params.inAppWebView.getLoadUrl(),
    controller: params.controller
  })
    // Avoid RESIZE_VISUAL/OHOS default resize in nested Flutter PlatformView scenes;
    // keyboard viewport shrink desyncs hit-testing from painted content in release.
    .keyboardAvoidMode(WebKeyboardAvoidMode.OVERLAYS_CONTENT)
    .id(params.inAppWebView.getWebSnapshotId())
    .onControllerAttached(() => {
      params.onControllerAttached();
    })
    .onAlert(params.inAppWebView.inAppWebViewClient?.onAlert)
    .onBeforeUnload(params.inAppWebView.inAppWebViewClient?.onBeforeUnload)
    .onConfirm(params.inAppWebView.inAppWebViewClient?.onConfirm)
    .onPrompt((event) => {
      if (params.inAppWebView == null || params.inAppWebView.inAppWebViewClient == null) {
        return false;
      }
      return params.inAppWebView.inAppWebViewClient.onPrompt(event, params.inAppWebView);
    })
    .onConsole(params.inAppWebView.inAppWebViewClient?.onConsole)
    .onDownloadStart(params.inAppWebView.inAppWebViewClient?.onDownloadStart)
    .onErrorReceive((event) => {
      params.getAliveClient()?.onErrorReceive(event);
    })
    .onHttpErrorReceive((event) => {
      params.getAliveClient()?.onHttpErrorReceive(event);
    })
    .onPageBegin((event) => {
      params.getAliveClient()?.onPageBegin(event);
    })
    .onPageEnd((event) => {
      params.getAliveClient()?.onPageEnd(event);
    })
    .onProgressChange(params.inAppWebView.inAppWebViewClient?.onProgressChange)
    .onTitleReceive(params.inAppWebView.inAppWebViewClient?.onTitleReceive)
    .onRefreshAccessedHistory(params.inAppWebView.inAppWebViewClient?.onRefreshAccessedHistory)
    .onRenderExited(params.inAppWebView.inAppWebViewClient?.onRenderExited)
    .onShowFileSelector(params.inAppWebView.inAppWebViewClient?.onShowFileSelector)
    .onResourceLoad(params.inAppWebView.inAppWebViewClient?.onResourceLoad)
    .onScaleChange(params.inAppWebView.inAppWebViewClient?.onScaleChange)
    .onInterceptRequest((event) => {
      if (params.inAppWebView == null || params.inAppWebView.inAppWebViewClient == null) {
        return null;
      }
      return params.inAppWebView.inAppWebViewClient.onInterceptRequest(event);
    })
    .onHttpAuthRequest(params.inAppWebView.inAppWebViewClient?.onHttpAuthRequest)
    .onSslErrorEventReceive(params.inAppWebView.inAppWebViewClient?.onSslErrorEventReceive)
    .onClientAuthenticationRequest(params.inAppWebView.inAppWebViewClient?.onClientAuthenticationRequest)
    .onPermissionRequest(params.inAppWebView.inAppWebViewClient?.onPermissionRequest)
    .onContextMenuShow(params.inAppWebView.inAppWebViewClient?.onContextMenuShow)
    .onContextMenuHide(params.inAppWebView.inAppWebViewClient?.onContextMenuHide)
    .onScroll(params.inAppWebView.inAppWebViewClient?.onScroll)
    .onGeolocationShow(params.inAppWebView.inAppWebViewClient?.onGeolocationShow)
    .onGeolocationHide(params.inAppWebView.inAppWebViewClient?.onGeolocationHide)
    .onFullScreenEnter(params.inAppWebView.inAppWebViewClient?.onFullScreenEnter)
    .onFullScreenExit(params.inAppWebView.inAppWebViewClient?.onFullScreenExit)
    .onWindowNew(params.inAppWebView.customSettings.multiWindowAccess
      ? params.inAppWebView.inAppWebViewClient?.onWindowNew
      : undefined)
    .onWindowExit(params.inAppWebView.inAppWebViewClient?.onWindowExit)
    .onSearchResultReceive(params.inAppWebView.inAppWebViewClient?.onSearchResultReceive)
    .onDataResubmitted(params.inAppWebView.inAppWebViewClient?.onDataResubmitted)
    .onPageVisible(params.inAppWebView.inAppWebViewClient?.onPageVisible)
    .onInterceptKeyEvent(params.inAppWebView.inAppWebViewClient?.onInterceptKeyEvent)
    .onTouchIconUrlReceived(params.inAppWebView.inAppWebViewClient?.onTouchIconUrlReceived)
    .onFaviconReceived(params.inAppWebView.inAppWebViewClient?.onFaviconReceived)
    .onAudioStateChanged(params.inAppWebView.inAppWebViewClient?.onAudioStateChanged)
    .onFirstContentfulPaint(params.inAppWebView.inAppWebViewClient?.onFirstContentfulPaint)
    .onLoadIntercept(params.inAppWebView.inAppWebViewClient?.onLoadIntercept)
    .onOverrideUrlLoading(params.inAppWebView.inAppWebViewClient?.onOverrideUrlLoading)
    .onRequestSelected(params.inAppWebView.inAppWebViewClient?.onRequestSelected)
    .onScreenCaptureRequest(params.inAppWebView.inAppWebViewClient?.onScreenCaptureRequest)
    .onOverScroll(params.inAppWebView.inAppWebViewClient?.onOverScroll)
    .onNavigationEntryCommitted(params.inAppWebView.inAppWebViewClient?.onNavigationEntryCommitted)
    .onSafeBrowsingCheckResult(params.inAppWebView.inAppWebViewClient?.onSafeBrowsingCheckResult)
    .onNativeEmbedLifecycleChange(params.inAppWebView.inAppWebViewClient?.onNativeEmbedLifecycleChange)
    .onNativeEmbedGestureEvent(params.inAppWebView.inAppWebViewClient?.onNativeEmbedGestureEvent)
    .onRenderProcessNotResponding(params.inAppWebView.inAppWebViewClient?.onRenderProcessNotResponding)
    .onRenderProcessResponding(params.inAppWebView.inAppWebViewClient?.onRenderProcessResponding)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      params.onAreaChange(oldValue, newValue);
    })
    .domStorageAccess(params.inAppWebView.customSettings.domStorageAccess)
    .fileAccess(params.inAppWebView.customSettings.fileAccess)
    .imageAccess(params.inAppWebView.customSettings.imageAccess)
    .javaScriptAccess(params.inAppWebView.customSettings.javaScriptAccess)
    .overScrollMode(params.inAppWebView.customSettings.overScrollMode)
    .mixedMode(params.inAppWebView.customSettings.mixedMode)
    .onlineImageAccess(params.inAppWebView.customSettings.onlineImageAccess)
    .zoomAccess(params.inAppWebView.customSettings.zoomAccess)
    .overviewModeAccess(params.inAppWebView.customSettings.overviewModeAccess)
    .databaseAccess(params.inAppWebView.customSettings.databaseAccess)
    .geolocationAccess(params.inAppWebView.customSettings.geolocationAccess)
    .mediaPlayGestureAccess(params.inAppWebView.customSettings.mediaPlayGestureAccess)
    .multiWindowAccess(params.inAppWebView.customSettings.multiWindowAccess &&
     params.inAppWebView.customSettings.allowWindowOpenMethod)
    .horizontalScrollBarAccess(params.inAppWebView.customSettings.horizontalScrollBarAccess)
    .verticalScrollBarAccess(params.inAppWebView.customSettings.verticalScrollBarAccess)
    .cacheMode(params.cacheEnabled ? params.inAppWebView.customSettings.cacheMode : CacheMode.Online)
    .textZoomRatio(params.inAppWebView.customSettings.textZoomRatio)
    .initialScale(params.inAppWebView.customSettings.initialScale)
    .blockNetwork(params.inAppWebView.customSettings.blockNetwork)
    .defaultFixedFontSize(params.inAppWebView.customSettings.defaultFixedFontSize)
    .defaultFontSize(params.inAppWebView.customSettings.defaultFontSize)
    .minFontSize(params.inAppWebView.customSettings.minFontSize)
    .minLogicalFontSize(params.inAppWebView.customSettings.minLogicalFontSize)
    .webFixedFont(params.inAppWebView.customSettings.webFixedFont)
    .webSansSerifFont(params.inAppWebView.customSettings.webSansSerifFont)
    .webSerifFont(params.inAppWebView.customSettings.webSerifFont)
    .webStandardFont(params.inAppWebView.customSettings.webStandardFont)
    .webFantasyFont(params.inAppWebView.customSettings.webFantasyFont)
    .webCursiveFont(params.inAppWebView.customSettings.webCursiveFont)
    .darkMode(params.inAppWebView.customSettings.darkMode)
    .forceDarkAccess(params.inAppWebView.customSettings.forceDarkAccess)
    .pinchSmooth(params.inAppWebView.customSettings.pinchSmooth)
    .allowWindowOpenMethod(params.inAppWebView.customSettings.allowWindowOpenMethod)
    .layoutMode(params.inAppWebView.customSettings.layoutMode)
    .enableNativeEmbedMode(params.inAppWebView.customSettings.enableNativeEmbedMode)
    .javaScriptOnDocumentStart(params.startScripts)
    .backgroundColor(params.transparentBackground ? Color.Transparent : Color.White)
}

const wrappedBuildWebNode: WrappedBuilder<[WebBuilderParams]> = wrapBuilder(buildWebNode);

export class WebNodeController extends NodeController {
  private rootNode: FrameNode | null = null;
  private webBuilderNode: BuilderNode<[WebBuilderParams]> | null = null;
  private webFrameNode: FrameNode | null = null;
  private webParams: WebBuilderParams | null = null;
  private isWebMounted: boolean = false;
  private uiContext: UIContext | null = null;

  constructor() {
    super();
  }

  public initParams(params: WebBuilderParams): void {
    this.webParams = params;
  }

  public updateParams(params: WebBuilderParams): void {
    this.webParams = params;
    if (this.webBuilderNode != null) {
      this.webBuilderNode.update(params);
    }
  }

  public makeNode(uiContext: UIContext): FrameNode | null {
    this.uiContext = uiContext;
    if (this.rootNode == null) {
      this.rootNode = new FrameNode(uiContext);
    }
    if (this.webBuilderNode == null && this.webParams != null) {
      this.webBuilderNode = new BuilderNode<[WebBuilderParams]>(uiContext);
      this.webBuilderNode.build(wrappedBuildWebNode, this.webParams!);
      this.webFrameNode = this.webBuilderNode.getFrameNode();
      if (this.webFrameNode != null) {
        this.rootNode.appendChild(this.webFrameNode!);
        this.isWebMounted = true;
      }
    } else if (this.webBuilderNode != null && !this.isWebMounted && this.webFrameNode != null) {
      try {
        this.rootNode.appendChild(this.webFrameNode!);
        this.isWebMounted = true;
      } catch (e) {
        Log.e(TAG, 'makeNode: re-attach webFrameNode error: ' + JSON.stringify(e));
      }
    }
    return this.rootNode;
  }

  public mountWebComponent(): void {
    if (this.rootNode == null || this.webFrameNode == null) {
      return;
    }
    if (this.isWebMounted) {
      return;
    }
    try {
      this.rootNode!.appendChild(this.webFrameNode!);
      this.isWebMounted = true;
    } catch (e) {
      Log.e(TAG, 'mountWebComponent error: ' + JSON.stringify(e));
    }
  }

  public unmountWebComponent(): void {
    if (this.rootNode == null || this.webFrameNode == null) {
      return;
    }
    if (!this.isWebMounted) {
      return;
    }
    try {
      this.rootNode!.removeChild(this.webFrameNode!);
      this.isWebMounted = false;
    } catch (e) {
      Log.e(TAG, 'unmountWebComponent error: ' + JSON.stringify(e));
    }
  }

  public isMounted(): boolean {
    return this.isWebMounted;
  }

  public dispose(): void {
    if (this.webFrameNode != null && this.rootNode != null && this.isWebMounted) {
      try {
        this.rootNode!.removeChild(this.webFrameNode!);
      } catch (e) {
        Log.e(TAG, 'dispose removeChild error: ' + JSON.stringify(e));
      }
    }
    this.isWebMounted = false;
    if (this.webBuilderNode != null) {
      try {
        this.webBuilderNode!.dispose();
      } catch (e) {
        Log.e(TAG, 'dispose BuilderNode error: ' + JSON.stringify(e));
      }
    }
    if (this.rootNode != null) {
      try {
        this.rootNode!.dispose();
      } catch (e) {
        Log.e(TAG, 'dispose rootNode error: ' + JSON.stringify(e));
      }
    }
    this.webBuilderNode = null;
    this.webFrameNode = null;
    this.rootNode = null;
    this.webParams = null;
    this.uiContext = null;
  }
}
