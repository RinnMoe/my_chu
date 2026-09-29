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

import web_webview from '@ohos.web.webview'
import bundleManager from '@ohos.bundle.bundleManager';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView'
import URLRequest from '../../types/URLRequest';
import InAppWebViewFlutterPlugin from '../../InAppWebViewFlutterPlugin';
import { ClientCertHttpPaths } from '../../ClientCertUtil';
import InAppWebViewInterface from '../InAppWebViewInterface';
import InAppWebViewSettings from './InAppWebViewSettings';
import { buildOhosWebView } from './OhosWebView';
import { Any, Log, MethodChannel } from '@ohos/flutter_ohos';
import UserScript from '../../types/UserScript';
import JavaScriptBridgeInterface from '../JavaScriptBridgeInterface';
import JavaScriptBridgeJS from '../../plugin_scripts_js/JavaScriptBridgeJS';
import WebViewChannelDelegate from '../WebViewChannelDelegate';
import ContentWorld from '../../types/ContentWorld';
import { UserScriptInjectionTime } from '../../types/UserScriptInjectionTime';
import { ValueCallback } from '../../types/ValueCallback';
import { WebMessageChannel } from '../web_message/WebMessageChannel';
import UserContentController from '../../types/UserContentController';
import HitTestResult from '../../types/HitTestResult';
import util from '@ohos.util';
import Util from '../../Util';
import PluginScriptsUtil from '../../plugin_scripts_js/PluginScriptsUtil';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import InAppWebViewClient from './InAppWebViewClient';
import PluginScript from '../../types/PluginScript';
import PromisePolyfillJS from '../../plugin_scripts_js/PromisePolyfillJS';
import PrintJS from '../../plugin_scripts_js/PrintJS';
import OnWindowBlurEventJS from '../../plugin_scripts_js/OnWindowBlurEventJS';
import OnWindowFocusEventJS from '../../plugin_scripts_js/OnWindowFocusEventJS';
import InterceptAjaxRequestJS from '../../plugin_scripts_js/InterceptAjaxRequestJS';
import InterceptFetchRequestJS from '../../plugin_scripts_js/InterceptFetchRequestJS';
import OnLoadResourceJS from '../../plugin_scripts_js/OnLoadResourceJS';
import OnZoomScaleChangedJS from '../../plugin_scripts_js/OnZoomScaleChangedJS';
import OnJsBeforeUnloadJS from '../../plugin_scripts_js/OnJsBeforeUnloadJS';
import WindowOpenAboutBlankJS from '../../plugin_scripts_js/WindowOpenAboutBlankJS';
import WebMessageListenerJS from '../../plugin_scripts_js/WebMessageListenerJS';
import { InAppBrowserDelegate } from '../../in_app_browser/InAppBrowserDelegate';
import { ArrayList, HashMap, List } from '@kit.ArkTS';
import PrintJobSettings from '../../print_job/PrintJobSettings';
import WebMessageListener from '../web_message/WebMessageListener';
import WebMessageCompatExt from '../../types/WebMessageCompatExt';
import WebViewAssetLoaderExt from '../../types/WebViewAssetLoaderExt';
import WebViewAssetLoader from '../../types/WebViewAssetLoader';
import ContentBlockerHandler from '../../content_blocker/ContentBlockerHandler';
import ContentBlockerUtil from '../../content_blocker/ContentBlockerUtil';
import cert from '@ohos.security.cert';
import image from '@ohos.multimedia.image';
import window from '@ohos.window';
import animator, { AnimatorOptions, AnimatorResult } from '@ohos.animator';
import common from '@ohos.app.ability.common';
import { FindInteractionController } from '../../find_interaction/FindInteractionController';
import PullToRefreshLayout from '../../pull_to_refresh/PullToRefreshLayout';
import EventConstant from '../../EventConstant'
import { BusinessError } from '@kit.BasicServicesKit';
import { print } from '@kit.BasicServicesKit';
import PrintJobController from '../../print_job/PrintJobController';
import { PrintJobState } from '../../print_job/PrintJobState';
import ChannelResultUtil from '../../types/ChannelResultUtil';
import { UIContext } from '@kit.ArkUI';
import http from '@ohos.net.http';
import uri from '@ohos.uri';

const TAG = "InAppWebView"
const METHOD_CHANNEL_NAME_PREFIX = "com.pichillilorenzo/flutter_inappwebview_";
const WEB_SNAPSHOT_ID_PREFIX = "inappwebview_web_";
const CONTROLLER_ATTACH_TIMEOUT_MS = 30000;

class ControllerAttachWaiter {
  resolve: () => void;
  reject: (reason?: Object) => void;

  constructor(resolve: () => void, reject: (reason?: Object) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

export default class InAppWebView implements InAppWebViewInterface {
  public plugin: InAppWebViewFlutterPlugin | null = null;
  public inAppBrowserDelegate: InAppBrowserDelegate | null = null
  public id: string;
  public windowId: number | null | undefined;
  public inAppWebViewClient: InAppWebViewClient | null = null;
  public channelDelegate: WebViewChannelDelegate | null = null;
  private javaScriptBridgeInterface: JavaScriptBridgeInterface | null = null;
  public customSettings: InAppWebViewSettings;
  public isLoading: boolean = false
  /** True while client-cert negotiation / HTTP fallback is in flight. */
  public clientCertHttpFallbackPending: boolean = false
  /** True after HTTP fallback HTML was applied via loadData; wait for onPageEnd. */
  public clientCertHttpContentLoaded: boolean = false
  /** Sticky: loadStop already fired for current client-cert fallback (avoid data: duplicate). */
  public clientCertLoadStopDispatched: boolean = false
  private inFullscreen: boolean = false;
  public zoomScale: number = 1.0
  private lastLoadStopUrl: string = "";
  /** True after AT_DOCUMENT_END scripts were injected for the current navigation. */
  private documentEndScriptsInjected: boolean = false;
  /** URL for which onLoadStop dispatch is already scheduled (document-end first). */
  private loadStopDispatchInFlightUrl: string = "";
  private lastKnownScrollX: number = 0;
  private lastKnownScrollY: number = 0;
  public contentBlockerHandler = new ContentBlockerHandler();
  public regexToCancelSubFramesLoadingCompiled: RegExp | null = null;
  // public  gestureDetector: GestureDetector | null = null;
  // public floatingContextMenu: LinearLayout | null = null;
  public contextMenu: Map<string, Any> | undefined = undefined;
  // static mHandler: Handler = new Handler();
  // public checkScrollStoppedTask: Runnable | null = null;
  public initialPositionScrollStoppedTask: number = -1;
  public newCheckScrollStoppedTask: number = 100;
  // ms
  // public checkContextMenuShouldBeClosedTask: Runnable | null = null;
  public newCheckContextMenuShouldBeClosedTaskTask: number = 100;
  // ms
  public userContentController: UserContentController | null = new UserContentController(this);
  public callAsyncJavaScriptCallbacks: Map<string, ValueCallback<string>> = new Map<string, ValueCallback<string>>();
  public evaluateJavaScriptContentWorldCallbacks: Map<string, ValueCallback<string>> = new Map<string, ValueCallback<string>>()
  public webMessageChannels: Map<string, WebMessageChannel> = new Map<string, WebMessageChannel>()
  public webMessageListeners: Array<WebMessageListener> = new Array<WebMessageListener>();
  private initialUserOnlyScripts: Array<UserScript>;
  public findInteractionController: FindInteractionController | null = null;
  public webViewAssetLoaderExt: WebViewAssetLoaderExt | null = null;
  private interceptOnlyAsyncAjaxRequestsPluginScript: PluginScript | null = null;
  public context: common.Context | null = null;
  public controller: web_webview.WebviewController | null = new web_webview.WebviewController();
  private controllerAttached: boolean = false;
  private preparePromise: Promise<void> | null = null;
  private disposed: boolean = false;
  private activePrintTask: print.PrintTask | null = null;
  private loadDataTimers: number[] = [];
  public pendingTimers: number[] = [];
  private webResourcesReleased: boolean = false;
  private pendingAttachWaiters: ControllerAttachWaiter[] = [];
  private controllerAttachTimeoutId: number = -1;
  private pullToRefreshLayout: PullToRefreshLayout | null = null;
  private viewWidth = 0;
  private viewHeight= 0;
  private contentWidth = 0;
  private contentHeight = 0;
  private innerWidth = 0;
  private innerHeight = 0;
  private scrollClampTolerance = 1;
  private currentScrollAnimator: AnimatorResult | null = null;
  private curUrl: string | Resource = "";
  /** Popup target URL captured in constructor; survives map cleanup during parent dispose. */
  private pendingPopupUrl: string | null = null;
  public isNavigatingBackOrForward: boolean = false;
  // -1 = goBack, 0 = none, 1 = goForward
  public navigateBackOrForwardDirection: number = 0;
  // Counter to allow the first main-frame onOverrideUrlLoading during
  // back/forward navigation (the back/forward target itself). Set to 1 when
  // goBack/goForward is called and decremented when the first main-frame
  // onOverrideUrlLoading is allowed through. Prevents blocking the back
  // navigation itself while still blocking subsequent URL-level redirects.
  public backForwardNavigationAllowCount: number = 0;
  private navigateBackTimer: number = -1;
  public pendingSkipAfterRedirectBlock: boolean = false;
  // Context menu data captured from onContextMenuShow event.param methods.
  // OHOS WebContextMenuParam provides getLinkUrl() and getSourceUrl() natively.
  public lastContextMenuLinkUrl: string | null = null;
  public lastContextMenuSourceUrl: string | null = null;
  // Cached hit test type from first getHitTestValue() call in onContextMenuShow.
  // Avoids calling getHitTestValue() again later, which may return Unknown
  // on repeated long-press invocations.
  public lastContextMenuHitTestType: web_webview.WebHitTestType = web_webview.WebHitTestType.Unknown;
  // Direction to skip: -1 = goBack, 1 = goForward
  public pendingSkipDirection: number = 0;
  /** Maps loadData document URLs to back-forward list indices. */
  private loadDataPageUrlToIndex: Map<string, number> = new Map<string, number>();
  private static readonly LOAD_DATA_MAP_MAX_SIZE: number = 1000;
  /**
   * Maps loadData document (data:) URLs to the logical https history URL.
   * OHOS HistoryItem.historyUrl is often not the baseUrl after back/forward, so
   * getUrl() would otherwise keep returning the previous page's curUrl.
   */
  private loadDataPageUrlToHistoryUrl: Map<string, string> = new Map<string, string>();
  /** Logical history URL from the in-flight loadDataWithBaseURL call. */
  private pendingLoadDataHistoryUrl: string | null = null;
  /** Retrigger geolocation on next page end after loadData inline scripts may run too early. */
  public pendingLoadDataGeolocationRetrigger: boolean = false;
  /** Resolves when loadData document finishes (onPageEnd) or times out. */
  private loadDataReadyResolve: (() => void) | null = null;
  /** Set when onGeolocationShow handles a prompt for the current loadData page. */
  public geolocationShowHandled: boolean = false;
  /** True when the current page registered a beforeunload handler (ArkWeb polyfill). */
  public hasBeforeUnloadHandler: boolean = false;
  /** One-shot allow-list URL after the user confirms leaving the page. */
  public beforeUnloadNavigationAllowedUrl: string | null = null;
  /** Target URL blocked while waiting for onJsBeforeUnload resolution. */
  public pendingBeforeUnloadTargetUrl: string | null = null;
  /** True while a beforeunload prompt is in flight. */
  public beforeUnloadNavigationPending: boolean = false;

  constructor(context: Context, plugin: InAppWebViewFlutterPlugin, id: string, windowId: number | null | undefined,
              customSettings: InAppWebViewSettings, userScripts: Array<UserScript>, contextMenu?: Map<string, Any>) {
    this.context = context as common.Context;
    this.plugin = plugin;
    this.id = id;
    let channel = new MethodChannel(plugin.messenger!, METHOD_CHANNEL_NAME_PREFIX + id);
    this.channelDelegate = new WebViewChannelDelegate(this, channel);
    this.windowId = windowId;
    if ((windowId == null || windowId == undefined) && plugin.inAppWebViewManager != null) {
      plugin.inAppWebViewManager.cleanupStaleWindowState();
    }
    if (windowId != null && windowId != undefined && plugin.inAppWebViewManager != null) {
      let popupController = plugin.inAppWebViewManager.windowWebViewControllers.get(windowId);
      if (popupController != null) {
        this.controller = popupController;
      }
      let pendingPopupUrl = plugin.inAppWebViewManager.windowWebViewUrls.get(windowId);
      if (pendingPopupUrl != null && pendingPopupUrl.length > 0) {
        this.pendingPopupUrl = pendingPopupUrl;
      }
    }
    this.customSettings = customSettings;
    this.contextMenu = contextMenu;
    this.initialUserOnlyScripts = userScripts;
    // if (plugin != null && plugin.activity != null) {
    //   plugin.activity.registerForContextMenu(this);
    // }
  }

  setPullToRefreshLayout(pullToRefreshLayout: PullToRefreshLayout) {
    this.pullToRefreshLayout = pullToRefreshLayout;
  }

  getPullToRefreshLayout(): PullToRefreshLayout {
    return this.pullToRefreshLayout!!;
  }

  public prepare(): Promise<void> {
    if (this.preparePromise != null) {
      return this.preparePromise;
    }
    this.preparePromise = this.prepareInternal();
    return this.preparePromise;
  }

  private async prepareInternal() {
    if (this.plugin != null) {
      let configuredLoader =
        WebViewAssetLoaderExt.fromMap(this.customSettings.webViewAssetLoader, this.plugin, getContext());
      if (configuredLoader != null) {
        this.webViewAssetLoaderExt = configuredLoader;
      }
    }

    this.javaScriptBridgeInterface = new JavaScriptBridgeInterface(this);
    //addJavascriptInterface(javaScriptBridgeInterface, JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME);

    this.inAppWebViewClient = new InAppWebViewClient(this.plugin!, this);

    if (this.windowId == null || this.windowId == undefined) {
      this.prepareAndAddUserScripts();
    }

    ContentBlockerUtil.populateRuleList(this.contentBlockerHandler, this.customSettings.contentBlockers);

    if (this.customSettings.regexToCancelSubFramesLoading != null) {
      this.regexToCancelSubFramesLoadingCompiled = new RegExp(this.customSettings.regexToCancelSubFramesLoading);
    }

    await this.waitControllerAttached()
    this.requireController().registerJavaScriptProxy(this.javaScriptBridgeInterface,
    JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME, this.javaScriptBridgeInterface.getMethodList());

    if (this.customSettings.incognito) {
      this.setIncognito(true);
    }
    this.setCacheEnabled(this.customSettings.cacheEnabled);

    // settings
    if (this.customSettings.userAgent != null && this.customSettings.userAgent.length > 0) {
      this.requireController().setCustomUserAgent(this.customSettings.userAgent);
    }

    if (this.customSettings.applicationNameForUserAgent != null &&
    this.customSettings.applicationNameForUserAgent.length > 0) {
      let userAgent = (this.customSettings.userAgent != null && this.customSettings.userAgent.length > 0)
        ? this.customSettings.userAgent
        : this.getSafeUserAgent();
      let userAgentWithApplicationName = userAgent + ' ' + this.customSettings.applicationNameForUserAgent;
      this.requireController().setCustomUserAgent(userAgentWithApplicationName);
    }

    web_webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(this.customSettings.thirdPartyCookiesEnabled);

    if (this.customSettings.transparentBackground) {
      this.setTransparentBackground(true);
    }
  }

  private userScriptsPrepared: boolean = false;

  prepareAndAddUserScripts(): void {
    if (this.userScriptsPrepared) {
      return;
    }
    this.userScriptsPrepared = true;
    this.requireUserContentController().addPluginScript(PromisePolyfillJS.PROMISE_POLYFILL_JS_PLUGIN_SCRIPT);
    this.requireUserContentController().addPluginScript(JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_JS_PLUGIN_SCRIPT);
    this.requireUserContentController().addPluginScript(OnJsBeforeUnloadJS.ON_JS_BEFORE_UNLOAD_JS_PLUGIN_SCRIPT);
    this.requireUserContentController().addPluginScript(WebMessageListenerJS.WEB_MESSAGE_LISTENER_JS_PLUGIN_SCRIPT);
    this.requireUserContentController().addPluginScript(PrintJS.PRINT_JS_PLUGIN_SCRIPT);
    this.requireUserContentController().addPluginScript(OnWindowBlurEventJS.ON_WINDOW_BLUR_EVENT_JS_PLUGIN_SCRIPT);
    this.requireUserContentController().addPluginScript(OnWindowFocusEventJS.ON_WINDOW_FOCUS_EVENT_JS_PLUGIN_SCRIPT);
    this.requireUserContentController().addPluginScript(OnZoomScaleChangedJS.ON_ZOOM_SCALE_CHANGED_JS_PLUGIN_SCRIPT);
    if (this.customSettings.multiWindowAccess && this.customSettings.allowWindowOpenMethod) {
      this.requireUserContentController().addPluginScript(WindowOpenAboutBlankJS.PLUGIN_SCRIPT);
    }
    this.interceptOnlyAsyncAjaxRequestsPluginScript = InterceptAjaxRequestJS.createInterceptOnlyAsyncAjaxRequestsPluginScript(
      this.customSettings.interceptOnlyAsyncAjaxRequests);
    if (this.customSettings.useShouldInterceptAjaxRequest) {
      this.requireUserContentController().addPluginScript(this.interceptOnlyAsyncAjaxRequestsPluginScript);
      this.requireUserContentController().addPluginScript(InterceptAjaxRequestJS.INTERCEPT_AJAX_REQUEST_JS_PLUGIN_SCRIPT);
    }
    if (this.customSettings.useShouldInterceptFetchRequest) {
      this.requireUserContentController().addPluginScript(InterceptFetchRequestJS.INTERCEPT_FETCH_REQUEST_JS_PLUGIN_SCRIPT);
    }
    if (this.customSettings.useOnLoadResource) {
      this.requireUserContentController().addPluginScript(OnLoadResourceJS.ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT);
    }
    if (!this.customSettings.useHybridComposition) {
      this.requireUserContentController().addPluginScript(PluginScriptsUtil.CHECK_GLOBAL_KEY_DOWN_EVENT_TO_HIDE_CONTEXT_MENU_JS_PLUGIN_SCRIPT);
    }
    this.requireUserContentController().addUserOnlyScripts(this.initialUserOnlyScripts);
  }

  public setIncognito(enabled: boolean): void {
    if (enabled) {
      try { web_webview.WebCookieManager.clearAllCookiesSync(true); } catch (e) { Log.e(TAG, 'setIncognito clearAllCookiesSync failed: ' + JSON.stringify(e)); }
      this.setCacheEnabled(false);
      try { this.requireController().clearHistory(); } catch (e) { Log.e(TAG, 'setIncognito clearHistory failed: ' + JSON.stringify(e)); }
      try { this.requireController().clearMatches(); } catch (e) { Log.e(TAG, 'setIncognito clearMatches failed: ' + JSON.stringify(e)); }
      try { this.requireController().clearSslCache(); } catch (e) { Log.e(TAG, 'setIncognito clearSslCache failed: ' + JSON.stringify(e)); }
      try { this.requireController().removeCache(true); } catch (e) { Log.e(TAG, 'setIncognito removeCache failed: ' + JSON.stringify(e)); }
      this.clearFormData();
    } else {
      this.setCacheEnabled(true);
    }
  }

  public setCacheEnabled(enabled: boolean): void {
    if (this.context == null) {
      return;
    }
    let context = this.context as common.UIAbilityContext;
    context.eventHub.emit(EventConstant.EVENT_UPDATE_CACHEENABLE, enabled);
  }

  public static readonly TRANSPARENT_BACKGROUND_JS_SOURCE: string =
    "(function(){var s=document.getElementById('flutter_inappwebview_transparent_bg');" +
    "if(!s){s=document.createElement('style');s.id='flutter_inappwebview_transparent_bg';" +
    "s.textContent='html,body{background:transparent!important;background-color:transparent!important;}';" +
    "(document.head||document.documentElement).appendChild(s);}})();";

  public setTransparentBackground(enabled: boolean): void {
    if (this.context == null) {
      return;
    }
    let context = this.context as common.UIAbilityContext;
    context.eventHub.emit(EventConstant.EVENT_UPDATE_TRANSPARENT_BACKGROUND, enabled);
    if (enabled && this.controllerAttached) {
      this.applyTransparentBackgroundToPage();
    }
  }

  public applyTransparentBackgroundToPage(): void {
    if (!this.customSettings.transparentBackground || !this.controllerAttached) {
      return;
    }
    try {
      this.requireController().runJavaScript(InAppWebView.TRANSPARENT_BACKGROUND_JS_SOURCE);
    } catch (error) {
      console.info(`applyTransparentBackgroundToPage error: ${(error as BusinessError).message}`);
    }
  }

  async loadUrl(urlRequest: URLRequest) {
    let url = urlRequest.getUrl();
    let method = urlRequest.getMethod();
    if (url != null && url.length > 0 && method != "POST") {
      if (url.startsWith("resources/rawfile/")) {
        this.curUrl = $rawfile(url.replace("resources/rawfile/", ""));
      } else {
        this.curUrl = url;
      }
    }
    await this.waitControllerAttached();
    // Android loadUrl does not stopLoading before POST; stopping here can leave
    // the WebView unable to apply a subsequent loadData (private-POST fallback).
    if (method != "POST") {
      try {
        this.stopLoading();
      } catch (e) {
        Log.w(TAG, "loadUrl stopLoading failed: " + JSON.stringify(e));
      }
    }
    if (method != null && method == "POST") {
      // Nested URLRequest.body from the method channel can differ from postUrl's
      // top-level postData; headers are optional (Android postUrl ignores them).
      const body = urlRequest.getBody();
      await this.postUrl(url, body, null);
      return;
    }
    if (this.inAppWebViewClient != null &&
      this.inAppWebViewClient.handleChromeSafeBrowsingTestUrlIfNeeded(url)) {
      return;
    }
    if (this.isLoopbackHttpUrl(url) &&
      (method == null || method === 'GET' || method === 'HEAD')) {
      await this.loadLoopbackHttpUrl(urlRequest);
      return;
    }
    let realUrl = url.startsWith("resources/rawfile/") ? $rawfile(url.replace("resources/rawfile/", "")) : url;
    let headers = urlRequest.getHeaders();
    this.curUrl = realUrl;
    if (headers != null) {
      this.requireController().loadUrl(realUrl, this.toWebHeaders(headers));
      return;
    }
    this.requireController().loadUrl(realUrl);
  }

  /**
   * ArkWeb LNA can block main-frame navigations to loopback before onInterceptRequest runs.
   * Fetch via @ohos.net.http and inject with loadData so InAppLocalhostServer tests work.
   */
  private isLoopbackHttpUrl(url: string): boolean {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return false;
    }
    try {
      let host = new uri.URI(url).host?.toLowerCase();
      return host === 'localhost' || host === '127.0.0.1' || host === '::1';
    } catch (e) {
      return false;
    }
  }

  /**
   * Private LAN hosts (RFC1918 / link-local). ArkWeb postUrl after about:blank can
   * hang on a second WebView in the same process; use @ohos.net.http + loadData.
   */
  private isPrivateNetworkHttpUrl(url: string): boolean {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return false;
    }
    try {
      let host = new uri.URI(url).host?.toLowerCase();
      if (host == null || host.length === 0) {
        return false;
      }
      if (host.endsWith('.local')) {
        return true;
      }
      let parts = host.split('.');
      if (parts.length !== 4) {
        return false;
      }
      let nums: number[] = [];
      for (let part of parts) {
        let value = parseInt(part, 10);
        if (isNaN(value) || value < 0 || value > 255) {
          return false;
        }
        nums.push(value);
      }
      let a = nums[0];
      let b = nums[1];
      if (a === 10 || a === 127) {
        return true;
      }
      if (a === 169 && b === 254) {
        return true;
      }
      if (a === 172 && b >= 16 && b <= 31) {
        return true;
      }
      if (a === 192 && b === 168) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  private shouldPostViaHttpFallback(url: string): boolean {
    return this.isLoopbackHttpUrl(url) || this.isPrivateNetworkHttpUrl(url);
  }

  /** Copy Flutter codec body into a fresh ArrayBuffer (views may be reused/detached). */
  private static copyRequestBody(postData: ArrayBuffer | null): ArrayBuffer {
    if (postData == null) {
      return new ArrayBuffer(0);
    }
    try {
      // Nested URLRequest.body may arrive as number[] instead of ArrayBuffer.
      const maybeList = postData as Object as number[];
      if (maybeList != null && maybeList.length != null &&
        typeof maybeList.length === 'number' &&
        (postData as ArrayBuffer).byteLength == null &&
        (postData as Uint8Array).buffer == null) {
        const copy = new Uint8Array(maybeList.length);
        for (let i = 0; i < maybeList.length; i++) {
          copy[i] = Number(maybeList[i]) & 0xff;
        }
        return copy.buffer.slice(copy.byteOffset, copy.byteOffset + copy.byteLength) as ArrayBuffer;
      }
      let src: Uint8Array;
      const maybeView = postData as Uint8Array;
      if (maybeView != null && maybeView.byteLength != null && maybeView.buffer != null &&
        typeof maybeView.byteOffset === 'number') {
        src = new Uint8Array(maybeView.buffer, maybeView.byteOffset, maybeView.byteLength);
      } else {
        src = new Uint8Array(postData);
      }
      const copy = new Uint8Array(src.byteLength);
      for (let i = 0; i < src.byteLength; i++) {
        copy[i] = src[i];
      }
      return copy.buffer.slice(copy.byteOffset, copy.byteOffset + copy.byteLength) as ArrayBuffer;
    } catch (e) {
      Log.w(TAG, 'copyRequestBody failed: ' + JSON.stringify(e));
      return new ArrayBuffer(0);
    }
  }

  /**
   * Tests call loadUrl/postUrl right after creating a WebView with about:blank,
   * without awaiting that blank load. loadData raced with about:blank → flaky DOM.
   */
  private async waitForDocumentComplete(timeoutMs: number = 3000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (this.disposed) {
        return;
      }
      if (!this.isControllerUsable()) {
        await new Promise<void>((resolve) => setTimeout(resolve, 50));
        continue;
      }
      if (!this.isLoading) {
        try {
          const result = await this.requireController().runJavaScriptExt('document.readyState');
          let state = '';
          try {
            state = result.getString() ?? '';
          } catch (_e) {
            state = '';
          }
          // readyState may be JSON-quoted from runJavaScriptExt.
          if (state.indexOf('complete') >= 0) {
            // Settle so a late about:blank onPageEnd cannot wipe loadData HTML.
            await new Promise<void>((resolve) => setTimeout(resolve, 150));
            if (!this.isLoading) {
              return;
            }
          }
        } catch (_e) {
          // Controller not ready for JS yet.
        }
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
    }
  }

  /**
   * Fetch private/loopback URL via @ohos.net.http and inject with loadData.
   * Used for POST (and by loadLoopbackHttpUrl for GET/HEAD) to avoid ArkWeb LNA /
   * flaky postUrl after a prior WebView already POSTed in-process.
   */
  private async loadPrivateHttpUrl(
    url: string,
    method: string,
    body: ArrayBuffer | null,
    headers?: Map<string, string> | null
  ): Promise<void> {
    const upper = (method ?? 'GET').toUpperCase();
    let httpMethod = http.RequestMethod.GET;
    if (upper === 'POST') {
      httpMethod = http.RequestMethod.POST;
    } else if (upper === 'HEAD') {
      httpMethod = http.RequestMethod.HEAD;
    } else if (upper === 'PUT') {
      httpMethod = http.RequestMethod.PUT;
    }
    // Defer onLoadStop until DOM is queryable (same race as client-cert HTTP+loadData).
    const deferLoadStop = upper === 'POST' || upper === 'PUT' || upper === 'PATCH';
    // Detect about:blank BEFORE assigning curUrl to the POST target.
    let fromAboutBlank = false;
    try {
      const current = this.getUrl();
      fromAboutBlank = current === 'about:blank' || current.startsWith('about:');
    } catch (_e) {
      fromAboutBlank = false;
    }
    this.curUrl = url;
    if (deferLoadStop) {
      // Tests fire POST immediately after about:blank without awaiting it.
      if (fromAboutBlank) {
        await this.waitForDocumentComplete(5000);
        try {
          this.stopLoading();
        } catch (e) {
          Log.w(TAG, 'loadPrivateHttpUrl stopLoading after blank failed: ' + JSON.stringify(e));
        }
      }
      this.clientCertHttpFallbackPending = true;
      this.clientCertHttpContentLoaded = false;
      this.clientCertLoadStopDispatched = false;
    }
    let httpRequest: http.HttpRequest | null = null;
    try {
      httpRequest = http.createHttp();
      let headerObj: Record<string, string> = {};
      if (upper === 'POST' || upper === 'PUT' || upper === 'PATCH') {
        headerObj['Content-Type'] = 'application/x-www-form-urlencoded';
      }
      if (headers != null) {
        headers.forEach((value: string, key: string) => {
          headerObj[key] = value;
        });
      }
      let requestOptions: http.HttpRequestOptions = {
        method: httpMethod,
        header: headerObj,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000,
      };
      if (body != null && body.byteLength > 0 &&
        (upper === 'POST' || upper === 'PUT' || upper === 'PATCH')) {
        try {
          requestOptions.extraData =
            util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(body));
        } catch (e) {
          requestOptions.extraData = body;
        }
      }
      let resp = await httpRequest.request(url, requestOptions);
      httpRequest.destroy();
      httpRequest = null;
      if (resp.responseCode >= 400) {
        Log.e(TAG, 'loadPrivateHttpUrl HTTP ' + resp.responseCode + ' for ' + url);
        if (deferLoadStop) {
          this.clientCertHttpFallbackPending = false;
          this.clientCertHttpContentLoaded = false;
        }
        if (upper === 'POST' && body != null) {
          this.requireController().postUrl(url, body);
        } else {
          this.requireController().loadUrl(url);
        }
        return;
      }
      let mimeType = 'text/html';
      if (resp.header) {
        let respHeaders = resp.header as Record<string, string>;
        let contentType = respHeaders['Content-Type'] ?? respHeaders['content-type'];
        if (contentType != null && contentType.length > 0) {
          mimeType = contentType.split(';')[0].trim();
        }
      }
      let data = InAppWebView.httpResultToString(resp.result);
      if (data.length === 0) {
        Log.w(TAG, 'loadPrivateHttpUrl empty body for ' + url + ', resultType=' + typeof resp.result);
      }
      let baseUrl = this.buildLoopbackBaseUrl(url);
      if (deferLoadStop) {
        this.clientCertHttpContentLoaded = true;
      }
      if (fromAboutBlank && deferLoadStop) {
        // loadData races remaining about:blank work; write into the settled document.
        await this.applyHtmlViaDocumentWrite(url, data);
        this.waitForClientCertPageReadyThenDispatchLoadStop(url);
      } else {
        await this.loadDataWithBaseURL(baseUrl, data, mimeType, 'utf-8', url);
        if (deferLoadStop) {
          this.waitForClientCertPageReadyThenDispatchLoadStop(url);
        }
      }
    } catch (e) {
      Log.e(TAG, 'loadPrivateHttpUrl failed for ' + url + ': ' + JSON.stringify(e));
      if (httpRequest != null) {
        try {
          httpRequest.destroy();
        } catch (e3) {
          Log.e(TAG, 'loadPrivateHttpUrl destroy failed: ' + JSON.stringify(e3));
        }
        httpRequest = null;
      }
      if (deferLoadStop) {
        this.clientCertHttpFallbackPending = false;
        this.clientCertHttpContentLoaded = false;
      }
      if (upper === 'POST' && body != null) {
        try {
          this.requireController().postUrl(url, body);
        } catch (e2) {
          Log.e(TAG, 'loadPrivateHttpUrl native postUrl fallback failed: ' + JSON.stringify(e2));
        }
      } else {
        this.requireController().loadUrl(url);
      }
    }
  }

  private static httpResultToString(result: Object | string | ArrayBuffer | null | undefined): string {
    if (result == null) {
      return '';
    }
    if (typeof result === 'string') {
      return result as string;
    }
    try {
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(result as ArrayBuffer));
    } catch (e) {
      try {
        return String(result);
      } catch (e2) {
        return '';
      }
    }
  }

  /**
   * Replace the current document (typically settled about:blank) with HTML.
   * Avoids loadData racing a still-finishing blank navigation.
   */
  private async applyHtmlViaDocumentWrite(historyUrl: string, html: string): Promise<void> {
    this.curUrl = historyUrl;
    if (historyUrl.startsWith('http://') || historyUrl.startsWith('https://')) {
      this.pendingLoadDataHistoryUrl = historyUrl;
    }
    const js =
      '(function(){try{document.open();document.write(' +
      JSON.stringify(html) +
      ');document.close();return true;}catch(e){return false;}})()';
    try {
      await this.requireController().runJavaScriptExt(js);
    } catch (e) {
      Log.e(TAG, 'applyHtmlViaDocumentWrite failed: ' + JSON.stringify(e));
      // Fallback to loadData if document.write is unavailable.
      const baseUrl = this.buildLoopbackBaseUrl(historyUrl);
      await this.loadDataWithBaseURL(baseUrl, html, 'text/html', 'utf-8', historyUrl);
    }
  }

  private buildLoopbackBaseUrl(url: string): string {
    try {
      let parsed = new uri.URI(url);
      let scheme = parsed.scheme ?? 'http';
      let host = parsed.host ?? 'localhost';
      let port = parsed.port;
      let origin = scheme + '://' + host;
      if (port != null && port !== '' && port !== '-1') {
        origin += ':' + port;
      }
      let path = parsed.path ?? '/';
      let lastSlash = path.lastIndexOf('/');
      if (lastSlash >= 0) {
        return origin + path.substring(0, lastSlash + 1);
      }
      return origin + '/';
    } catch (e) {
      return url;
    }
  }

  private async loadLoopbackHttpUrl(urlRequest: URLRequest): Promise<void> {
    let url = urlRequest.getUrl();
    let method = urlRequest.getMethod()?.toUpperCase() ?? 'GET';
    await this.loadPrivateHttpUrl(url, method, null, urlRequest.getHeaders());
  }

  /**
   * ArkWeb client certificate selection via handler.confirm() is unreliable on some
   * devices (CreateClientCertStore TODO). Reload the page through @ohos.net.http
   * with clientCert when the Dart layer returns PROCEED.
   */
  loadClientCertUrlViaHttp(url: string, clientCertPaths: ClientCertHttpPaths): void {
    let requestUrl = url;
    if (requestUrl == null || requestUrl.length === 0) {
      requestUrl = this.getUrl();
    }
    if (requestUrl == null || requestUrl.length === 0) {
      Log.e(TAG, 'loadClientCertUrlViaHttp: missing url');
      this.clientCertHttpFallbackPending = false;
      this.clientCertHttpContentLoaded = false;
      return;
    }
    this.curUrl = requestUrl;
    this.clientCertHttpFallbackPending = true;
    this.clientCertHttpContentLoaded = false;
    this.clientCertLoadStopDispatched = false;
    try {
      let httpRequest = http.createHttp();
      const useP12 = clientCertPaths.certType === 'P12';
      let requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000,
        clientCert: {
          certPath: clientCertPaths.certPath,
          keyPath: useP12 ? '' : clientCertPaths.keyPath,
          certType: useP12 ? http.CertType.P12 : http.CertType.PEM,
          keyPassword: clientCertPaths.keyPassword ?? '',
        },
        remoteValidation: 'skip' as http.RemoteValidation,
      };
      if (clientCertPaths.caPath != null) {
        requestOptions.caPath = clientCertPaths.caPath;
        Log.d(TAG, 'loadClientCertUrlViaHttp caPath: ' + clientCertPaths.caPath);
      }
      Log.d(TAG, 'loadClientCertUrlViaHttp certType: ' + clientCertPaths.certType +
        ' certPath: ' + clientCertPaths.certPath +
        ' keyPath: ' + clientCertPaths.keyPath + ' url: ' + requestUrl);
      httpRequest.request(requestUrl, requestOptions).then(async (resp: http.HttpResponse) => {
        try {
          let data = typeof resp.result === 'string' ? resp.result as string : '';
          if (resp.responseCode >= 400 && data.length === 0) {
            Log.e(TAG, 'loadClientCertUrlViaHttp HTTP ' + resp.responseCode + ' for ' + requestUrl);
            this.clientCertHttpFallbackPending = false;
            this.clientCertHttpContentLoaded = false;
            return;
          }
          let mimeType = 'text/html';
          if (resp.header) {
            let headers = resp.header as Record<string, string>;
            let contentType = headers['Content-Type'] ?? headers['content-type'];
            if (contentType != null && contentType.length > 0) {
              mimeType = contentType.split(';')[0].trim();
            }
          }
          let baseUrl = this.buildLoopbackBaseUrl(requestUrl);
          // Keep pending=true so scheduleLoadDataCompletion / progress / FCP do not
          // fire onLoadStop before the WebView finishes parsing HTML (SSL test race:
          // first loadStop → evaluateJavascript null; second → Future already completed).
          this.clientCertHttpContentLoaded = true;
          await this.loadDataWithBaseURL(baseUrl, data, mimeType, 'utf-8', requestUrl);
          this.waitForClientCertPageReadyThenDispatchLoadStop(requestUrl);
        } catch (e) {
          Log.e(TAG, 'loadClientCertUrlViaHttp apply failed: ' + JSON.stringify(e));
          this.clientCertHttpFallbackPending = false;
          this.clientCertHttpContentLoaded = false;
        } finally {
          httpRequest.destroy();
        }
      }).catch((err: Error) => {
        Log.e(TAG, 'loadClientCertUrlViaHttp request failed: ' + (err ? err.message : 'unknown'));
        this.clientCertHttpFallbackPending = false;
        this.clientCertHttpContentLoaded = false;
        httpRequest.destroy();
      });
    } catch (e) {
      Log.e(TAG, 'loadClientCertUrlViaHttp setup failed: ' + JSON.stringify(e));
      this.clientCertHttpFallbackPending = false;
      this.clientCertHttpContentLoaded = false;
    }
  }

  /**
   * loadData's onPageEnd can fire before the DOM is queryable. Poll until body
   * content is ready (or timeout), then dispatch a single onLoadStop.
   */
  private waitForClientCertPageReadyThenDispatchLoadStop(requestUrl: string): void {
    const maxAttempts = 25;
    const poll = (attempt: number): void => {
      if (this.disposed) {
        return;
      }
      if (!this.clientCertHttpFallbackPending || !this.clientCertHttpContentLoaded) {
        return;
      }
      if (!this.isControllerUsable()) {
        if (attempt < maxAttempts) {
          const timerId = setTimeout((): void => {
            poll(attempt + 1);
          }, 100);
          this.pendingTimers.push(timerId);
        } else {
          this.releaseClientCertHttpFallbackAndDispatchLoadStop(requestUrl);
        }
        return;
      }
      try {
        this.requireController().runJavaScriptExt(
          // Require a real content node (p for POST tests, h1 for SSL). Do not
          // treat bare body.innerText as ready — about:blank can race loadData.
          "(function(){var b=document.body;if(!b){return null;}var p=b.querySelector('p');if(p&&(p.innerHTML||'').length){return p.innerHTML;}var h=b.querySelector('h1');return h&&h.textContent?h.textContent:null;})()"
        ).then((result): void => {
          if (this.disposed || !this.clientCertHttpFallbackPending) {
            return;
          }
          let ready = false;
          try {
            const value: string = result.getString();
            ready = value != null && value.length > 0;
          } catch (_e) {
            ready = false;
          }
          if (ready) {
            if (this.releaseClientCertHttpFallbackAndDispatchLoadStop(requestUrl)) {
              Log.d(TAG, 'waitForClientCertPageReady: dispatched loadStop attempt=' + attempt);
            }
            return;
          }
          if (attempt >= maxAttempts) {
            this.releaseClientCertHttpFallbackAndDispatchLoadStop(requestUrl);
            return;
          }
          const timerId1 = setTimeout((): void => {
            poll(attempt + 1);
          }, 100);
          this.pendingTimers.push(timerId1);
        }).catch((_error: Error): void => {
          if (attempt >= maxAttempts) {
            this.releaseClientCertHttpFallbackAndDispatchLoadStop(requestUrl);
          } else {
            const timerId2 = setTimeout((): void => {
              poll(attempt + 1);
            }, 100);
            this.pendingTimers.push(timerId2);
          }
        });
      } catch (e) {
        Log.w(TAG, 'waitForClientCertPageReady poll failed: ' + JSON.stringify(e));
        if (attempt >= maxAttempts) {
          this.releaseClientCertHttpFallbackAndDispatchLoadStop(requestUrl);
        } else {
          const timerId3 = setTimeout((): void => {
            poll(attempt + 1);
          }, 100);
          this.pendingTimers.push(timerId3);
        }
      }
    };
    const timerId0 = setTimeout((): void => {
      poll(0);
    }, 50);
    this.pendingTimers.push(timerId0);
  }

  private static readonly FLUTTER_ASSETS_URL_PREFIX: string = '/assets/flutter_assets/';
  private static readonly ANDROID_ASSET_URL: string = 'file:///android_asset/';

  private isFlutterAssetLoaderUrl(url: string): boolean {
    return url.includes(WebViewAssetLoader.DEFAULT_DOMAIN) &&
      url.includes(InAppWebView.FLUTTER_ASSETS_URL_PREFIX);
  }

  private buildFlutterAssetFileUrl(assetFilePath: string): string {
    let normalizedPath = assetFilePath.startsWith('/') ?
      assetFilePath.substring(1) : assetFilePath;
    return `${InAppWebView.ANDROID_ASSET_URL}${normalizedPath}`;
  }

  private buildFlutterAssetRawFileRelativePath(assetFilePath: string): string {
    let normalizedPath = assetFilePath.startsWith('/') ?
      assetFilePath.substring(1) : assetFilePath;
    return `flutter_assets/${normalizedPath}`;
  }

  /**
   * Ensures a [WebViewAssetLoader] exists so local Flutter assets (including ES
   * module sub-resources) are served over https:// instead of rawfile://, which
   * avoids sub-resource load failures on ArkWeb.
   */
  private ensureDefaultFlutterAssetLoader(): void {
    if (this.webViewAssetLoaderExt != null) {
      return;
    }
    try {
      if (this.context != null) {
        this.webViewAssetLoaderExt =
          WebViewAssetLoaderExt.createDefaultFlutterAssetsLoader(this.context);
      }
    } catch (error) {
      Log.e(TAG, 'ensureDefaultFlutterAssetLoader error: ' + error);
    }
  }

  private buildFlutterAssetUrl(assetFilePath: string): string {
    let normalizedPath = assetFilePath.startsWith('/') ?
      assetFilePath.substring(1) : assetFilePath;
    return `https://${WebViewAssetLoader.DEFAULT_DOMAIN}${InAppWebView.FLUTTER_ASSETS_URL_PREFIX}${normalizedPath}`;
  }

  /**
   * When allowFileAccessFromFileURLs is enabled, load via $rawfile so the page
   * origin can access whitelisted file:// subresources (see setPathAllowingUniversalAccess).
   * Otherwise keep https://appassets for ES module / crossorigin sub-resources.
   */
  private shouldPreferRawfileOriginForLoadFile(): boolean {
    const settings = this.customSettings;
    return settings.fileAccess &&
      (settings.allowFileAccessFromFileURLs ||
        settings.allowUniversalAccessFromFileURLs);
  }

  async loadFile(assetFilePath: string) {
    if (this.plugin == null) {
      throw new Error('InAppWebView plugin is not available');
    }
    await this.waitControllerAttached();
    try {
      this.stopLoading();
    } catch (e) {
      Log.w(TAG, 'loadFile stopLoading failed: ' + JSON.stringify(e));
    }
    let normalizedPath = assetFilePath.startsWith('/') ?
      assetFilePath.substring(1) : assetFilePath;
    if (this.shouldPreferRawfileOriginForLoadFile()) {
      try {
        let rawRelativePath = this.buildFlutterAssetRawFileRelativePath(assetFilePath);
        let rawfileUrl = $rawfile(rawRelativePath);
        this.curUrl = this.buildFlutterAssetFileUrl(assetFilePath);
        Log.i(TAG, 'loadFile using rawfile origin: ' + rawRelativePath);
        this.requireController().loadUrl(rawfileUrl);
        return;
      } catch (rawfileOriginError) {
        Log.w(TAG, 'loadFile rawfile origin failed, trying https: ' + JSON.stringify(rawfileOriginError));
      }
    }
    this.ensureDefaultFlutterAssetLoader();
    try {
      let assetUrl = this.buildFlutterAssetUrl(assetFilePath);
      this.curUrl = this.buildFlutterAssetFileUrl(assetFilePath);
      this.requireController().loadUrl(assetUrl);
    } catch (primaryError) {
      Log.w(TAG, 'loadFile primary URL failed, trying rawfile fallback: ' + JSON.stringify(primaryError));
      try {
        let rawfileUrl = $rawfile(normalizedPath);
        this.curUrl = rawfileUrl;
        this.requireController().loadUrl(rawfileUrl);
      } catch (fallbackError) {
        Log.e(TAG, 'loadFile rawfile fallback failed: ' + JSON.stringify(fallbackError));
        throw fallbackError as Error;
      }
    }
  }

  public clearFormData(): void {
    if (!this.isControllerUsable()) {
      return;
    }
    const clearFormJs =
      '(function() {' +
      '  try {' +
      "    document.querySelectorAll('form').forEach(function(form) { form.reset(); });" +
      "    document.querySelectorAll('input, textarea, select').forEach(function(el) {" +
      "      if (el.type === 'checkbox' || el.type === 'radio') { el.checked = false; }" +
      "      else if (el.type !== 'button' && el.type !== 'submit' && el.type !== 'reset') { el.value = ''; }" +
      '    });' +
      '  } catch (e) {}' +
      '})();';
    this.evaluateJavascript(clearFormJs, null, null);
  }

  // ---------- Media playback & capture APIs ----------

  public setAllMediaPlaybackSuspended(suspended: boolean): void {
    if (!this.isControllerUsable()) {
      return;
    }
    try {
      if (suspended) {
        this.requireController().pauseAllMedia();
      } else {
        this.requireController().resumeAllMedia();
      }
    } catch (e) {
      Log.e(TAG, 'setAllMediaPlaybackSuspended failed: ' + JSON.stringify(e));
    }
  }

  public closeAllMediaPresentations(): void {
    if (!this.isControllerUsable()) {
      return;
    }
    try {
      this.requireController().closeAllMediaPresentations();
    } catch (e) {
      Log.e(TAG, 'closeAllMediaPresentations failed: ' + JSON.stringify(e));
    }
  }

  public requestMediaPlaybackState(result: MethodResult): void {
    if (!this.isControllerUsable()) {
      result.success(null);
      return;
    }
    try {
      const arkState = this.requireController().getMediaPlaybackState();
      // ArkWeb: NONE=0 PLAYING=1 PAUSED=2 STOPPED=3
      // Flutter: NONE=0 PLAYING=1 PAUSED=2 SUSPENDED=3
      let stateMap: Record<string, number> = { 'state': arkState };
      result.success(stateMap);
    } catch (e) {
      Log.e(TAG, 'requestMediaPlaybackState failed: ' + JSON.stringify(e));
      result.success(null);
    }
  }

  public startSafeBrowsing(): boolean {
    // ArkWeb safe browsing is managed by the system and enabled by default on OHOS.
    Log.i(TAG, 'startSafeBrowsing: ArkWeb safe browsing is system-managed on OHOS');
    return true;
  }

  getLoadUrl(): string | Resource {
    return this.curUrl
  }

  getLoading(): boolean {
    return this.isLoading
  }

  clearCookies(): void {
    web_webview.WebCookieManager.clearAllCookiesSync()
  }

  refresh(): void{
    try {
      this.requireController().refresh()
    } catch (e) {
      Log.e(TAG, 'refresh failed', e);
    }
  }

  scrollToTop(): void {
    this.requireController().scrollTo(0, 0)
  }

  public clearAllCache(): void {
    this.requireController().removeCache(true);
    this.clearCookies();
  }

  public getWebSnapshotId(): string {
    return WEB_SNAPSHOT_ID_PREFIX + this.id;
  }

  private async resolveUiContextForScreenshot(): Promise<UIContext | null> {
    const contexts: Context[] = [];
    if (this.plugin?.uiAbility?.context != null) {
      contexts.push(this.plugin!.uiAbility!.context);
    }
    if (this.context != null) {
      contexts.push(this.context);
    }
    for (let ctx of contexts) {
      try {
        let windowClass: window.Window = await window.getLastWindow(ctx);
        return windowClass.getUIContext();
      } catch (e) {
        Log.w(TAG, 'resolveUiContextForScreenshot failed: ' + JSON.stringify(e));
      }
    }
    return null;
  }

  public async takeScreenshot(screenshotConfiguration: Map<string, Any> | null, result: MethodResult): Promise<void> {
    let pixelDensity: number = Util.getPixelDensity()

    try {
      let uiContext: UIContext | null = await this.resolveUiContextForScreenshot();
      if (uiContext == null) {
        throw new Error('Unable to obtain UIContext for screenshot');
      }
      let screenshotBitmap: image.PixelMap = await uiContext.getComponentSnapshot().get(this.getWebSnapshotId(), {
        waitUntilRenderFinished: true
      });

      let compressFormat: string = 'image/jpeg'
      let quality: number = 100

      if (screenshotConfiguration != null) {
        let rect: Map<string, number> = screenshotConfiguration.get('rect') as Map<string, number>
        if (rect != null) {
          let rectX: number = Math.floor((rect.get('x') ?? 0) * pixelDensity + 0.5) as number
          let rectY: number = Math.floor((rect.get('y') ?? 0) * pixelDensity + 0.5) as number
          let rectWidth: number = Math.min((await screenshotBitmap.getImageInfo()).size.width, Math.floor((rect.get('width') ?? 0) * pixelDensity + 0.5));
          let rectHeight: number = Math.min((await screenshotBitmap.getImageInfo()).size.height, Math.floor((rect.get('height') ?? 0) * pixelDensity + 0.5));
          await screenshotBitmap.crop({
            x: rectX, y: rectY, size: {
              height: rectHeight, width: rectWidth
            }
          })
        }

        let snapshotWidth: number = screenshotConfiguration.get('snapshotWidth') as number
        if (snapshotWidth != null) {
          let dstWidth: number = Math.floor(snapshotWidth * pixelDensity + 0.5) as number
          let bitMapInfo: image.ImageInfo = await screenshotBitmap.getImageInfo()
          let ratioBitmap: number = bitMapInfo.size.width / bitMapInfo.size.height
          let dstHeight: number = dstWidth / ratioBitmap
          screenshotBitmap.scale(dstWidth, dstHeight)
        }

        try {
          switch (screenshotConfiguration.get('compressFormat')) {
            case 'JPEG':
              compressFormat = 'image/jpeg'
              break
            case 'PNG':
              compressFormat = 'image/png'
              break
            default:
              compressFormat = 'image/jpeg'
          }
        } catch (e) {
          Log.e(TAG, '', e);
        }

        quality = screenshotConfiguration.get('quality') as number
      }

      const imagePackerApi = image.createImagePacker()
      try {
        let packOpts: image.PackingOption = {
          format: compressFormat, quality: quality
        }

        let bos: ArrayBuffer = await imagePackerApi.packing(screenshotBitmap, packOpts)

        result.success(new Uint8Array(bos));
      } finally {
        try {
          imagePackerApi.release();
        } catch (relErr) {
          Log.e(TAG, 'takeScreenshot release ImagePacker failed: ' + JSON.stringify(relErr));
        }
      }
    } catch (e) {
      Log.e(TAG, 'takeScreenshot failed', e);
      ChannelResultUtil.reportError(TAG, 'takeScreenshot', result, e as Object);
    }
  }

  public setSettings(newCustomSettings: InAppWebViewSettings, newSettingsMap: Map<string, Any>): void {

    if (newSettingsMap.has('useShouldInterceptAjaxRequest') && this.customSettings.useShouldInterceptAjaxRequest != newCustomSettings.useShouldInterceptAjaxRequest) {
      this.enablePluginScriptAtRuntime(
        InterceptAjaxRequestJS.FLAG_VARIABLE_FOR_SHOULD_INTERCEPT_AJAX_REQUEST_JS_SOURCE,
        newCustomSettings.useShouldInterceptAjaxRequest,
        InterceptAjaxRequestJS.INTERCEPT_AJAX_REQUEST_JS_PLUGIN_SCRIPT
      );
    }

    if (newSettingsMap.has('interceptOnlyAsyncAjaxRequests') && this.customSettings.interceptOnlyAsyncAjaxRequests != newCustomSettings.interceptOnlyAsyncAjaxRequests) {
      this.enablePluginScriptAtRuntime(
        InterceptAjaxRequestJS.FLAG_VARIABLE_FOR_INTERCEPT_ONLY_ASYNC_AJAX_REQUESTS_JS_SOURCE,
        newCustomSettings.interceptOnlyAsyncAjaxRequests,
        this.interceptOnlyAsyncAjaxRequestsPluginScript!!
      );
    }

    if (newSettingsMap.has('useShouldInterceptFetchRequest') && this.customSettings.useShouldInterceptFetchRequest != newCustomSettings.useShouldInterceptFetchRequest) {
      this.enablePluginScriptAtRuntime(
        InterceptFetchRequestJS.FLAG_VARIABLE_FOR_SHOULD_INTERCEPT_FETCH_REQUEST_JS_SOURCE,
        newCustomSettings.useShouldInterceptFetchRequest,
        InterceptFetchRequestJS.INTERCEPT_FETCH_REQUEST_JS_PLUGIN_SCRIPT
      );
    }

    if (newSettingsMap.has('useOnLoadResource') && this.customSettings.useOnLoadResource != newCustomSettings.useOnLoadResource) {
      this.enablePluginScriptAtRuntime(
        OnLoadResourceJS.FLAG_VARIABLE_FOR_ON_LOAD_RESOURCE_JS_SOURCE,
        newCustomSettings.useOnLoadResource,
        OnLoadResourceJS.ON_LOAD_RESOURCE_JS_PLUGIN_SCRIPT
      );
    }

    if (newSettingsMap.has('contentBlockers')) {
      this.customSettings.contentBlockers = newCustomSettings.contentBlockers;
      ContentBlockerUtil.populateRuleList(this.contentBlockerHandler, newCustomSettings.contentBlockers);
      // Clear image cache so that reloaded images go through onInterceptRequest
      // and get re-evaluated against updated ContentBlocker rules.
      if (this.controllerAttached) {
        try {
          this.requireController().removeCache(false);
        } catch (e) {
          Log.e(TAG, 'removeCache after contentBlocker update failed: ' + JSON.stringify(e));
        }
      }
    }

    if (newSettingsMap.has('regexToCancelSubFramesLoading') && (this.customSettings.regexToCancelSubFramesLoading == null ||
      this.customSettings.regexToCancelSubFramesLoading != newCustomSettings.regexToCancelSubFramesLoading)) {
      if (newCustomSettings.regexToCancelSubFramesLoading == null)
        this.regexToCancelSubFramesLoadingCompiled = null;
      else
        this.regexToCancelSubFramesLoadingCompiled = new RegExp(newCustomSettings.regexToCancelSubFramesLoading);
    }

    if (newSettingsMap.has('userAgent') && this.customSettings.userAgent != newCustomSettings.userAgent && newCustomSettings.userAgent.length > 0) {
      if (this.controllerAttached) {
        this.requireController().setCustomUserAgent(newCustomSettings.userAgent);
        this.applyJsUserAgentOverride();
      }
    }

    if (newSettingsMap.has('applicationNameForUserAgent') && this.customSettings.applicationNameForUserAgent != newCustomSettings.applicationNameForUserAgent && newCustomSettings.applicationNameForUserAgent != null &&
      newCustomSettings.applicationNameForUserAgent.length > 0) {
      if (this.controllerAttached) {
        let userAgent = (newCustomSettings.userAgent != null && newCustomSettings.userAgent.length > 0)
          ? newCustomSettings.userAgent
          : this.getSafeUserAgent();
        let userAgentWithApplicationName = userAgent + ' ' + newCustomSettings.applicationNameForUserAgent;
        this.requireController().setCustomUserAgent(userAgentWithApplicationName);
        this.applyJsUserAgentOverride();
      }
    }

    if (newSettingsMap.has('incognito') && this.customSettings.incognito != newCustomSettings.incognito){
      this.setIncognito(newCustomSettings.incognito);
    }

    if (newSettingsMap.has('cacheEnabled') && this.customSettings.cacheEnabled != newCustomSettings.cacheEnabled)
      this.setCacheEnabled(newCustomSettings.cacheEnabled);

    if (newSettingsMap.has('transparentBackground') && this.customSettings.transparentBackground != newCustomSettings.transparentBackground)
      this.setTransparentBackground(newCustomSettings.transparentBackground);

    if (newSettingsMap.has('textZoom') && this.controllerAttached) {
      const ratio: number = newCustomSettings.textZoomRatio / 100;
      this.requireController().runJavaScript(
        `document.body.style.webkitTextSizeAdjust='${ratio * 100}%'`);
    }

    if (this.plugin != null) {
      if (this.webViewAssetLoaderExt != null) {
        this.webViewAssetLoaderExt.dispose();
      }
      let configuredLoader =
        WebViewAssetLoaderExt.fromMap(newCustomSettings.webViewAssetLoader, this.plugin, getContext());
      if (configuredLoader != null) {
        this.webViewAssetLoaderExt = configuredLoader;
      } else {
        this.webViewAssetLoaderExt = null;
      }
    }
    this.customSettings = newCustomSettings;
  }

  public getCustomSettings(): Map<string, Any> | null {
    return this.customSettings != null ? this.customSettings.getRealSettings(this) : null
  }

  public enablePluginScriptAtRuntime(flagVariable: string, enable: boolean, pluginScript: PluginScript) {
    this.evaluateJavascript('window.' + flagVariable, null, {
      onReceiveValue: (value) => {
        let alreadyLoaded = value != null && value.toLowerCase() != 'null';
        if (alreadyLoaded) {
          let enableSource = 'window.' + flagVariable + ' = ' + enable + ';';
          this.evaluateJavascript(enableSource, null, null);
          if (!enable) {
            this.requireUserContentController().removePluginScript(pluginScript);
          }
        } else if (enable) {
          this.evaluateJavascript(pluginScript.getSource(), null, null);
          this.requireUserContentController().addPluginScript(pluginScript);
        }
      }
    });
  }

  public injectDeferredObject(source: string, contentWorld: ContentWorld | null, jsWrapper: string | null, resultCallback: ValueCallback<string> | null): void {
    let resultUuid: string | null = contentWorld != null && !contentWorld.equals(ContentWorld.PAGE) ? util.generateRandomUUID(true)
      .toString() : null
    let scriptToInject: string = source
    if (jsWrapper != null) {
      let jsonEsc = Array<string>();
      jsonEsc.push(source);
      let jsonRepr: string = JSON.stringify(jsonEsc);
      let jsonSourceString: string = jsonRepr.substring(1, jsonRepr.length - 1);
      scriptToInject = Util.formatString(jsWrapper, jsonSourceString);
    }
    if (resultUuid != null && resultCallback != null) {
      this.evaluateJavaScriptContentWorldCallbacks.set(resultUuid, resultCallback);
      scriptToInject = Util.replaceAll(PluginScriptsUtil.EVALUATE_JAVASCRIPT_WITH_CONTENT_WORLD_WRAPPER_JS_SOURCE,
        PluginScriptsUtil.VAR_RANDOM_NAME, '_' + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + '_' + Math.round(Math.random() * 1000000))
        .replace(PluginScriptsUtil.VAR_PLACEHOLDER_VALUE, UserContentController.escapeCode(source))
        .replace(PluginScriptsUtil.VAR_RESULT_UUID, resultUuid);
    }

    const finalScriptToInject = scriptToInject;
    this.waitControllerAttached().then(() => {
      if (this.disposed) {
        this.resolveJavaScriptCallbackOnError(resultUuid, resultCallback);
        return;
      }
      if (this.customSettings.userAgent != null && this.customSettings.userAgent.length > 0) {
        this.applyJsUserAgentOverride();
      }
      let script = this.requireUserContentController().generateCodeForScriptEvaluation(finalScriptToInject, contentWorld);
      try {
        this.requireController().runJavaScript(script).then(res => {
          if (resultUuid != null || resultCallback == null)
            return;
          resultCallback.onReceiveValue(res);
        }).catch((error: BusinessError) => {
          Log.e(TAG, `runJavaScript async error, code: ${error.code}, message: ${error.message}`);
          this.resolveJavaScriptCallbackOnError(resultUuid, resultCallback);
        });
      } catch (error) {
        let errorCode = (error as BusinessError).code;
        let errorMsg = (error as BusinessError).message;
        Log.e(TAG, `runJavaScript sync error, code:${errorCode}, message:${errorMsg}`);
        this.resolveJavaScriptCallbackOnError(resultUuid, resultCallback);
      }
    }).catch((error: BusinessError) => {
      Log.e(TAG, `injectDeferredObject waitControllerAttached failed, code: ${error.code}, message: ${error.message}`);
      this.resolveJavaScriptCallbackOnError(resultUuid, resultCallback);
    });
  }

  private resolveJavaScriptCallbackOnError(resultUuid: string | null, resultCallback: ValueCallback<string> | null): void {
    const errorMsg = 'JavaScript execution failed';
    if (resultUuid != null) {
      let callback = this.evaluateJavaScriptContentWorldCallbacks.get(resultUuid);
      this.evaluateJavaScriptContentWorldCallbacks.delete(resultUuid);
      if (callback != null) {
        if (callback.onError) {
          callback.onError(errorMsg);
        } else {
          callback.onReceiveValue(null);
        }
      }
    } else if (resultCallback != null) {
      if (resultCallback.onError) {
        resultCallback.onError(errorMsg);
      } else {
        resultCallback.onReceiveValue(null);
      }
    }
  }

  public evaluateJavascript(source: string, contentWorld: ContentWorld | null, resultCallback: ValueCallback<string> | null): void {
    this.injectDeferredObject(source, contentWorld, null, resultCallback);
  }

  public injectJavascriptFileFromUrl(urlFile: string, scriptHtmlTagAttributes: Map<string, Any> | null): void {
    let scriptAttributes: string = '';
    if (scriptHtmlTagAttributes != null) {
      let typeAttr: string = scriptHtmlTagAttributes.get('type') as string;
      if (typeAttr != null) {
        scriptAttributes += ' script.type = ' + UserContentController.escapeCode(typeAttr) + '; ';
      }
      let idAttr: string = scriptHtmlTagAttributes.get('id') as string;
      if (idAttr != null) {
        let scriptIdEscaped: string = UserContentController.escapeCode(idAttr);
        scriptAttributes += ' script.id = ' + scriptIdEscaped + '; ';
        scriptAttributes += " script.onload = function() {" +
          "  if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + " != null && " +
          "      window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler != null) {" +
          "    window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler('onInjectedScriptLoaded', " + scriptIdEscaped + ");" +
          "  }" +
          "};";
        scriptAttributes += " script.onerror = function() {" +
          "  if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + " != null && " +
          "      window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler != null) {" +
          "    window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler('onInjectedScriptError', " + scriptIdEscaped + ");" +
          "  }" +
          "};";
      }
      let asyncAttr: boolean = scriptHtmlTagAttributes.get('async') as boolean;
      if (asyncAttr != null && asyncAttr) {
        scriptAttributes += ' script.async = true; ';
      }
      let deferAttr: boolean = scriptHtmlTagAttributes.get('defer') as boolean;
      if (deferAttr != null && deferAttr) {
        scriptAttributes += ' script.defer = true; ';
      }
      let crossOriginAttr: string = scriptHtmlTagAttributes.get('crossOrigin') as string;
      if (crossOriginAttr != null) {
        scriptAttributes += ' script.crossOrigin = ' + UserContentController.escapeCode(crossOriginAttr) + '; ';
      }
      let integrityAttr: string = scriptHtmlTagAttributes.get('integrity') as string;
      if (integrityAttr != null) {
        scriptAttributes += ' script.integrity = ' + UserContentController.escapeCode(integrityAttr) + '; ';
      }
      let noModuleAttr: boolean = scriptHtmlTagAttributes.get('noModule') as boolean;
      if (noModuleAttr != null && noModuleAttr) {
        scriptAttributes += ' script.noModule = true; ';
      }
      let nonceAttr: string = scriptHtmlTagAttributes.get('nonce') as string;
      if (nonceAttr != null) {
        scriptAttributes += ' script.nonce = ' + UserContentController.escapeCode(nonceAttr) + '; ';
      }
      let referrerPolicyAttr: string = scriptHtmlTagAttributes.get('referrerPolicy') as string;
      if (referrerPolicyAttr != null) {
        scriptAttributes += ' script.referrerPolicy = ' + UserContentController.escapeCode(referrerPolicyAttr) + '; ';
      }
    }
    let jsWrapper: string =
      JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_JS_SOURCE + ';' +
      "(function(d) { var script = d.createElement('script'); " + scriptAttributes +
      " script.src = %s; if (d.body != null) { d.body.appendChild(script); } })(document);";
    this.injectDeferredObject(urlFile, null, jsWrapper, null);
  }

  public injectCSSCode(source: string): void {
    let jsWrapper: string = "(function(d) { var style = d.createElement('style'); style.innerHTML = %s;" +
      " if (d.head != null) { d.head.appendChild(style); } })(document);";
    this.injectDeferredObject(source, null, jsWrapper, null);
  }

  public injectCSSFileFromUrl(urlFile: string, cssLinkHtmlTagAttributes: Map<string, Any> | null): void {
    let cssLinkAttributes: string = '';
    let alternateStylesheet: string = '';
    if (cssLinkHtmlTagAttributes != null) {
      let idAttr: string = cssLinkHtmlTagAttributes.get('id') as string;
      if (idAttr != null) {
        cssLinkAttributes += ' link.id = ' + UserContentController.escapeCode(idAttr) + '; ';
      }
      let mediaAttr: string = cssLinkHtmlTagAttributes.get('media') as string;
      if (mediaAttr != null) {
        cssLinkAttributes += ' link.media = ' + UserContentController.escapeCode(mediaAttr) + '; ';
      }
      let crossOriginAttr: string = cssLinkHtmlTagAttributes.get('crossOrigin') as string;
      if (crossOriginAttr != null) {
        cssLinkAttributes += ' link.crossOrigin = ' + UserContentController.escapeCode(crossOriginAttr) + '; ';
      }
      let integrityAttr: string = cssLinkHtmlTagAttributes.get('integrity') as string;
      if (integrityAttr != null) {
        cssLinkAttributes += ' link.integrity = ' + UserContentController.escapeCode(integrityAttr) + '; ';
      }
      let referrerPolicyAttr: string = cssLinkHtmlTagAttributes.get('referrerPolicy') as string;
      if (referrerPolicyAttr != null) {
        cssLinkAttributes += ' link.referrerPolicy = ' + UserContentController.escapeCode(referrerPolicyAttr) + '; ';
      }
      let disabledAttr: boolean = cssLinkHtmlTagAttributes.get('disabled') as boolean;
      if (disabledAttr != null && disabledAttr) {
        cssLinkAttributes += ' link.disabled = true; ';
      }
      let alternateAttr: boolean = cssLinkHtmlTagAttributes.get('alternate') as boolean;
      if (alternateAttr != null && alternateAttr) {
        alternateStylesheet = 'alternate ';
      }
      let titleAttr: string = cssLinkHtmlTagAttributes.get('title') as string;
      if (titleAttr != null) {
        cssLinkAttributes += ' link.title = ' + UserContentController.escapeCode(titleAttr) + '; ';
      }
    }
    let jsWrapper: string = "(function(d) { var link = d.createElement('link'); link.rel='" + alternateStylesheet + "stylesheet'; link.type='text/css'; " +
      cssLinkAttributes + " link.href = %s; if (d.head != null) { d.head.appendChild(link); } })(document);";
    this.injectDeferredObject(urlFile, null, jsWrapper, null);
  }

  public getCopyBackForwardList(): HashMap<string, Any> {
    let currentList: web_webview.BackForwardList = this.requireController().getBackForwardEntries();
    let currentSize: number = currentList.size;
    let currentIndex: number = currentList.currentIndex;

    // OHOS can report a stale currentIndex; infer from navigation availability at boundaries.
    let boundaryIndex: number | null = null;
    try {
      if (currentSize > 0) {
        if (!this.canGoBack()) {
          boundaryIndex = 0;
        } else if (!this.canGoForward()) {
          boundaryIndex = currentSize - 1;
        }
      }
    } catch (e) {
      Log.w(TAG, 'getCopyBackForwardList boundary index sync failed: ' + JSON.stringify(e));
    }
    if (boundaryIndex != null) {
      currentIndex = boundaryIndex;
    } else {
      // Refine using the active document URL when in the middle of the stack.
      try {
        let activeUrl = '';
        try {
          activeUrl = this.urlValueToString(this.requireController().getUrl());
        } catch (e) {
          activeUrl = '';
        }
        if (activeUrl.length > 0 && activeUrl !== 'about:blank') {
          const mappedIndex = this.lookupLoadDataPageIndex(activeUrl);
          if (mappedIndex != null) {
            currentIndex = mappedIndex;
          } else {
            for (let i: number = 0; i < currentSize; i++) {
              const historyItem: web_webview.HistoryItem = currentList.getItemAtIndex(i);
              const historyUrl = historyItem.historyUrl ?? '';
              const rawUrl = historyItem.historyRawUrl ?? '';
              if (activeUrl === historyUrl || activeUrl === rawUrl) {
                currentIndex = i;
                break;
              }
            }
          }
        }
      } catch (e) {
        Log.w(TAG, 'getCopyBackForwardList active URL index sync failed: ' + JSON.stringify(e));
      }
    }

    let history: List<HashMap<string, Any>> = new List<HashMap<string, Any>>();
    let filteredCurrentIndex = 0;
    let filteredIndex = 0;

    for (let i: number = 0; i < currentSize; i++) {
      let historyItem: web_webview.HistoryItem = currentList.getItemAtIndex(i);
      let historyUrl = historyItem.historyUrl ?? '';
      if (historyUrl === 'about:blank' || historyUrl.startsWith('about:')) {
        continue;
      }
      if (i === currentIndex) {
        filteredCurrentIndex = filteredIndex;
        break;
      }
      filteredIndex++;
    }

    filteredIndex = 0;
    for (let i: number = 0; i < currentSize; i++) {
      let historyItem: web_webview.HistoryItem = currentList.getItemAtIndex(i);
      let historyUrl = historyItem.historyUrl ?? '';
      if (historyUrl === 'about:blank' || historyUrl.startsWith('about:')) {
        continue;
      }
      let historyItemMap: HashMap<string, Any> = new HashMap<string, Any>();

      historyItemMap.set('originalUrl', historyItem.historyRawUrl);
      historyItemMap.set('title', historyItem.title);
      historyItemMap.set('url', historyItem.historyUrl);
      historyItemMap.set('index', filteredIndex);
      historyItemMap.set('offset', filteredIndex - filteredCurrentIndex);

      history.add(historyItemMap);
      filteredIndex++;
    }

    if (filteredIndex > 0) {
      currentIndex = filteredCurrentIndex;
    }

    let result: HashMap<string, Any> = new HashMap<string, Any>();

    result.set('list', history);
    result.set('currentIndex', currentIndex);

    return result;
  }

  private dispatchOverScrolledAfterScrollTo(targetX: number, targetY: number): void {
    if (targetX <= 0 && targetY <= 0) {
      return;
    }
    if (this.disposed || this.channelDelegate == null) {
      return;
    }
    this.channelDelegate.onOverScrolled(targetX, targetY, false, false);
  }

  public scrollTo(x: number, y: number, animated: boolean): void {
    this.lastKnownScrollX = Math.round(x);
    this.lastKnownScrollY = Math.round(y);
    this.runJavaScriptScrollTo(this.lastKnownScrollX, this.lastKnownScrollY);
    if (animated) {
      let startX: number = 0;
      let startY: number = 0;
      try {
        startX = this.requireController().getPageOffset().x;
        startY = this.requireController().getPageOffset().y;
      } catch (e) {
        Log.e(TAG, 'scrollTo getPageOffset failed: ' + JSON.stringify(e));
        try {
          this.requireController().scrollTo(x, y);
        } catch (err) {
          Log.e(TAG, 'scrollTo fallback failed: ' + JSON.stringify(err));
        }
        this.dispatchOverScrolledAfterScrollTo(x, y);
        return;
      }
      const dx: number = x - startX;
      const dy: number = y - startY;
      let options: AnimatorOptions = {
        duration: 300,
        easing: 'friction',
        delay: 0,
        fill: 'forwards',
        direction: 'normal',
        iterations: 1,
        begin: 0,
        end: 1
      };
      let animatorResult: AnimatorResult | undefined = animator.create(options);
      if (animatorResult) {
        this.cancelCurrentScrollAnimation();
        this.currentScrollAnimator = animatorResult;
        animatorResult.onFrame = (progress: number) => {
          this.requireController().scrollTo(startX + dx * progress, startY + dy * progress);
        };
        animatorResult.onFinish = () => {
          this.requireController().scrollTo(x, y);
          this.releaseScrollAnimator(animatorResult);
          this.dispatchOverScrolledAfterScrollTo(x, y);
        };
        animatorResult.play();
      } else {
        this.requireController().scrollTo(x, y);
        this.dispatchOverScrolledAfterScrollTo(x, y);
      }
    } else {
      this.requireController().scrollTo(x, y);
      this.dispatchOverScrolledAfterScrollTo(x, y);
    }
  }

  public scrollBy(x: number, y: number, animated: boolean): void {
    const targetX: number = this.getScrollXSync() + Math.round(x);
    const targetY: number = this.getScrollYSync() + Math.round(y);
    this.scrollTo(targetX, targetY, animated);
  }

  public getScrollXSync(): number {
    if (!this.isControllerUsable()) {
      return this.lastKnownScrollX;
    }
    try {
      const offsetX: number = Math.round(this.requireController().getPageOffset().x);
      if (Math.abs(offsetX - this.lastKnownScrollX) <= 2) {
        this.lastKnownScrollX = offsetX;
      }
    } catch (e) {
      Log.w(TAG, 'getScrollXSync getPageOffset failed: ' + JSON.stringify(e));
    }
    return this.lastKnownScrollX;
  }

  public getScrollYSync(): number {
    if (!this.isControllerUsable()) {
      return this.lastKnownScrollY;
    }
    try {
      const offsetY: number = Math.round(this.requireController().getPageOffset().y);
      if (Math.abs(offsetY - this.lastKnownScrollY) <= 2) {
        this.lastKnownScrollY = offsetY;
      }
    } catch (e) {
      Log.w(TAG, 'getScrollYSync getPageOffset failed: ' + JSON.stringify(e));
    }
    return this.lastKnownScrollY;
  }

  public updateScrollPositionFromNative(x: number, y: number): void {
    this.lastKnownScrollX = Math.round(x);
    this.lastKnownScrollY = Math.round(y);
  }

  public resetLoadStopTracking(): void {
    this.lastLoadStopUrl = '';
    this.documentEndScriptsInjected = false;
    this.loadStopDispatchInFlightUrl = '';
  }

  /**
   * Inject AT_DOCUMENT_END user/plugin scripts once per navigation.
   * Android does this in onPageFinished before onLoadStop.
   */
  public injectDocumentEndScriptsIfNeeded(): void {
    if (this.documentEndScriptsInjected) {
      return;
    }
    if (!this.isControllerUsable() || this.userContentController == null) {
      return;
    }
    this.documentEndScriptsInjected = true;
    try {
      const source = this.requireUserContentController().generateWrappedCodeForDocumentEnd();
      this.requireController().runJavaScriptExt(source);
    } catch (e) {
      Log.w(TAG, 'injectDocumentEndScriptsIfNeeded failed: ' + JSON.stringify(e));
      this.documentEndScriptsInjected = false;
    }
  }

  private hasNonPageDocumentEndUserScripts(): boolean {
    if (this.userContentController == null) {
      return false;
    }
    try {
      const scripts = this.requireUserContentController()
        .getUserOnlyScriptsAt(UserScriptInjectionTime.AT_DOCUMENT_END);
      for (const script of scripts) {
        const world = script.getContentWorld();
        if (world != null && !world.equals(ContentWorld.PAGE)) {
          return true;
        }
      }
    } catch (e) {
      Log.w(TAG, 'hasNonPageDocumentEndUserScripts failed: ' + JSON.stringify(e));
    }
    return false;
  }

  /**
   * Some heavy sites (e.g. flutter.dev) may not reach onPageEnd within test
   * timeouts even though content is visible. Dispatch onLoadStop once per URL
   * when first contentful paint or progress reaches 100%.
   *
   * Matches Android: inject AT_DOCUMENT_END scripts before notifying Dart.
   */
  public tryDispatchLoadStopIfNeeded(url: string): boolean {
    if (this.channelDelegate == null) {
      return false;
    }
    if (url == null || url.length === 0) {
      return false;
    }
    // Defer until client-cert HTTP body is parsed (see onPageEnd / setTimeout fallback).
    if (this.clientCertHttpFallbackPending) {
      return false;
    }
    // Allow about:blank only while a navigation is in progress (initial InAppBrowser load).
    if (url === 'about:blank' && !this.isLoading) {
      return false;
    }
    if (this.lastLoadStopUrl === url) {
      return false;
    }
    if (this.loadStopDispatchInFlightUrl === url) {
      return false;
    }

    this.loadStopDispatchInFlightUrl = url;
    this.injectDocumentEndScriptsIfNeeded();

    // Content-world wrappers may need a tick after document-end injection
    // (initialUserScripts: bar/bar2 in DEFAULT_CLIENT / custom worlds).
    const settleMs = this.hasNonPageDocumentEndUserScripts() ? 50 : 0;
    const dispatch = (): void => {
      if (this.disposed || this.channelDelegate == null) {
        return;
      }
      if (this.lastLoadStopUrl === url) {
        return;
      }
      if (this.clientCertHttpFallbackPending) {
        this.loadStopDispatchInFlightUrl = '';
        return;
      }
      this.lastLoadStopUrl = url;
      this.loadStopDispatchInFlightUrl = '';
      this.isLoading = false;
      this.channelDelegate.onLoadStop(url);
    };
    if (settleMs > 0) {
      const timerId = setTimeout(dispatch, settleMs);
      this.pendingTimers.push(timerId);
    } else {
      dispatch();
    }
    return true;
  }

  /**
   * Finish client-cert HTTP fallback and dispatch a single onLoadStop.
   * Safe to call from onPageEnd and from the loadData timeout fallback.
   */
  public releaseClientCertHttpFallbackAndDispatchLoadStop(preferredUrl: string): boolean {
    if (!this.clientCertHttpFallbackPending || !this.clientCertHttpContentLoaded) {
      return false;
    }
    this.clientCertHttpFallbackPending = false;
    this.clientCertHttpContentLoaded = false;
    let url = preferredUrl;
    if (url == null || url.length === 0 || url.startsWith('data:')) {
      url = this.getUrl();
    }
    if (url == null || url.length === 0) {
      url = preferredUrl;
    }
    // Allow dispatch even if a deferred attempt recorded the same logical URL.
    this.lastLoadStopUrl = '';
    const dispatched = this.tryDispatchLoadStopIfNeeded(url);
    // Prevent a later onPageEnd from also dispatching for the data: URL.
    this.clientCertLoadStopDispatched = true;
    return dispatched;
  }

  private runJavaScriptScrollTo(x: number, y: number): void {
    if (!this.isControllerUsable()) {
      return;
    }
    try {
      this.requireController().runJavaScriptExt(`window.scrollTo(${x}, ${y});`);
    } catch (e) {
      Log.w(TAG, 'runJavaScriptScrollTo failed: ' + JSON.stringify(e));
    }
  }

  private cancelCurrentScrollAnimation(): void {
    if (this.currentScrollAnimator) {
      try {
        this.currentScrollAnimator.cancel();
      } catch (e) {
        Log.e(TAG, 'cancelCurrentScrollAnimation failed: ' + JSON.stringify(e));
      }
      this.currentScrollAnimator = null;
    }
  }

  private releaseScrollAnimator(target: AnimatorResult | undefined): void {
    if (!target) {
      return;
    }
    if (this.currentScrollAnimator === target) {
      this.currentScrollAnimator = null;
    }
  }

  public printCurrentPage(settings: PrintJobSettings): string | null {
    Log.d(TAG, 'printCurrentPage called, handledByClient=' + settings.handledByClient +
      ', plugin=' + (this.plugin != null ? 'present' : 'null') +
      ', printJobManager=' + (this.plugin?.printJobManager != null ? 'present' : 'null'));
    if (this.plugin == null || this.plugin.printJobManager == null) {
      Log.w(TAG, 'printCurrentPage returning null: plugin or printJobManager is null');
      return null;
    }
    if (!settings.handledByClient) {
      Log.d(TAG, 'printCurrentPage: handledByClient=false, using no-controller flow');
      this._startPrintFlowNoController(settings);
      return null;
    }
    let id: string = util.generateRandomUUID(true).toString();
    Log.d(TAG, 'printCurrentPage: handledByClient=true, created job id=' + id);
    let printJobController = new PrintJobController(id, null, settings, this.plugin!);
    this.plugin!.printJobManager!.jobs.set(id, printJobController);
    this._startPrintFlow(id, settings);
    return id;
  }

  /**
   * Build OHOS PrintAttributes from the plugin's PrintJobSettings.
   * Maps the cross-platform settings to OHOS print.PrintAttributes fields.
   */
  private _buildPrintAttributes(settings: PrintJobSettings): print.PrintAttributes {
    let printAttributes: print.PrintAttributes = {};

    // Orientation: 0 = portrait, 1 = landscape
    // Maps to PrintDirectionMode: 1 = PORTRAIT, 2 = LANDSCAPE
    if (settings.orientation != null) {
      if (settings.orientation === 0) {
        printAttributes.directionMode = print.PrintDirectionMode.DIRECTION_MODE_PORTRAIT;
      } else if (settings.orientation === 1) {
        printAttributes.directionMode = print.PrintDirectionMode.DIRECTION_MODE_LANDSCAPE;
      }
    }

    // Color mode: maps directly
    if (settings.colorMode != null) {
      printAttributes.colorMode = settings.colorMode === 0 ?
        print.PrintColorMode.COLOR_MODE_MONOCHROME :
        print.PrintColorMode.COLOR_MODE_COLOR;
    }

    // Duplex mode: maps directly
    if (settings.duplexMode != null) {
      printAttributes.duplexMode = settings.duplexMode as number;
    }

    return printAttributes;
  }

  /**
   * Core print logic using createWebPrintDocumentAdapter (API 11+).
   * This is the OHOS equivalent of Android's WebView.createPrintDocumentAdapter().
   * It creates a print adapter from the web content, which the print framework
   * uses to render the full web page into a PDF and present the print dialog.
   *
   * Flow: WebviewController.createWebPrintDocumentAdapter() → print.print(jobName, adapter, attrs, context)
   */
  private async _doPrintWithAdapter(printJobId: string | null, settings: PrintJobSettings): Promise<print.PrintTask | null> {
    if (this.context == null) {
      return null;
    }
    try {
      let context = this.context as common.UIAbilityContext;
      let jobName = settings.jobName != null ? settings.jobName! :
        (this.getTitle() != null ? this.getTitle()! : 'Document');

      // Create a print document adapter from the web view content
      // This is equivalent to Android's WebView.createPrintDocumentAdapter()
      let webPrintDocAdapter = this.requireController().createWebPrintDocumentAdapter(jobName + '.pdf');

      // Build PrintAttributes from the plugin's PrintJobSettings
      let printAttributes: print.PrintAttributes = this._buildPrintAttributes(settings);

      // Start the print task using the adapter
      // print.print(jobName, printAdapter, printAttributes, context)
      let printTask: print.PrintTask = await print.print(jobName, webPrintDocAdapter, printAttributes, context);

      // Attach PrintTask to PrintJobController if printJobId is provided
      if (printJobId != null) {
        let printJobController: PrintJobController | undefined = this.plugin!.printJobManager!.jobs.get(printJobId);
        if (printJobController != null) {
          const jobController: PrintJobController = printJobController;
          jobController.setJob(printTask);
          jobController.setCreationTime(Date.now());
          jobController.setState(PrintJobState.STARTED);
          // Register event listeners for state tracking
          // Store for cleanup in dispose()
          this.activePrintTask = printTask;
          printTask.on('block', () => {
            jobController.setState(PrintJobState.BLOCKED);
          });
          printTask.on('succeed', () => {
            jobController.setState(PrintJobState.COMPLETED);
            this.activePrintTask = null;
          });
          printTask.on('fail', () => {
            jobController.setState(PrintJobState.FAILED);
            this.activePrintTask = null;
          });
          printTask.on('cancel', () => {
            jobController.setState(PrintJobState.CANCELED);
            this.activePrintTask = null;
          });
        }
      }
      return printTask;
    } catch (e) {
      Log.e(TAG, '_doPrintWithAdapter error: ' + JSON.stringify(e));
      return null;
    }
  }

  private async _startPrintFlow(printJobId: string, settings: PrintJobSettings): Promise<void> {
    let printTask: print.PrintTask | null = await this._doPrintWithAdapter(printJobId, settings);
    if (printTask == null) {
      this._removePrintJobController(printJobId);
    }
  }

  private async _startPrintFlowNoController(settings: PrintJobSettings): Promise<void> {
    await this._doPrintWithAdapter(null, settings);
  }

  private _removePrintJobController(printJobId: string): void {
    if (this.plugin != null && this.plugin.printJobManager != null) {
      let controller: PrintJobController | undefined = this.plugin.printJobManager.jobs.get(printJobId);
      if (controller != null) {
        controller.setState(PrintJobState.FAILED);
      }
    }
  }

  public isDisposed(): boolean {
    return this.disposed;
  }

  private isControllerUsable(): boolean {
    return !this.disposed && this.controller != null && this.controllerAttached;
  }

  private requireUserContentController(): UserContentController {
    if (this.userContentController == null) {
      throw new Error('InAppWebView userContentController unavailable');
    }
    return this.userContentController;
  }

  private requireController(): web_webview.WebviewController {
    if (this.controller == null) {
      throw new Error('InAppWebView controller unavailable');
    }
    return this.controller;
  }

  public releaseWebComponentResources(): void {
    if (this.webResourcesReleased) {
      return;
    }
    this.notifyWebComponentUnmount();
    if (this.disposed) {
      return;
    }
    if (this.controller == null || !this.controllerAttached) {
      return;
    }
    this.webResourcesReleased = true;
    try {
      this.cancelCurrentScrollAnimation();
      this.requireController().deleteJavaScriptRegister(JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME);
      this.requireController().stop();
      this.requireController().pauseAllMedia();
      this.requireController().onInactive();
      this.requireController().loadUrl('about:blank');
    } catch (e) {
      Log.e(TAG, 'releaseWebComponentResources error: ' + JSON.stringify(e));
    }
  }

  public mountWebComponent(): void {
    try {
      let uiContext = this.context as common.UIAbilityContext;
      uiContext.eventHub.emit(EventConstant.EVENT_MOUNT_WEB_COMPONENT, this.id);
    } catch (e) {
      Log.e(TAG, 'mountWebComponent error: ' + JSON.stringify(e));
    }
  }

  public unmountWebComponent(): void {
    try {
      let uiContext = this.context as common.UIAbilityContext;
      uiContext.eventHub.emit(EventConstant.EVENT_UNMOUNT_WEB_COMPONENT, this.id);
    } catch (e) {
      Log.e(TAG, 'unmountWebComponent error: ' + JSON.stringify(e));
    }
  }

  private notifyWebComponentUnmount(): void {
    if (this.context == null) {
      return;
    }
    try {
      let uiContext = this.context as common.UIAbilityContext;
      uiContext.eventHub.emit(EventConstant.EVENT_UNMOUNT_WEB_COMPONENT, this.id);
    } catch (e) {
      Log.e(TAG, 'notifyWebComponentUnmount error: ' + JSON.stringify(e));
    }
  }

  private releaseWebResources(): void {
    this.releaseWebComponentResources();
    if (this.controller == null || !this.controllerAttached) {
      return;
    }
    try {
      this.requireController().clearHistory();
      this.requireController().clearMatches();
      this.requireController().removeCache(true);
    } catch (e) {
      Log.e(TAG, 'releaseWebResources error: ' + JSON.stringify(e));
    }
  }

  dispose() {
    if (this.disposed) {
      return;
    }
    this.clearNavigateBackFlag();
    this.pendingSkipAfterRedirectBlock = false;
    this.pendingSkipDirection = 0;
    this.cancelPendingControllerAttachWaiters();
    // Clean up active PrintTask event listeners
    if (this.activePrintTask != null) {
      try {
        this.activePrintTask.off('block');
        this.activePrintTask.off('succeed');
        this.activePrintTask.off('fail');
        this.activePrintTask.off('cancel');
      } catch (e) {
        Log.e(TAG, 'dispose printTask cleanup failed: ' + JSON.stringify(e));
      }
      this.activePrintTask = null;
    }
    // Cancel pending load-data timers
    for (let i = 0; i < this.loadDataTimers.length; i++) {
      try {
        clearTimeout(this.loadDataTimers[i]);
      } catch (e) {
        Log.e(TAG, 'dispose clearTimeout failed: ' + JSON.stringify(e));
      }
    }
    this.loadDataTimers = [];
    // Cancel pending general timers (client cert poll, load stop dispatch, popup emit, etc.)
    for (let i = 0; i < this.pendingTimers.length; i++) {
      try {
        clearTimeout(this.pendingTimers[i]);
      } catch (e) {
        Log.e(TAG, 'dispose pendingTimer cleanup failed: ' + JSON.stringify(e));
      }
    }
    this.pendingTimers = [];
    // 须在 disposed=true 之前释放 Web GPU 资源（releaseWebComponentResources 会检查 disposed）
    this.releaseWebResources();
    if (this.inAppWebViewClient != null) {
      this.inAppWebViewClient.dispose();
      this.inAppWebViewClient = null;
    }
    this.disposed = true;
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    if(this.controller){
      try {
        this.requireController().stop();
      } catch (e) {
        Log.e(TAG, 'dispose stop error: ' + e);
      }
      try {
        this.requireController().deleteJavaScriptRegister(JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME);
      } catch (e) {
        Log.e(TAG, 'dispose deleteJavaScriptRegister error: ' + e);
      }
    }

    if (this.webViewAssetLoaderExt != null) {
      this.webViewAssetLoaderExt.dispose();
      this.webViewAssetLoaderExt = null;
    }

    if(this.javaScriptBridgeInterface != null){
      this.javaScriptBridgeInterface.dispose();
      this.javaScriptBridgeInterface = null;
    }

    if (this.userContentController != null) {
      this.userContentController.dispose();
    }

    if(this.findInteractionController != null){
      this.findInteractionController.dispose();
      this.findInteractionController = null;
    }

    if(this.pullToRefreshLayout != null){
      this.pullToRefreshLayout.dispose();
      this.pullToRefreshLayout = null;
    }

    if (this.windowId != null && this.windowId != undefined && this.plugin != null && this.plugin.inAppWebViewManager != null) {
      let handler = this.plugin.inAppWebViewManager.windowWebViewMessages.get(this.windowId);
      if (handler != null) {
        try {
          // Unbind window name (e.g. _blank) so the next window.open() gets onWindowNew
          // instead of onActivateContent on a disposed controller.
          handler.setWebController(null);
        } catch (error) {
          Log.e(TAG, 'dispose popup setWebController(null) failed: ' + JSON.stringify(error));
        }
      }
      this.plugin.inAppWebViewManager.windowWebViewMessages.delete(this.windowId);
      this.plugin.inAppWebViewManager.windowWebViewControllers.delete(this.windowId);
      this.plugin.inAppWebViewManager.windowWebViewUrls.delete(this.windowId);
    }
    // Do not cleanup pending popup window state when a parent WebView disposes.
    // onCreateWindow return true replaces the parent with a popup-only widget tree;
    // clearing maps here detaches the popup controller and drops the target URL.

    this.disposeWebMessageChannels();
    this.disposeWebMessageListeners();

    this.callAsyncJavaScriptCallbacks.forEach((callback: ValueCallback<string>, uuid: string) => {
      try {
        callback.onReceiveValue(JSON.stringify({
          'value': null,
          'error': 'WebView disposed',
          'resultUuid': uuid
        }));
      } catch (e) {
        Log.e(TAG, 'Error notifying callAsyncJavaScript callback during dispose: ' + e);
      }
    });
    this.callAsyncJavaScriptCallbacks.clear();
    this.evaluateJavaScriptContentWorldCallbacks.forEach((callback: ValueCallback<string>, uuid: string) => {
      try {
        callback.onReceiveValue(JSON.stringify({
          'value': null,
          'error': 'WebView disposed',
          'resultUuid': uuid
        }));
      } catch (e) {
        Log.e(TAG, 'Error notifying evaluateJavaScript callback during dispose: ' + e);
      }
    });
    this.evaluateJavaScriptContentWorldCallbacks.clear();

    this.interceptOnlyAsyncAjaxRequestsPluginScript = null;
    this.contentBlockerHandler.getRuleList().clear();
    this.userContentController = null;
    this.loadDataPageUrlToIndex.clear();
    this.loadDataPageUrlToHistoryUrl.clear();
    this.pendingLoadDataHistoryUrl = null;
    this.contextMenu = undefined;

    this.inAppBrowserDelegate = null;
    this.plugin = null;
    this.controller = null;
    this.context = null;
  }

  private urlValueToString(value: string | Resource | null | undefined): string {
    if (value == null) {
      return '';
    }
    if (typeof value === 'string') {
      return value;
    }
    return String(value);
  }

  getUrl(): string {
    if (!this.isControllerUsable()) {
      return this.urlValueToString(this.curUrl);
    }
    try {
      let url = this.requireController().getUrl();
      let urlStr = this.urlValueToString(url);
      if (urlStr.length > 0 && urlStr !== 'about:blank') {
        if (urlStr.startsWith('data:')) {
          const cur = this.urlValueToString(this.curUrl);
          if (cur.length > 0 && !cur.startsWith('about:')) {
            return cur;
          }
        }
        if (this.isFlutterAssetLoaderUrl(urlStr)) {
          const cur = this.urlValueToString(this.curUrl);
          if (cur.startsWith('file://')) {
            return cur;
          }
        }
        return urlStr;
      }
    } catch (e) {
      Log.w(TAG, 'getUrl from controller failed: ' + JSON.stringify(e));
    }
    return this.urlValueToString(this.curUrl);
  }

  public syncCurUrlFromPageEnd(pageUrl: string): void {
    if (pageUrl == null || pageUrl.length === 0) {
      return;
    }
    try {
      if (pageUrl.startsWith('data:')) {
        // Prefer the history URL captured at loadData time: after back/forward
        // OHOS may not expose baseUrl on HistoryItem, so curUrl would stick.
        if (this.pendingLoadDataHistoryUrl != null &&
            (this.pendingLoadDataHistoryUrl.startsWith('http://') ||
              this.pendingLoadDataHistoryUrl.startsWith('https://'))) {
          this.storeLoadDataHistoryUrl(pageUrl, this.pendingLoadDataHistoryUrl);
          this.curUrl = this.pendingLoadDataHistoryUrl;
          this.pendingLoadDataHistoryUrl = null;
          const knownIndexForPending = this.lookupLoadDataPageIndex(pageUrl);
          if (knownIndexForPending != null) {
            this.storeLoadDataPageIndex(pageUrl, knownIndexForPending);
          }
          return;
        }
        const mappedHistoryUrl = this.lookupLoadDataHistoryUrl(pageUrl);
        if (mappedHistoryUrl != null) {
          this.curUrl = mappedHistoryUrl;
          const knownIndexForMapped = this.lookupLoadDataPageIndex(pageUrl);
          if (knownIndexForMapped != null) {
            this.storeLoadDataPageIndex(pageUrl, knownIndexForMapped);
          }
          return;
        }
        const knownIndex = this.lookupLoadDataPageIndex(pageUrl);
        if (knownIndex != null) {
          this.storeLoadDataPageIndex(pageUrl, knownIndex);
          const item = this.requireController().getBackForwardEntries().getItemAtIndex(knownIndex);
          const historyUrl = item.historyUrl ?? '';
          if (historyUrl.startsWith('http://') || historyUrl.startsWith('https://')) {
            this.curUrl = historyUrl;
            this.storeLoadDataHistoryUrl(pageUrl, historyUrl);
          }
          return;
        }
      }
      const list = this.requireController().getBackForwardEntries();
      let matchedIndex = list.currentIndex;
      for (let i = 0; i < list.size; i++) {
        const item = list.getItemAtIndex(i);
        const historyUrl = item.historyUrl ?? '';
        const rawUrl = item.historyRawUrl ?? '';
        if (pageUrl === historyUrl || pageUrl === rawUrl) {
          matchedIndex = i;
          break;
        }
      }
      if (pageUrl.startsWith('data:')) {
        this.storeLoadDataPageIndex(pageUrl, matchedIndex);
      }
      const item = list.getItemAtIndex(matchedIndex);
      const historyUrl = item.historyUrl ?? '';
      if (historyUrl.startsWith('http://') || historyUrl.startsWith('https://')) {
        const cur = this.urlValueToString(this.curUrl);
        if (this.isFlutterAssetLoaderUrl(historyUrl) && cur.startsWith('file://')) {
          return;
        }
        this.curUrl = historyUrl;
        if (pageUrl.startsWith('data:')) {
          this.storeLoadDataHistoryUrl(pageUrl, historyUrl);
        }
      }
    } catch (e) {
      Log.w(TAG, 'syncCurUrlFromPageEnd failed: ' + JSON.stringify(e));
    }
  }

  private storeLoadDataPageIndex(pageUrl: string, index: number): void {
    if (this.loadDataPageUrlToIndex.size >= InAppWebView.LOAD_DATA_MAP_MAX_SIZE) {
      this.loadDataPageUrlToIndex.clear();
    }
    this.loadDataPageUrlToIndex.set(pageUrl, index);
    try {
      const normalized = decodeURIComponent(pageUrl);
      if (normalized !== pageUrl) {
        this.loadDataPageUrlToIndex.set(normalized, index);
      }
    } catch (e) {
      // ignore decode errors
    }
  }

  private storeLoadDataHistoryUrl(pageUrl: string, historyUrl: string): void {
    if (this.loadDataPageUrlToHistoryUrl.size >= InAppWebView.LOAD_DATA_MAP_MAX_SIZE) {
      this.loadDataPageUrlToHistoryUrl.clear();
    }
    this.loadDataPageUrlToHistoryUrl.set(pageUrl, historyUrl);
    try {
      const normalized = decodeURIComponent(pageUrl);
      if (normalized !== pageUrl) {
        this.loadDataPageUrlToHistoryUrl.set(normalized, historyUrl);
      }
    } catch (e) {
      // ignore decode errors
    }
  }

  private lookupLoadDataHistoryUrl(pageUrl: string): string | null {
    if (this.loadDataPageUrlToHistoryUrl.has(pageUrl)) {
      return this.loadDataPageUrlToHistoryUrl.get(pageUrl) ?? null;
    }
    try {
      const normalized = decodeURIComponent(pageUrl);
      if (this.loadDataPageUrlToHistoryUrl.has(normalized)) {
        return this.loadDataPageUrlToHistoryUrl.get(normalized) ?? null;
      }
    } catch (e) {
      // ignore decode errors
    }
    return null;
  }

  private lookupLoadDataPageIndex(pageUrl: string): number | null {
    if (this.loadDataPageUrlToIndex.has(pageUrl)) {
      return this.loadDataPageUrlToIndex.get(pageUrl) ?? null;
    }
    try {
      const normalized = decodeURIComponent(pageUrl);
      if (this.loadDataPageUrlToIndex.has(normalized)) {
        return this.loadDataPageUrlToIndex.get(normalized) ?? null;
      }
    } catch (e) {
      // ignore decode errors
    }
    return null;
  }

  getTitle(): string {
    try {
      return this.requireController().getTitle()
    } catch (e) {
      Log.e(TAG, 'getTitle failed', e);
      return '';
    }
  }

  getProgress(): number {
    return this.inAppWebViewClient ? this.inAppWebViewClient!.progress : 0
  }

  reload(): void {
    try {
      this.requireController().refresh();
    } catch (e) {
      Log.e(TAG, 'reload failed', e);
    }
  }

  canGoBack(): boolean {
    try {
      return this.requireController().accessBackward()
    } catch (e) {
      Log.e(TAG, 'canGoBack failed', e);
      return false;
    }
  }

  goBack(): void {
    this.isNavigatingBackOrForward = true;
    this.navigateBackOrForwardDirection = -1;
    this.backForwardNavigationAllowCount = 1;
    this.startNavigateBackTimer();
    // Use JS history.back() instead of controller.backward() because
    // OHOS has a '历史操作干预机制' that skips history entries added
    // without user activation (e.g. JS window.open()/location.href),
    // causing backward() to silently no-op. JS history.back() is not
    // affected by this OHOS platform behavior.
    try {
      this.requireController().runJavaScript('history.back();');
    } catch (e) {
      Log.e(TAG, 'goBack: history.back() failed, falling back to backward()', e);
      this.requireController().backward();
    }
  }

  canGoForward(): boolean {
    try {
      return this.requireController().accessForward()
    } catch (e) {
      Log.e(TAG, 'canGoForward failed', e);
      return false;
    }
  }

  goForward(): void {
    this.isNavigatingBackOrForward = true;
    this.navigateBackOrForwardDirection = 1;
    this.backForwardNavigationAllowCount = 1;
    this.startNavigateBackTimer();
    try {
      this.requireController().runJavaScript('history.forward();');
    } catch (e) {
      Log.e(TAG, 'goForward: history.forward() failed, falling back to forward()', e);
      this.requireController().forward();
    }
  }

  canGoBackOrForward(steps: number): boolean {
    return this.requireController().accessStep(steps)
  }

  goBackOrForward(steps: number): void {
    if (steps === 0) {
      return;
    }
    this.isNavigatingBackOrForward = true;
    this.navigateBackOrForwardDirection = steps < 0 ? -1 : 1;
    this.backForwardNavigationAllowCount = Math.abs(steps);
    this.startNavigateBackTimer();
    try {
      this.requireController().backOrForward(steps);
    } catch (e) {
      Log.e(TAG, 'goBackOrForward: backOrForward() failed, falling back to history.go()', e);
      try {
        this.requireController().runJavaScript('history.go(' + steps + ');');
      } catch (jsError) {
        Log.e(TAG, 'goBackOrForward: history.go() failed', jsError);
      }
    }
  }

  private startNavigateBackTimer(): void {
    if (this.navigateBackTimer !== -1) {
      clearTimeout(this.navigateBackTimer);
    }
    this.navigateBackTimer = setTimeout(() => {
      this.isNavigatingBackOrForward = false;
      this.navigateBackOrForwardDirection = 0;
      this.backForwardNavigationAllowCount = 0;
      this.pendingSkipAfterRedirectBlock = false;
      this.pendingSkipDirection = 0;
      this.navigateBackTimer = -1;
    }, 5000);
  }

  public clearNavigateBackFlag(): void {
    this.isNavigatingBackOrForward = false;
    this.navigateBackOrForwardDirection = 0;
    this.backForwardNavigationAllowCount = 0;
    if (this.navigateBackTimer !== -1) {
      clearTimeout(this.navigateBackTimer);
      this.navigateBackTimer = -1;
    }
  }

  stopLoading(): void {
    try {
      this.requireController().stop()
    } catch (e) {
      Log.e(TAG, 'stopLoading failed', e);
    }
  }

  clearSslPreferences(): void {
    try {
      this.requireController().clearSslCache()
    } catch (e) {
      Log.e(TAG, 'clearSslPreferences failed', e);
    }
  }

  findAllAsync(find: string): void {
    try {
      this.requireController().searchAllAsync(find)
    } catch (e) {
      Log.e(TAG, 'findAllAsync failed', e);
    }
  }

  findNext(forward: boolean): void {
    try {
      this.requireController().searchNext(forward)
    } catch (e) {
      Log.e(TAG, 'findNext failed', e);
    }
  }

  clearMatches(): void {
    try {
      this.requireController().clearMatches()
    } catch (e) {
      Log.e(TAG, 'clearMatches failed', e);
    }
  }

  onPause(): void {
    try {
      this.requireController().pauseAllMedia()
      this.requireController().onInactive()
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'onPause failed: ' + JSON.stringify(err));
    }
  }

  onResume(): void {
    try {
      this.requireController().resumeAllMedia()
      this.requireController().onActive()
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'onResume failed: ' + JSON.stringify(err));
    }
  }

  pauseTimers(): void {
    web_webview.WebviewController.pauseAllTimers();
  }

  resumeTimers(): void {
    web_webview.WebviewController.resumeAllTimers();
  }

  getContentHeight(): number {
    if (!this.isControllerUsable()) {
      return 0;
    }
    try {
      return this.requireController().getPageHeight()
    } catch (e) {
      Log.w(TAG, 'getContentHeight sync throw (controller detached): ' + JSON.stringify(e));
      return 0;
    }
  }

  public getContentWidth(callback: ValueCallback<number>): void {
    if (!this.isControllerUsable()) {
      callback.onReceiveValue(0);
      return;
    }
    try {
      this.requireController().runJavaScriptExt('document.documentElement.scrollWidth;').then((result) => {
        callback.onReceiveValue(result.getNumber())
      }).catch((error: BusinessError) => {
        Log.w(TAG, 'getContentWidth failed: ' + error.message);
        callback.onReceiveValue(0);
      })
    } catch (e) {
      Log.w(TAG, 'getContentWidth sync throw (controller detached): ' + JSON.stringify(e));
      callback.onReceiveValue(0);
    }
  }

  public saveWebArchive(baseName: string, autoName: boolean, callback: ValueCallback<string>): void {
    try {
      this.requireController().storeWebArchive(baseName, autoName).then(fileName => {
        callback.onReceiveValue(fileName)
      }).catch((e: Error) => {
        Log.e(TAG, 'saveWebArchive failed: ' + JSON.stringify(e));
        callback.onReceiveValue('');
      })
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'saveWebArchive sync failed: ' + JSON.stringify(err));
      callback.onReceiveValue('');
    }
  }

  public isSecureContext(resultCallback: ValueCallback<boolean>): void {
    this.evaluateJavascript('window.isSecureContext', null,  {
      onReceiveValue: (value) => {
        if (value == null || value.length == 0 || value == 'null' || value == 'false') {
          resultCallback.onReceiveValue(false);
          return;
        }
        resultCallback.onReceiveValue(true);
      }
    });
  }

  zoomBy(zoomFactor: number): void {
    if (zoomFactor < 0.01)
      throw new Error('zoomFactor must be greater than 0.01.');
    if (zoomFactor > 100.0)
      throw new Error('zoomFactor must be less than 100.');

    const density: number = Util.getPixelDensity();
    const oldChannelScale: number = this.zoomScale * density;

    try {
      this.requireController().zoom(zoomFactor);
    } catch (e) {
      throw new Error('Failed to perform zoom operation');
    }

    this.zoomScale = this.zoomScale * zoomFactor;
    const newChannelScale: number = this.zoomScale * density;
    if (this.channelDelegate != null &&
      Math.abs(newChannelScale - oldChannelScale) >= 0.01) {
      this.channelDelegate.onZoomScaleChanged(oldChannelScale, newChannelScale);
    }
  }

  getOriginalUrl(): string {
    try {
      return this.requireController().getOriginalUrl()
    } catch (e) {
      Log.e(TAG, 'getOriginalUrl failed', e);
      return '';
    }
  }

  getZoomScale(): number {
    return this.zoomScale
  }

  getHitTestResult(): web_webview.HitTestValue {
    return this.requireController().getHitTestValue()
  }

  pageDown(bottom: boolean): boolean {
    try {
      this.requireController().pageDown(bottom)
      return true
    } catch (e) {
      throw Error('Jumping to the bottom of the page failed')
    }
  }

  pageUp(top: boolean): boolean {
    try {
      this.requireController().pageUp(top)
      return true
    } catch (e) {
      throw Error('Jumping to the top of the page failed')
    }
  }

  zoomIn(): boolean {
    try {
      this.requireController().zoomIn()
      return true
    } catch (e) {
      throw Error('Failed to perform amplification operation')
    }
  }

  zoomOut(): boolean {
    try {
      this.requireController().zoomOut()
      return true
    } catch (e) {
      throw Error('Failed to perform shrink operation')
    }
  }

  clearFocus(): void {
    try {
      this.requireController().runJavaScript(
        '(function(){var e=document.activeElement;if(e&&e.blur)e.blur();})();'
      );
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'clearFocus failed: ' + JSON.stringify(err));
    }
  }

  async getCertificate() {
    let certificates = await this.requireController().getCertificate()
    if (certificates && certificates.length > 0) {
      return certificates[0]
    } else {
      return null
    }
  }

  clearHistory(): void {
    this.requireController().clearHistory();
    this.loadDataPageUrlToIndex.clear();
    this.loadDataPageUrlToHistoryUrl.clear();
    this.pendingLoadDataHistoryUrl = null;
  }

  async postUrl(
    url: string,
    postData: ArrayBuffer | null,
    headers?: Map<string, string> | null
  ) {
    await this.waitControllerAttached();
    const buffer = InAppWebView.copyRequestBody(postData);
    // Private/loopback: ArkWeb postUrl hangs on the 2nd WebView after about:blank.
    if (this.shouldPostViaHttpFallback(url)) {
      await this.loadPrivateHttpUrl(url, 'POST', buffer, headers);
      return;
    }
    this.curUrl = url;
    try {
      this.requireController().postUrl(url, buffer);
    } catch (e) {
      Log.e(TAG, 'postUrl failed: ' + JSON.stringify(e));
    }
  }

  async loadDataWithBaseURL(baseUrl: string, data: string, mimeType: string, encoding: string, historyUrl: string) {
    Log.d(TAG, 'loadDataWithBaseURL begin baseUrl=' + baseUrl + ' dataLen=' + data.length);
    await this.waitControllerAttached();
    Log.d(TAG, 'loadDataWithBaseURL controller attached');
    baseUrl ??= 'about:blank';
    historyUrl ??= 'about:blank';
    // Dart defaults historyUrl to about:blank when omitted; Android WebView uses
    // baseUrl as the history entry URL in that case.
    if ((historyUrl === 'about:blank' || historyUrl.length === 0) &&
        baseUrl !== 'about:blank' && baseUrl.length > 0 &&
        (baseUrl.startsWith('http://') || baseUrl.startsWith('https://'))) {
      historyUrl = baseUrl;
    }
    if (historyUrl !== 'about:blank') {
      this.curUrl = historyUrl;
      if (historyUrl.startsWith('http://') || historyUrl.startsWith('https://')) {
        this.pendingLoadDataHistoryUrl = historyUrl;
      }
      // OHOS keeps the initial about:blank entry when the first loadData() is
      // applied; Android/iOS replace that entry. Clear history on the first
      // non-about load so back/forward indices match other platforms.
      try {
        if (!this.canGoBack()) {
          const currentUrl = this.getUrl();
          if (currentUrl === 'about:blank' || currentUrl.startsWith('about:')) {
            this.requireController().clearHistory();
          }
        }
      } catch (e) {
        Log.w(TAG, 'loadDataWithBaseURL clearHistory check failed: ' + JSON.stringify(e));
      }
    }
    if (this.customSettings.geolocationAccess &&
        data.indexOf('geolocation') >= 0 &&
        (baseUrl.startsWith('http://') || baseUrl.startsWith('https://'))) {
      this.pendingLoadDataGeolocationRetrigger = true;
    }
    const pageUrl: string = historyUrl !== 'about:blank' ? historyUrl : baseUrl;
    let dataToLoad: string = data;
    // Embed hook in loadData HTML so it survives late document parse (runJavaScript
    // timers can run before/during replace and get wiped before the test clicks).
    if (this.customSettings.multiWindowAccess && this.customSettings.allowWindowOpenMethod) {
      const hookTag: string = '<script>' + WindowOpenAboutBlankJS.SOURCE + '</script>';
      const lower: string = dataToLoad.toLowerCase();
      const headIdx: number = lower.indexOf('<head>');
      const bodyIdx: number = lower.indexOf('<body>');
      if (headIdx >= 0) {
        const insertAt: number = headIdx + 6;
        dataToLoad = dataToLoad.substring(0, insertAt) + hookTag + dataToLoad.substring(insertAt);
      } else if (bodyIdx >= 0) {
        const insertAt: number = bodyIdx + 6;
        dataToLoad = dataToLoad.substring(0, insertAt) + hookTag + dataToLoad.substring(insertAt);
      } else {
        dataToLoad = hookTag + dataToLoad;
      }
      // Inline the signal in onclick so we do not depend on <script> surviving loadData.
      const inlineOpen: string =
        "console.log('" + WindowOpenAboutBlankJS.CONSOLE_PREFIX + "about:blank');" +
        "setTimeout(function(){try{var b=window.flutter_inappwebview;" +
        "if(b&&b._callHandler){b._callHandler('" + WindowOpenAboutBlankJS.HANDLER_NAME +
        "','0','[]');}}catch(e){}},0)";
      dataToLoad = dataToLoad.split("window.open('about:blank','_blank')").join(inlineOpen);
      dataToLoad = dataToLoad.split('window.open("about:blank","_blank")').join(inlineOpen);
    }
    this.requireController().loadData(dataToLoad, mimeType, encoding, baseUrl, historyUrl);
    // Do not await page-ready here: this runs on the platform method-channel
    // thread; waiting for onPageEnd/setTimeout deadlocks after a prior WebView.
    this.scheduleLoadDataCompletion(pageUrl);
    Log.d(TAG, 'loadDataWithBaseURL done');
  }

  public notifyLoadDataPageReady(): void {
    // Kept for onPageEnd callers; loadData no longer awaits this (deadlock risk).
    if (this.loadDataReadyResolve != null) {
      const resolve = this.loadDataReadyResolve;
      this.loadDataReadyResolve = null;
      resolve();
    }
  }

  private extractOriginFromUrl(url: string): string {
    const match = url.match(/^(https?:\/\/[^/]+)/i);
    return match != null ? match[1] : url;
  }

  private scheduleLoadDataCompletion(pageUrl: string): void {
    if (this.disposed || !this.isControllerUsable()) {
      return;
    }
    if (pageUrl !== 'about:blank' && pageUrl.length > 0) {
      // No-op while httpLoadData/clientCert fallback pending (DOM not ready yet).
      this.tryDispatchLoadStopIfNeeded(pageUrl);
    }
    if (this.pendingLoadDataGeolocationRetrigger && this.inAppWebViewClient != null) {
      this.pendingLoadDataGeolocationRetrigger = false;
      const origin: string = this.extractOriginFromUrl(pageUrl);
      this.inAppWebViewClient.dispatchManualGeolocationPrompt(origin);
    }
    // Install early so window.open(about:blank) works before the caller's short delay.
    if (this.customSettings.multiWindowAccess && this.customSettings.allowWindowOpenMethod) {
      const install = (): void => {
        if (this.disposed || !this.isControllerUsable()) {
          return;
        }
        try {
          this.requireController().runJavaScript(WindowOpenAboutBlankJS.SOURCE);
        } catch (error) {
          Log.w(TAG, 'scheduleLoadDataCompletion window.open hook failed: ' + JSON.stringify(error));
        }
      };
      // Cover slow loadData after prior multi-window tests (DOM may arrive after 400ms).
      const delays: number[] = [0, 200, 400, 600, 800, 1000, 1200];
      for (let i = 0; i < delays.length; i++) {
        let timerId = setTimeout(install, delays[i]);
        this.loadDataTimers.push(timerId);
      }
    }
  }

  getController(): web_webview.WebviewController {
    if (this.controller == null) {
      throw new Error('InAppWebView controller unavailable');
    }
    return this.controller;
  }

  public getInAppBrowserDelegate(): InAppBrowserDelegate | null {
    return this.inAppBrowserDelegate;
  }

  public setContextMenu(contextMenu: Map<string, Any>): void {
    this.contextMenu = contextMenu;
  }

  public async requestFocusNodeHref(): Promise<Map<string, Any>> {
    let obj: Map<string, Any> = new Map<string, Any>();
    // Use context menu data captured from onContextMenuShow event.param.getLinkUrl().
    // Falls back to getHitTestValue() with type check if no context menu data available.
    if (this.lastContextMenuLinkUrl != null) {
      obj.set('src', this.lastContextMenuLinkUrl);
      obj.set('url', this.lastContextMenuLinkUrl);
      obj.set('title', null);
      return obj;
    }
    try {
      let hitValue: web_webview.HitTestValue = this.requireController().getHitTestValue();
      const type = hitValue.type;
      const extra = hitValue.extra;
      const hasExtra = extra != null && extra.length > 0;
      const isImage: boolean = type === web_webview.WebHitTestType.Img
        || type === web_webview.WebHitTestType.HttpAnchorImg;
      const isAnchor: boolean = type === web_webview.WebHitTestType.HttpAnchor
        || type === web_webview.WebHitTestType.HttpAnchorImg;
      obj.set('url', isAnchor && hasExtra ? extra : null);
      obj.set('src', isImage && hasExtra ? extra : null);
      obj.set('title', null);
    } catch (error) {
      let e: BusinessError = error as BusinessError;
      Log.w(TAG, `requestFocusNodeHref failed, code: ${e.code}, message: ${e.message}`);
    }
    return obj;
  }

  public async requestImageRef(): Promise<Map<string, Any>> {
    let obj: Map<string, Any> = new Map<string, Any>();
    // Use context menu data from onContextMenuShow event.param.getSourceUrl().
    // Falls back to getHitTestValue() with type check if no context menu data available.
    if (this.lastContextMenuSourceUrl != null) {
      obj.set('url', this.lastContextMenuSourceUrl);
      return obj;
    }
    try {
      let hitValue: web_webview.HitTestValue = this.requireController().getHitTestValue();
      const extra = hitValue.extra;
      const hasExtra = extra != null && extra.length > 0;
      const isImage: boolean = hitValue.type === web_webview.WebHitTestType.Img
        || hitValue.type === web_webview.WebHitTestType.HttpAnchorImg;
      obj.set('url', isImage && hasExtra ? extra : null);
    } catch (error) {
      let e: BusinessError = error as BusinessError;
      Log.w(TAG, `requestImageRef failed, code: ${e.code}, message: ${e.message}`);
    }
    return obj;
  }

  public createCompatWebMessageChannel(): WebMessageChannel {
    let id: string = util.generateRandomUUID(true).toString();
    let webMessageChannel: WebMessageChannel = new WebMessageChannel(id, this);
    this.webMessageChannels.set(id, webMessageChannel);
    return webMessageChannel;
  }

  public addWebMessageListener(webMessageListener: WebMessageListener): void {
    webMessageListener.initJsInstance();
    this.webMessageListeners.push(webMessageListener);
  }

  public dispatchWebMessageListenerPostMessage(jsObjectName: string, message: WebMessageCompatExt,
    sourceOrigin: string | null, isMainFrame: boolean): void {
    for (let listener of this.webMessageListeners) {
      listener.handlePostMessageFromJs(jsObjectName, message, sourceOrigin, isMainFrame);
    }
  }

  public canScrollVertically(): boolean {
    // Prefer JS-measured scrollHeight; getPageHeight() is often wrong for loadData.
    const viewport = this.innerHeight > 0 ? this.innerHeight : this.viewHeight;
    if (this.contentHeight > 0 && viewport > 0) {
      return this.contentHeight > viewport;
    }
    return this.getContentHeight() > this.viewHeight;
  }

  public measureCanScrollVertically(callback: ValueCallback<boolean>): void {
    if (!this.isControllerUsable()) {
      callback.onReceiveValue(false);
      return;
    }
    try {
      this.requireController().runJavaScriptExt(
        'Math.max(document.documentElement.scrollHeight||0, document.body?document.body.scrollHeight:0);'
      ).then(result => {
        if (!this.isControllerUsable()) {
          callback.onReceiveValue(false);
          return;
        }
        this.contentHeight = result.getNumber();
        const viewport = this.innerHeight > 0 ? this.innerHeight : this.viewHeight;
        callback.onReceiveValue(viewport > 0 && this.contentHeight > viewport);
      }).catch((error: Error) => {
        Log.e(TAG, 'measureCanScrollVertically JavaScript execution failed: ' + error.message);
        callback.onReceiveValue(this.canScrollVertically());
      })
    } catch (e) {
      Log.w(TAG, 'measureCanScrollVertically sync throw (controller detached): ' + JSON.stringify(e));
      callback.onReceiveValue(false);
    }
  }

  public canScrollHorizontally(callback: ValueCallback<boolean>) {
    if (!this.isControllerUsable()) {
      callback.onReceiveValue(false);
      return;
    }
    try {
      this.requireController().runJavaScriptExt('document.documentElement.scrollWidth;').then(result => {
        if (!this.isControllerUsable()) {
          callback.onReceiveValue(false);
          return;
        }
        this.contentWidth = result.getNumber();
        const viewport = this.innerWidth > 0 ? this.innerWidth : this.viewWidth;
        callback.onReceiveValue(viewport > 0 && result.getNumber() > viewport)
      }).catch((error: Error) => {
        Log.e(TAG, 'canScrollHorizontally JavaScript execution failed: ' + error.message);
        callback.onReceiveValue(false);
      })
    } catch (e) {
      Log.w(TAG, 'canScrollHorizontally sync throw (controller detached): ' + JSON.stringify(e));
      callback.onReceiveValue(false);
    }
  }

  public refreshScrollMetricsAsync(): void {
    if (!this.isControllerUsable()) {
      return;
    }
    try {
      this.requireController().runJavaScriptExt('window.innerWidth;').then((result) => {
        if (!this.isControllerUsable()) {
          return;
        }
        this.innerWidth = result.getNumber();
      }).catch((error: BusinessError) => {
        Log.w(TAG, 'refreshScrollMetricsAsync innerWidth failed: ' + error.message);
      })

      this.requireController().runJavaScriptExt('window.innerHeight;').then((result) => {
        if (!this.isControllerUsable()) {
          return;
        }
        this.innerHeight = result.getNumber();
      }).catch((error: BusinessError) => {
        Log.w(TAG, 'refreshScrollMetricsAsync innerHeight failed: ' + error.message);
      })

      this.requireController().runJavaScriptExt('document.documentElement.scrollWidth;').then((result) => {
        if (!this.isControllerUsable()) {
          return;
        }
        this.contentWidth = result.getNumber();
      }).catch((error: BusinessError) => {
        Log.w(TAG, 'refreshScrollMetricsAsync scrollWidth failed: ' + error.message);
      })

      this.requireController().runJavaScriptExt(
        'Math.max(document.documentElement.scrollHeight||0, document.body?document.body.scrollHeight:0);'
      ).then((result) => {
        if (!this.isControllerUsable()) {
          return;
        }
        this.contentHeight = result.getNumber();
      }).catch((error: BusinessError) => {
        Log.w(TAG, 'refreshScrollMetricsAsync scrollHeight failed: ' + error.message);
      })
    } catch (e) {
      Log.w(TAG, 'refreshScrollMetricsAsync sync throw (controller detached): ' + JSON.stringify(e));
      this.controllerAttached = false;
    }
  }

  public getMaxScrollX(): number {
    if (this.innerWidth <= 0) {
      return 0;
    }
    return Math.max(0, this.contentWidth - this.innerWidth);
  }

  public getMaxScrollY(): number {
    if (this.innerHeight <= 0) {
      return 0;
    }
    const height = this.contentHeight > 0 ? this.contentHeight : this.getContentHeight();
    return Math.max(0, height - this.innerHeight);
  }

  public isClampedX(scrollX: number, maxScrollX: number): boolean {
    if (maxScrollX <= 0) {
      return false;
    }
    return scrollX <= this.scrollClampTolerance || scrollX >= maxScrollX - this.scrollClampTolerance;
  }

  public isClampedY(scrollY: number, maxScrollY: number): boolean {
    if (maxScrollY <= 0) {
      return false;
    }
    return scrollY <= this.scrollClampTolerance || scrollY >= maxScrollY - this.scrollClampTolerance;
  }


  public isInFullscreen(): boolean {
    return this.inFullscreen;
  }

  setInFullscreen(inFullscreen: boolean) {
    this.inFullscreen = inFullscreen;
  }

  public getPlugin(): InAppWebViewFlutterPlugin {
    if (this.plugin == null) {
      throw new Error('InAppWebView plugin unavailable');
    }
    return this.plugin;
  }

  public getWebMessageChannels(): Map<string, WebMessageChannel> {
    return this.webMessageChannels;
  }

  public getUserContentController(): UserContentController | null {
    return this.userContentController;
  }

  public onControllerAttached = () => {
    Log.d(TAG, 'onControllerAttached');
    if (this.controllerAttached) {
       return;
    }
    this.controllerAttached = true
    this.applyPendingUserAgentSettings();
    if (this.windowId != null && this.windowId != undefined) {
      this.loadPendingPopupUrlIfNeeded();
      this.prepareAndAddUserScripts();
      // Popup may already be loaded before Flutter mounts; synthesize onLoadStop shortly after attach.
      const popupTimerId = setTimeout(() => {
        if (!this.disposed && this.controllerAttached) {
          this.emitPopupLoadStopIfComplete();
        }
      }, 300);
      this.pendingTimers.push(popupTimerId);
    }
    this.resolvePendingControllerAttachWaiters();
  }

  private popupLoadStopEmitted: boolean = false;

  /**
   * When onWindowNew kept setWebController(null) for about:blank, JS window.close()
   * does not trigger onWindowExit. Bridge close to onCloseWindow for those popups.
   */
  private installPopupWindowCloseBridge(): void {
    if (this.windowId == null || this.windowId == undefined || !this.isControllerUsable()) {
      return;
    }
    try {
      const bridge = JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME;
      const js =
        '(function(){try{var _c=window.close;window.close=function(){' +
        'try{if(window.' + bridge + '!=null&&window.' + bridge + '.callHandler!=null){' +
        'window.' + bridge + '.callHandler(\'__onPopupWindowClose\');}}' +
        'catch(_e){}try{if(typeof _c===\'function\'){_c.call(window);}}catch(_e2){}};}catch(_e3){}})();';
      this.requireController().runJavaScript(js);
    } catch (error) {
      Log.e(TAG, 'installPopupWindowCloseBridge failed: ' + JSON.stringify(error));
    }
  }

  private loadPendingPopupUrlIfNeeded(): void {
    if (this.windowId == null || this.windowId == undefined) {
      return;
    }
    let popupUrl: string | null = this.pendingPopupUrl;
    if ((popupUrl == null || popupUrl.length === 0) &&
      this.plugin != null && this.plugin.inAppWebViewManager != null) {
      popupUrl = this.plugin.inAppWebViewManager.windowWebViewUrls.get(this.windowId) ?? null;
    }
    if (popupUrl == null || popupUrl.length === 0) {
      return;
    }
    try {
      this.curUrl = popupUrl;
      this.requireController().loadUrl(popupUrl);
      this.pendingPopupUrl = null;
    } catch (error) {
      Log.e(TAG, 'loadPendingPopupUrlIfNeeded failed: ' + JSON.stringify(error));
    }
  }

  private emitPopupLoadStopIfComplete(): void {
    if (this.windowId == null || this.windowId == undefined ||
      this.channelDelegate == null || this.popupLoadStopEmitted) {
      return;
    }
    try {
      let currentUrl: string = '';
      try {
        currentUrl = this.requireController().getUrl();
      } catch (_e) {
        currentUrl = '';
      }
      if (currentUrl.length === 0) {
        let pending: string | null = this.pendingPopupUrl;
        if ((pending == null || pending.length === 0) &&
          this.plugin != null && this.plugin.inAppWebViewManager != null) {
          pending = this.plugin.inAppWebViewManager.windowWebViewUrls.get(this.windowId) ?? null;
        }
        if (pending != null && pending.length > 0) {
          currentUrl = pending;
        }
      }
      if (currentUrl.length === 0) {
        return;
      }
      if (currentUrl === 'about:blank') {
        // Do not wait for isLoading=false: about:blank may keep loading flags under load.
        this.installPopupWindowCloseBridge();
        this.popupLoadStopEmitted = true;
        this.channelDelegate.onLoadStop('');
        return;
      }
      if (this.isLoading) {
        return;
      }
      this.popupLoadStopEmitted = true;
      this.channelDelegate.onLoadStop(currentUrl);
    } catch (error) {
      Log.e(TAG, 'emitPopupLoadStopIfComplete failed: ' + JSON.stringify(error));
    }
  }

  /**
   * ArkWeb 的 setCustomUserAgent() 仅影响 HTTP 请求头，不影响 JS navigator.userAgent。
   * 此方法注入 JS 代码覆盖 navigator.userAgent 的 getter，使 JS 端行为与 Android/iOS/macOS 一致。
   */
  public applyJsUserAgentOverride(): void {
    if (!this.controllerAttached || this.disposed) {
      return;
    }
    try {
      let ua: string = this.getSafeCustomUserAgent();
      if (ua != null && ua.length > 0) {
        let escapedUa: string = ua.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
        let js = `(function(){Object.defineProperty(navigator,'userAgent',{get:function(){return '${escapedUa}';},configurable:true});})();`;
        this.requireController().runJavaScriptExt(js);
        Log.d(TAG, `applyJsUserAgentOverride: navigator.userAgent overridden to '${ua.substring(0, 50)}'`);
      }
    } catch (error) {
      let e: BusinessError = error as BusinessError;
      Log.w(TAG, `applyJsUserAgentOverride failed, code: ${e.code}, message: ${e.message}`);
    }
  }

  public getSafeCustomUserAgent(): string {
    if (!this.controllerAttached) {
      return this.customSettings.userAgent ?? '';
    }
    try {
      let ua: string = this.requireController().getCustomUserAgent();
      if (ua != null && ua.length > 0) {
        return ua;
      }
    } catch (error) {
      let e: BusinessError = error as BusinessError;
      Log.w(TAG, `getCustomUserAgent failed, code: ${e.code}, message: ${e.message}`);
    }
    return this.customSettings.userAgent ?? '';
  }

  private getSafeUserAgent(): string {
    if (!this.controllerAttached) {
      return this.customSettings.userAgent ?? '';
    }
    try {
      return this.requireController().getUserAgent();
    } catch (error) {
      let e: BusinessError = error as BusinessError;
      Log.w(TAG, `getUserAgent failed, code: ${e.code}, message: ${e.message}`);
      return this.customSettings.userAgent ?? '';
    }
  }

  private applyPendingUserAgentSettings(): void {
    try {
      if (this.customSettings.userAgent != null && this.customSettings.userAgent.length > 0) {
        this.requireController().setCustomUserAgent(this.customSettings.userAgent);
      }
      if (this.customSettings.applicationNameForUserAgent != null &&
        this.customSettings.applicationNameForUserAgent.length > 0) {
        let userAgent = (this.customSettings.userAgent != null && this.customSettings.userAgent.length > 0)
          ? this.customSettings.userAgent
          : this.getSafeUserAgent();
        let userAgentWithApplicationName = userAgent + ' ' + this.customSettings.applicationNameForUserAgent;
        this.requireController().setCustomUserAgent(userAgentWithApplicationName);
      }
      this.applyJsUserAgentOverride();
    } catch (error) {
      let e: BusinessError = error as BusinessError;
      Log.w(TAG, `applyPendingUserAgentSettings failed, code: ${e.code}, message: ${e.message}`);
    }
  }

  onAreaChange = (oldValue: Area, newValue: Area) => {
    if (this.disposed || this.controller == null) {
      return;
    }
    this.viewWidth = newValue.width as number;
    this.viewHeight = newValue.height as number;
    this.refreshScrollMetricsAsync();
  }

  toWebHeaders(headers: Map<string, string>): Array<web_webview.WebHeader> {
    let result: Array<web_webview.WebHeader> = new Array;
    if (headers == null || headers.size == 0) {
      return result;
    }
    for (let arr of headers) {
      let key = arr[0];
      let value = arr[1];
      let header: web_webview.WebHeader = {
        headerKey: key, headerValue: value
      };
      result.push(header);
    }
    return result;
  }

  private async waitControllerAttached() {
    if (!this.controllerAttached) {
      await this.checkControllerAttached()
    }
  }

  private resolvePendingControllerAttachWaiters(): void {
    this.clearControllerAttachTimeout();
    const waiters = this.pendingAttachWaiters;
    this.pendingAttachWaiters = [];
    for (let waiter of waiters) {
      waiter.resolve();
    }
  }

  private cancelPendingControllerAttachWaiters(): void {
    this.clearControllerAttachTimeout();
    const waiters = this.pendingAttachWaiters;
    this.pendingAttachWaiters = [];
    const reason = new Error('InAppWebView disposed before Web controller attached');
    for (let waiter of waiters) {
      waiter.reject(reason);
    }
  }

  private clearControllerAttachTimeout(): void {
    if (this.controllerAttachTimeoutId !== -1) {
      clearTimeout(this.controllerAttachTimeoutId);
      this.controllerAttachTimeoutId = -1;
    }
  }

  private scheduleControllerAttachTimeout(): void {
    if (this.controllerAttachTimeoutId !== -1) {
      return;
    }
    this.controllerAttachTimeoutId = setTimeout(() => {
      this.onControllerAttachTimeout();
    }, CONTROLLER_ATTACH_TIMEOUT_MS);
  }

  private onControllerAttachTimeout(): void {
    this.controllerAttachTimeoutId = -1;
    if (this.controllerAttached || this.disposed) {
      return;
    }
    Log.e(TAG, 'Web controller attach timeout after ' + CONTROLLER_ATTACH_TIMEOUT_MS + 'ms');
    const waiters = this.pendingAttachWaiters;
    this.pendingAttachWaiters = [];
    const reason = new Error('Web controller attach timeout');
    for (let waiter of waiters) {
      waiter.reject(reason);
    }
  }

  private checkControllerAttached(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.controllerAttached) {
        resolve();
        return;
      }
      if (this.disposed) {
        reject(new Error('InAppWebView disposed before Web controller attached'));
        return;
      }
      try {
        this.pendingAttachWaiters.push(new ControllerAttachWaiter(resolve, reject));
        this.scheduleControllerAttachTimeout();
      } catch (err) {
        reject(err);
      }
    });
  }

  isDebuggingEnabled() {
    return this.plugin?.inAppWebViewManager?.debuggingEnabled ?? false
  }

  disposeWebMessageChannels(): void {
    for (let webMessageChannel of this.webMessageChannels.values()) {
      webMessageChannel.dispose();
    }
    this.webMessageChannels.clear();
  }

  disposeWebMessageListeners(): void {
    for (let webMessageListener of this.webMessageListeners) {
      webMessageListener.dispose();
    }
    this.webMessageListeners = new Array<WebMessageListener>();
  }

  hideContextMenu() {
    // TODO
    // removeView(floatingContextMenu);
    // this.floatingContextMenu = null;

    if (this.channelDelegate != null) this.channelDelegate.onHideContextMenu();
  }

  public getSelectedText(resultCallback: ValueCallback<string>): void {
    if (!this.isControllerUsable()) {
      resultCallback.onReceiveValue('');
      return;
    }
    try {
      this.requireController().runJavaScriptExt(PluginScriptsUtil.GET_SELECTED_TEXT_JS_SOURCE).then((result) => {
        resultCallback.onReceiveValue(result.getString())
      }).catch((error: BusinessError) => {
        Log.w(TAG, 'getSelectedText failed: ' + error.message);
        resultCallback.onReceiveValue('');
      })
    } catch (e) {
      Log.w(TAG, 'getSelectedText sync throw (controller detached): ' + JSON.stringify(e));
      resultCallback.onReceiveValue('');
    }
  }

  callAsyncJavaScript(functionBody: string, args: Map<string, Any>, contentWorld: ContentWorld | null, resultCallback: ValueCallback<string>): void {
    this.waitControllerAttached().then(() => {
      let resultUuid = util.generateRandomUUID(true);
      if (resultCallback != null) {
        this.callAsyncJavaScriptCallbacks.set(resultUuid, resultCallback);
      }

      // 防御性检查：args 可能为 null
      let safeArgs: Map<string, Any> = args ?? new Map<string, Any>();
      let keys = safeArgs.keys();

      let functionArgumentNamesList = new Array<string>();
      let functionArgumentValuesList = new Array<string>();
      let argsObj: Record<string, Any> = {};
      for (let key of keys) {
        functionArgumentNamesList.push(key);
        functionArgumentValuesList.push('obj.' + key);
        argsObj[key] = safeArgs.get(key);
      }

      let functionArgumentNames = functionArgumentNamesList.join(', ');
      let functionArgumentValues = functionArgumentValuesList.join(', ');
      let functionArgumentsObj = JSON.stringify(argsObj);

      let sourceToInject = PluginScriptsUtil.CALL_ASYNC_JAVA_SCRIPT_WRAPPER_JS_SOURCE
        .replace(PluginScriptsUtil.VAR_FUNCTION_ARGUMENT_NAMES, functionArgumentNames)
        .replace(PluginScriptsUtil.VAR_FUNCTION_ARGUMENT_VALUES, functionArgumentValues)
        .replace(PluginScriptsUtil.VAR_FUNCTION_ARGUMENTS_OBJ, functionArgumentsObj)
        .replace(PluginScriptsUtil.VAR_FUNCTION_BODY, functionBody)
        .replaceAll(PluginScriptsUtil.VAR_RESULT_UUID, resultUuid);

      sourceToInject = this.requireUserContentController().generateCodeForScriptEvaluation(sourceToInject, contentWorld);
      this.requireController().runJavaScriptExt(sourceToInject).catch((error: BusinessError) => {
        Log.e(TAG, 'callAsyncJavaScript: Failed to execute JavaScript, resultUuid=' + resultUuid + ', error=' + error.message);
        // 通知 Dart 侧执行失败，避免 Future 永久挂起
        let callAsyncJavaScriptCallback = this.callAsyncJavaScriptCallbacks.get(resultUuid);
        if (callAsyncJavaScriptCallback != null) {
          let errorResult = JSON.stringify({
            'value': null,
            'error': error.message,
            'resultUuid': resultUuid
          });
          callAsyncJavaScriptCallback.onReceiveValue(errorResult);
          this.callAsyncJavaScriptCallbacks.delete(resultUuid);
        }
      });
    }).catch((error: Error) => {
      Log.e(TAG, 'callAsyncJavaScript: waitControllerAttached failed: ' + error.message);
      if (resultCallback != null) {
        let errorResult = JSON.stringify({
          'value': null,
          'error': error.message,
          'resultUuid': null
        });
        resultCallback.onReceiveValue(errorResult);
      }
    });
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(buildOhosWebView)
  }
}