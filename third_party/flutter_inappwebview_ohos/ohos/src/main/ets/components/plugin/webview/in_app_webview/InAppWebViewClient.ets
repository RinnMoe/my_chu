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

import { Any, Log } from '@ohos/flutter_ohos';
import web_webview from '@ohos.web.webview';
import cameraPicker from '@ohos.multimedia.cameraPicker';
import picker from '@ohos.file.picker';
import uri from '@ohos.uri'
import InAppWebViewFlutterPlugin from '../../InAppWebViewFlutterPlugin';
import DownloadStartRequest from '../../types/DownloadStartRequest';
import URLUtil from '../../types/URLUtil';
import InAppWebView from './InAppWebView';
import WebResourceResponseExt from '../../types/WebResourceResponseExt';
import WebResourceRequestExt from '../../types/WebResourceRequestExt';
import WebResourceResponseHelper from '../../types/WebResourceResponseHelper';
import CustomSchemeResponse from '../../types/CustomSchemeResponse';
import URLRequest from '../../types/URLRequest';
import NavigationAction from '../../types/NavigationAction';
import { NavigationActionPolicy } from '../../types/NavigationActionPolicy';
import { NavigationResponsePolicy } from '../../types/NavigationResponsePolicy';
import URLCredential from '../../types/URLCredential';
import JavaScriptBridgeJS from '../../plugin_scripts_js/JavaScriptBridgeJS';
import WindowOpenAboutBlankJS from '../../plugin_scripts_js/WindowOpenAboutBlankJS';
import { image } from '@kit.ImageKit';
import { InAppBrowserDelegate } from '../../in_app_browser/InAppBrowserDelegate';
import WebResourceErrorExt from '../../types/WebResourceErrorExt';
import { createRawFileWebResponse } from '../../types/WebViewAssetLoader';
import Util from '../../Util';
import {
  GeolocationPermissionsShowPromptCallback,
  JsAlertCallback,
  JsBeforeUnloadCallback,
  JsConfirmCallback,
  JsPromptCallback,
  PermissionRequestCallback,
  ReceivedHttpAuthRequestCallback,
  ReceivedServerTrustAuthRequestCallback,
  ReceivedClientCertRequestCallback,
  CreateWindowCallback,
  FormResubmissionCallback,
  ShouldOverrideUrlLoadingCallback,
  SafeBrowsingHitCallback,
  RenderProcessUnresponsiveCallback,
  RenderProcessResponsiveCallback,
  ShouldInterceptRequestAsyncCallback,
  HybridShouldInterceptRequestCallback,
  SchemeShouldInterceptRequestCallback,
  SyncNavigationResponseCallback
} from '../WebViewChannelDelegate';
import JsAlertResponse from '../../types/JsAlertResponse';
import JsConfirmResponse from '../../types/JsConfirmResponse';
import JsPromptResponse from '../../types/JsPromptResponse';
import HttpAuthResponse from '../../types/HttpAuthResponse';
import { ohosPromptDialogBuilder } from './OhosPromptDialog';
import { promptAction } from '@kit.ArkUI';
import JsBeforeUnloadResponse from '../../types/JsBeforeUnloadResponse';
import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import MimeTypes from '../../MimeTypes';
import PermissionResponse from '../../types/PermissionResponse';
import GeolocationPermissionShowPromptResponse from '../../types/GeolocationPermissionShowPromptResponse';
import CredentialDatabase from '../../credential_database/CredentialDatabase';
import HttpAuthenticationChallenge from '../../types/HttpAuthenticationChallenge';
import URLProtectionSpace from '../../types/URLProtectionSpace';
import ServerTrustAuthResponse from '../../types/ServerTrustAuthResponse';
import ServerTrustChallenge from '../../types/ServerTrustChallenge';
import ClientCertChallenge from '../../types/ClientCertChallenge';
import ClientCertResponse from '../../types/ClientCertResponse';
import CreateWindowAction from '../../types/CreateWindowAction';
import SafeBrowsingResponse from '../../types/SafeBrowsingResponse';
import { cert } from '@kit.DeviceCertificateKit'
import ClientCertUtil, { ClientCertHttpPaths } from '../../ClientCertUtil';
import SyncBaseCallbackResultImpl from '../../types/SyncBaseCallbackResultImpl';
import { ArrayList, List, util } from '@kit.ArkTS';
import { common, Permissions, bundleManager, abilityAccessCtrl } from '@kit.AbilityKit';
import http from '@ohos.net.http';
import RequestBodyReader from '../../types/RequestBodyReader';
import HitTestResult from '../../types/HitTestResult';

const TAG = 'InAppWebViewClient';

function hasRefererHeader(headers: Map<string, string>): boolean {
  if (headers.has('Referer') && headers.get('Referer') !== '') {
    return true;
  }
  if (headers.has('referer') && headers.get('referer') !== '') {
    return true;
  }
  return false;
}

function isHttpOrHttpsUrl(url: string): boolean {
  return url.startsWith('http://') || url.startsWith('https://');
}

// OHOS: after shouldOverrideUrlLoading returns ALLOW, loadUrl(url, headers) re-loads the URL
// and may drop Referer. Android keeps the engine-computed Referer from request.getRequestHeaders().
// Here we supplement from controller.getUrl() (current page URL) when Referer is missing — sufficient
// for merchant-to-WeChat-pay flows; iframe navigation or post-redirect edge cases may differ slightly.
function ensureRefererHeader(inAppWebView: InAppWebView, headers: Map<string, string>): Map<string, string> {
  if (hasRefererHeader(headers)) {
    return headers;
  }
  const result = new Map<string, string>();
  headers.forEach((value: string, key: string) => {
    result.set(key, value);
  });
  try {
    const referer = inAppWebView.getController().getUrl();
    if (referer != null && referer !== '' && isHttpOrHttpsUrl(referer)) {
      result.set('Referer', referer);
      Log.d(TAG, 'shouldOverrideUrlLoading: supplemented Referer=' + referer);
    }
  } catch (e) {
    Log.e(TAG, 'shouldOverrideUrlLoading: failed to supplement Referer', e);
  }
  return result;
}

interface OHOSMessageLevels {
  DEBUG: number;
  ERROR: number;
  INFO: number;
  LOG: number;
  WARN: number;
}

interface DartConsoleMessageLevels {
  TIP: number;
  LOG: number;
  WARNING: number;
  ERROR: number;
  DEBUG: number;
}

// dispose 时强制 forceCancel 兜底。
export interface IPendingJsDialog {
  forceCancel(): void;
}

// 参考文档 所有事件 https://docs.openharmony.cn/pages/v4.1/zh-cn/application-dev/reference/apis-arkweb/ts-basic-components-web.md#onalert
export default class InAppWebViewClient {
  public previousAuthRequestFailureCount = 0;
  public credentialsProposed: List<URLCredential> | null = null;
  private plugin: InAppWebViewFlutterPlugin | null = null;
  private inAppWebView: InAppWebView | null = null;
  private inAppBrowserDelegate: InAppBrowserDelegate | null = null;
  private fullScreenExitHandler: FullScreenExitHandler | null = null;
  private disposed: boolean = false;
  private pendingJsDialogs: Set<IPendingJsDialog> = new Set();
  private isOriginalLayoutFullScreen = false;
  private isOriginalFullScreen = false;
  // After onNavigationResponse ALLOW, re-loadUrl must skip the policy check once
  // (onLoadIntercept fires for programmatic loadUrl; returning false after a sync
  // Dart round-trip does not reliably resume the original request on ArkWeb).
  private skipNextNavigationResponseCheck: boolean = false;
  /** Debounce console-fallback synthesize vs native onWindowNew for about:blank. */
  private lastAboutBlankCreateWindowMs: number = 0;
  public progress = 0;
  private permissionValues: Map<string, Permissions> = new Map([
    ['TYPE_VIDEO_CAPTURE', 'ohos.permission.CAMERA'],// 视频捕获资源，例如相机。
    ['TYPE_AUDIO_CAPTURE', 'ohos.permission.MICROPHONE'],// 音频捕获资源，例如麦克风。
  // ['TYPE_MIDI_SYSEX', 'ohos.permission.MIDI_SYSEX'],// MIDI SYSEX资源
  // ['TYPE_SENSOR', 'ohos.permission.SENSOR'] // 传感器资源，例如加速度传感器。
  ]);

  constructor(plugin: InAppWebViewFlutterPlugin, inAppWebView: InAppWebView) {
    this.plugin = plugin;
    this.inAppWebView = inAppWebView;
  }

  public registerPendingJsDialog(dialog: IPendingJsDialog): void {
    this.pendingJsDialogs.add(dialog);
  }

  public unregisterPendingJsDialog(dialog: IPendingJsDialog): void {
    this.pendingJsDialogs.delete(dialog);
  }

  dispose(): void {
    if (this.pendingJsDialogs.size > 0) {
      Log.i(TAG, 'dispose: force-cancel ' + this.pendingJsDialogs.size + ' pending JS dialog(s)');
    }
    let pending: Array<IPendingJsDialog> = new Array<IPendingJsDialog>();
    this.pendingJsDialogs.forEach((dialog: IPendingJsDialog) => {
      pending.push(dialog);
    });
    for (let dialog of pending) {
      try {
        dialog.forceCancel();
      } catch (e) {
        Log.e(TAG, 'dispose: forceCancel failed: ' + JSON.stringify(e));
      }
    }
    this.pendingJsDialogs.clear();
    this.permissionValues.clear();

    this.credentialsProposed = null;
    this.previousAuthRequestFailureCount = 0;
    if (this.fullScreenExitHandler != null) {
      try {
        this.fullScreenExitHandler.exitFullScreen();
      } catch (e) {
        Log.e(TAG, 'dispose: exitFullScreen failed: ' + JSON.stringify(e));
      }
      this.fullScreenExitHandler = null;
    }
    this.disposed = true;
    this.inAppBrowserDelegate = null;
    this.inAppWebView = null;
    this.plugin = null;
  }

  /**
   * 当 Dart 在 shouldInterceptRequest 中返回空值时，尝试从本地资源加载；
   * 仅对远程 http(s) URL 才回退到 HTTP 请求。
   */
  private fetchOriginalResource(
    request: WebResourceRequestExt,
    webResourceResponse: WebResourceResponse,
    requestBodyPromise?: Promise<ArrayBuffer | null>
  ): void {
    const requestUrl = request.getUrl();
    if (this.tryFetchFromLocalSource(requestUrl, webResourceResponse)) {
      return;
    }
    if (!this.isRemoteHttpUrl(requestUrl)) {
      Log.e(TAG, 'Cannot fetch non-http local resource: ' + requestUrl);
      webResourceResponse.setResponseCode(404);
      webResourceResponse.setResponseData('');
      webResourceResponse.setResponseIsReady(true);
      return;
    }

    this.runRemoteHttpFallback(request, requestBodyPromise, (resp: http.HttpResponse) => {
      try {
        WebResourceResponseHelper.applyHttpResponseToWebResourceResponse(webResourceResponse, resp);
      } catch (e) {
        Log.e(TAG, 'Error setting fetched response: ' + e);
      }
      webResourceResponse.setResponseIsReady(true);
    }, () => {
      webResourceResponse.setResponseCode(502);
      webResourceResponse.setResponseData('');
      webResourceResponse.setResponseIsReady(true);
    });
  }

  /**
   * Shared HTTP fallback for onInterceptRequest and WebSchemeHandler paths.
   */
  private runRemoteHttpFallback(
    request: WebResourceRequestExt,
    requestBodyPromise: Promise<ArrayBuffer | null> | undefined,
    onResponse: (resp: http.HttpResponse) => void,
    onFailure: () => void
  ): void {
    const performHttpRequest = (requestBody: ArrayBuffer | null) => {
      try {
        let httpRequest = http.createHttp();
        let headerObj: Record<string, string> = {};
        request.getHeaders().forEach((value: string, key: string) => {
          headerObj[key] = value;
        });

        let methodMap: Map<string, string> = new Map([
          ['GET', 'GET'],
          ['POST', 'POST'],
          ['PUT', 'PUT'],
          ['PATCH', 'PATCH'],
          ['DELETE', 'DELETE'],
          ['HEAD', 'HEAD'],
          ['OPTIONS', 'OPTIONS'],
        ]);
        let methodName = methodMap.get(request.getMethod().toUpperCase()) || 'GET';
        // @ohos.net.http 的 RequestMethod 类型定义（compatibleSdkVersion 12）缺少 PATCH，
        // 但 PATCH 自 API 26 起运行时已支持（见 DevEco 文档 @ohos.net.http RequestMethod）。
        // 对运行时 string 变量做断言可编译通过且运行时按字符串发送。
        let httpMethod = methodName as http.RequestMethod;
        let requestOptions: http.HttpRequestOptions = {
          method: httpMethod,
          header: headerObj,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 30000,
          readTimeout: 30000,
        };
        if (requestBody != null && requestBody.byteLength > 0) {
          requestOptions.extraData = requestBody;
          Log.d(TAG, 'Fallback POST body: ' + requestBody.byteLength + ' bytes');
        } else if (RequestBodyReader.needsRequestBody(request.getMethod())) {
          Log.w(TAG, 'Fallback POST body is empty for ' + request.getUrl());
        }

        httpRequest.request(request.getUrl(), requestOptions).then((resp: http.HttpResponse) => {
          try {
            onResponse(resp);
          } catch (e) {
            Log.e(TAG, 'Error applying HTTP fallback response: ' + e);
            onFailure();
          }
          httpRequest.destroy();
        }).catch((err: Error) => {
          Log.e(TAG, 'Error fetching original resource: ' + (err ? err.message : 'unknown'));
          onFailure();
          httpRequest.destroy();
        });
      } catch (e) {
        Log.e(TAG, 'Error creating HTTP request for fallback: ' + e);
        onFailure();
      }
    };

    if (requestBodyPromise != null && RequestBodyReader.needsRequestBody(request.getMethod())) {
      requestBodyPromise.then((requestBody) => {
        performHttpRequest(requestBody);
      }).catch((error: Error) => {
        Log.e(TAG, 'Failed to resolve request body for fallback: ' + error);
        performHttpRequest(null);
      });
      return;
    }

    performHttpRequest(null);
  }

  /**
   * Remote POST/PUT/PATCH are handled entirely by WebSchemeHandler (return true) so
   * getHttpBodyStream() stays valid. onInterceptRequest returns null for these URLs.
   */
  onSchemeHandlerInterceptRequest(
    schemeRequest: web_webview.WebSchemeHandlerRequest,
    resourceHandler: web_webview.WebResourceHandler
  ): boolean {
    if (!this.isWebViewAlive()) {
      return false;
    }

    let method = schemeRequest.getRequestMethod().toUpperCase();
    let request = WebResourceRequestExt.fromSchemeHandlerRequest(schemeRequest);
    let requestUrl = request.getUrl();

    if (this.shouldBypassLocalNetworkAccessChecks(requestUrl)) {
      if (method === 'OPTIONS') {
        WebResourceResponseHelper.serveCorsPreflightForSchemeHandler(resourceHandler);
        return true;
      }
      if (this.shouldProxyPrivateNetworkRequest(request)) {
        // 用户开启 useShouldInterceptRequest 时先咨询 Dart（与 Android/iOS 语义一致），
        // Dart 返回 null 再走 @ohos.net.http 代理透传，保证私网请求 body 不丢。
        if (this.inAppWebView!.customSettings.useShouldInterceptRequest &&
            this.inAppWebView!.channelDelegate != null) {
          let requestBodyPromise = RequestBodyReader.startReadingFromSchemeRequest(schemeRequest);
          let onNullResponse = () => {
            this.fetchOriginalResourceForSchemeHandler(request, resourceHandler, requestBodyPromise);
          };
          let callback = new SchemeShouldInterceptRequestCallback(resourceHandler, onNullResponse);
          this.inAppWebView!.channelDelegate.shouldInterceptRequestAsync(request, callback);
          return true;
        }
        if (RequestBodyReader.needsRequestBody(method)) {
          let requestBodyPromise = RequestBodyReader.startReadingFromSchemeRequest(schemeRequest);
          this.fetchOriginalResourceForSchemeHandler(request, resourceHandler, requestBodyPromise);
          return true;
        }
        if (method === 'GET' || method === 'HEAD') {
          this.fetchOriginalResourceForSchemeHandler(request, resourceHandler);
          return true;
        }
      }
      return false;
    }

    if (!this.inAppWebView!.customSettings.useShouldInterceptRequest) {
      return false;
    }

    if (method !== 'OPTIONS' && !RequestBodyReader.needsRequestBody(method)) {
      return false;
    }
    if (this.inAppWebView!.channelDelegate == null) {
      return false;
    }

    if (method === 'OPTIONS' && this.isRemoteHttpUrl(request.getUrl())) {
      WebResourceResponseHelper.serveCorsPreflightForSchemeHandler(resourceHandler);
      return true;
    }
    if (!this.shouldUseSchemeHandlerForUrl(request.getUrl(), method)) {
      return false;
    }

    let requestBodyPromise = RequestBodyReader.startReadingFromSchemeRequest(schemeRequest);
    let onNullResponse = () => {
      this.fetchOriginalResourceForSchemeHandler(request, resourceHandler, requestBodyPromise);
    };
    let callback = new SchemeShouldInterceptRequestCallback(resourceHandler, onNullResponse);
    this.inAppWebView!.channelDelegate.shouldInterceptRequestAsync(request, callback);
    return true;
  }

  private fetchOriginalResourceForSchemeHandler(
    request: WebResourceRequestExt,
    resourceHandler: web_webview.WebResourceHandler,
    requestBodyPromise?: Promise<ArrayBuffer | null>
  ): void {
    if (!this.isRemoteHttpUrl(request.getUrl())) {
      WebResourceResponseHelper.failResourceHandler(resourceHandler);
      return;
    }

    this.runRemoteHttpFallback(request, requestBodyPromise, (resp: http.HttpResponse) => {
      WebResourceResponseHelper.applyHttpResponseToResourceHandler(resourceHandler, resp);
    }, () => {
      WebResourceResponseHelper.failResourceHandler(resourceHandler);
    });
  }

  private isRemoteHttpUrl(url: string): boolean {
    try {
      let scheme = new uri.URI(url).scheme?.toLowerCase();
      return scheme === 'http' || scheme === 'https';
    } catch (e) {
      return url.startsWith('http://') || url.startsWith('https://');
    }
  }

  /**
   * ArkWeb blocks private-network XHR/fetch with ERR_BLOCKED_BY_LOCAL_NETWORK_ACCESS_CHECKS.
   * Proxy those http(s) requests through @ohos.net.http instead of the renderer network stack.
   */
  /**
   * Subresource GET/POST to private hosts are proxied via @ohos.net.http to bypass LNA.
   * Main-frame navigations stay on the WebView network stack so HTTP auth challenges
   * (onHttpAuthRequest) fire correctly, except loopback hosts used by InAppLocalhostServer.
   */
  private isLoopbackHost(url: string): boolean {
    try {
      let host = new uri.URI(url).host?.toLowerCase();
      return host === 'localhost' || host === '127.0.0.1' || host === '::1';
    } catch (e) {
      return false;
    }
  }

  private shouldProxyPrivateNetworkRequest(request: WebResourceRequestExt): boolean {
    if (request.getForMainFrame()) {
      return this.isLoopbackHost(request.getUrl());
    }
    return true;
  }

  private shouldBypassLocalNetworkAccessChecks(url: string): boolean {
    if (!this.isRemoteHttpUrl(url)) {
      return false;
    }
    try {
      let host = new uri.URI(url).host?.toLowerCase();
      if (host == null || host.length === 0) {
        return false;
      }
      if (host === 'localhost' || host.endsWith('.local')) {
        return true;
      }
      return this.isPrivateIpv4Host(host);
    } catch (e) {
      return false;
    }
  }

  private isPrivateIpv4Host(host: string): boolean {
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
  }

  /**
   * 统一走 Dart shouldInterceptRequest 异步拦截：
   * - 子资源（isForMainFrame false）全异步，不短等；
   * - main frame 短等 50ms，超时后切异步 deferred；
   * - Dart 返回自定义响应则应用并置 ready；
   * - Dart 返回 null / 异常 / channelDelegate 缺失时，同步路径返回 null（放行 ArkWeb 原始加载），
   *   异步路径调用 onNullResponse 兜底（如 fetchOriginalResource 或私网代理）。
   */
  private interceptThroughDart(
    request: WebResourceRequestExt,
    requestBodyPromise: Promise<ArrayBuffer | null> | undefined,
    onNullResponse: (webResourceResponse: WebResourceResponse) => void
  ): WebResourceResponse | null {
    if (this.inAppWebView!.channelDelegate == null) {
      return null;
    }
    try {
      let webResourceResponse = new WebResourceResponse();
      let onNull = () => {
        onNullResponse(webResourceResponse);
      };
      let callback = new HybridShouldInterceptRequestCallback(webResourceResponse, onNull);
      // 子资源 (isForMainFrame false)：不短等，先 switchToAsyncMode 再 invoke，避免和 Dart 快回在同步 success 上打架。
      if (!request.getForMainFrame()) {
        callback.switchToAsyncMode();
        webResourceResponse.setResponseIsReady(false);
        this.inAppWebView!.channelDelegate.shouldInterceptRequestAsync(request, callback);
        return webResourceResponse;
      }

      this.inAppWebView!.channelDelegate.shouldInterceptRequestAsync(request, callback);
      let responded = callback.waitResponseWithTimeout(50);

      if (responded) {
        if (callback.result != null) {
          let result = callback.result!;
          WebResourceResponseHelper.applyBytesToWebResourceResponse(
            webResourceResponse,
            result.getData(),
            result.getContentType() ?? '',
            result.getContentEncoding() ?? ''
          );
          if (result.getStatusCode()) {
            webResourceResponse.setResponseCode(result.getStatusCode());
          }
          if (result.getReasonPhrase()) {
            webResourceResponse.setReasonMessage(result.getReasonPhrase());
          }
          if (result.getHeaders()) {
            webResourceResponse.setResponseHeader(result.getHeaderArray());
          }
          webResourceResponse.setResponseIsReady(true);
          return webResourceResponse;
        } else {
          return null;
        }
      } else {
        callback.switchToAsyncMode();
        webResourceResponse.setResponseIsReady(false);
        return webResourceResponse;
      }
    } catch (e) {
      Log.e(TAG, '', e);
    }
    return null;
  }

  private interceptPrivateNetworkRequest(
    request: WebResourceRequestExt,
    webResourceResponse: WebResourceResponse,
    requestBodyPromise?: Promise<ArrayBuffer | null>
  ): WebResourceResponse {
    webResourceResponse.setResponseIsReady(false);
    this.fetchOriginalResource(request, webResourceResponse, requestBodyPromise);
    return webResourceResponse;
  }

  /**
   * Only remote POST/PUT/PATCH need WebSchemeHandler (readable body).
   * Local flutter assets and plain GET must keep using onInterceptRequest.
   */
  private shouldUseSchemeHandlerForUrl(url: string, method: string): boolean {
    if (!RequestBodyReader.needsRequestBody(method)) {
      return false;
    }
    if (!this.isRemoteHttpUrl(url)) {
      return false;
    }
    if (this.extractFlutterRawFilePath(url) != null) {
      return false;
    }
    if (url.includes('appassets.androidplatform.net')) {
      return false;
    }
    return true;
  }

  /**
   * Extracts a rawfile path from a URL that references Flutter assets.
   * Two patterns are supported with priority: (1) /assets/flutter_assets/ prefix
   * (appassets domain), then (2) bare flutter_assets/ prefix (file:// or other schemes).
   */
  private extractFlutterRawFilePath(url: string): string | null {
    const appAssetsMarker = '/assets/flutter_assets/';
    const appAssetsIdx = url.indexOf(appAssetsMarker);
    if (appAssetsIdx >= 0) {
      return 'flutter_assets/' + url.substring(appAssetsIdx + appAssetsMarker.length);
    }
    const flutterAssetsIdx = url.indexOf('flutter_assets/');
    if (flutterAssetsIdx >= 0) {
      return url.substring(flutterAssetsIdx);
    }
    return null;
  }

  private loadRawFileIntoResponse(rawPath: string, target: WebResourceResponse): void {
    let loaded = createRawFileWebResponse(this.inAppWebView!.context!, rawPath);
    target.setResponseData(loaded.getResponseData());
    target.setResponseMimeType(loaded.getResponseMimeType());
    target.setResponseEncoding(loaded.getResponseEncoding());
    target.setResponseCode(loaded.getResponseCode());
    target.setReasonMessage(loaded.getReasonMessage());
    target.setResponseHeader(loaded.getResponseHeader());
    target.setResponseIsReady(true);
  }

  private tryFetchFromLocalSource(requestUrl: string, target: WebResourceResponse): boolean {
    let rawPath = this.extractFlutterRawFilePath(requestUrl);
    if (rawPath != null) {
      this.loadRawFileIntoResponse(rawPath, target);
      return true;
    }
    return false;
  }

  private isWebViewAlive(): boolean {
    return !this.disposed && this.inAppWebView != null && !this.inAppWebView.isDisposed();
  }

  /**
   * ArkWeb may skip native onBeforeUnload when navigation lacks user gesture (Chromium
   * policy). When the page registered a beforeunload handler, intercept main-frame
   * navigations here and dispatch onJsBeforeUnload to match Android WebView behavior.
   */
  private tryHandleBeforeUnloadNavigationPolyfill(request: WebResourceRequest,
    requestUrl: string): boolean {
    if (!request.isMainFrame() || !this.isWebViewAlive()) {
      return false;
    }
    const webView = this.inAppWebView!;
    if (!webView.hasBeforeUnloadHandler || webView.channelDelegate == null) {
      return false;
    }
    if (webView.beforeUnloadNavigationPending) {
      return false;
    }
    if (webView.beforeUnloadNavigationAllowedUrl === requestUrl) {
      webView.beforeUnloadNavigationAllowedUrl = null;
      return false;
    }
    const currentUrl = webView.getUrl();
    if (currentUrl.length === 0 || currentUrl === requestUrl || requestUrl === 'about:blank') {
      return false;
    }
    Log.d(TAG, 'beforeUnload polyfill intercept: ' + currentUrl + ' -> ' + requestUrl);
    webView.beforeUnloadNavigationPending = true;
    webView.pendingBeforeUnloadTargetUrl = requestUrl;
    const jsResult = new BeforeUnloadNavigationJsResult(webView, requestUrl);
    webView.channelDelegate.onJsBeforeUnload(currentUrl, '',
      new InnerJsBeforeUnloadCallback(this, jsResult as JsResult, ''));
    return true;
  }

  private isTextualCustomSchemeContentType(contentType: string): boolean {
    const lower = contentType.toLowerCase();
    return lower.includes('text/') || lower.includes('json') ||
      lower.includes('javascript') || lower.includes('xml') ||
      lower.includes('css') || lower.includes('html');
  }

  private applyCustomSchemeResponseBody(
    resourceResponse: WebResourceResponse,
    customSchemeResponse: CustomSchemeResponse
  ): void {
    resourceResponse.setResponseMimeType(customSchemeResponse.getContentType());
    resourceResponse.setResponseEncoding(customSchemeResponse.getContentEncoding());
    const data = customSchemeResponse.getData();
    if (data != null && data.byteLength > 0) {
      if (this.isTextualCustomSchemeContentType(customSchemeResponse.getContentType() ?? '')) {
        const uint8 = new Uint8Array(data);
        resourceResponse.setResponseData(util.TextDecoder.create().decodeToString(uint8));
      } else {
        resourceResponse.setResponseData(data);
      }
    } else {
      Log.e(TAG, 'customSchemeResponse data is empty');
      resourceResponse.setResponseData('');
    }
    resourceResponse.setResponseCode(200);
    resourceResponse.setResponseIsReady(true);
  }

  onAlert = (event: OnAlertEvent) => {
    try {
      Log.d(TAG, 'onAlert url=' + event.url)
      if (this.inAppWebView != null && this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onJsAlert(event.url, event.message, null,
          new InnerJsAlertCallback(this, event.result, event.message));
        return true;
      }
    } catch (e) {
      Log.e(TAG, 'onAlert error: ' + JSON.stringify(e));
    }
    return false;
  }
  onBeforeUnload = (event: OnBeforeUnloadEvent) => {
    try {
      Log.d(TAG, 'onBeforeUnload url=' + event.url)
      if (this.inAppWebView != null) {
        this.inAppWebView!.beforeUnloadNavigationPending = true;
      }
      if (this.inAppWebView != null && this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onJsBeforeUnload(event.url, event.message,
          new InnerJsBeforeUnloadCallback(this, event.result, event.message));
        return true;
      }
    } catch (e) {
      Log.e(TAG, 'onBeforeUnload error: ' + JSON.stringify(e));
    }
    return false;
  }
  onConfirm = (event: OnConfirmEvent) => {
    try {
      Log.d(TAG, 'onConfirm url=' + event.url)
      if (this.inAppWebView != null && this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onJsConfirm(event.url, event.message, null,
          new InnerJsConfirmCallback(this, event.result, event.message));
        return true;
      }
    } catch (e) {
      Log.e(TAG, 'onConfirm error: ' + JSON.stringify(e));
    }
    return false;
  }
  onPrompt = (event: OnPromptEvent, uiObject: Object) => {
    try {
      Log.d(TAG, 'onPrompt url=' + event.url)
      if (this.inAppWebView != null && this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onJsPrompt(event.url, event.message, event.value, null,
          new InnerJsPromptCallback(this, event.result, event.message, event.value, uiObject));
        return true;
      }
    } catch (e) {
      Log.e(TAG, 'onPrompt error: ' + JSON.stringify(e));
    }
    return false;
  }
  onConsole = (event: OnConsoleEvent) => {
    try {
      Log.d(TAG, 'onConsole=' + JSON.stringify(event))
      let consoleMessage: string = '';
      try {
        consoleMessage = event.message.getMessage();
      } catch (msgErr) {
        Log.e(TAG, 'onConsole getMessage failed: ' + JSON.stringify(msgErr));
        return false;
      }
      if (consoleMessage != null &&
        consoleMessage.indexOf(WindowOpenAboutBlankJS.CONSOLE_PREFIX) >= 0 &&
        this.inAppWebView != null &&
        this.inAppWebView!.customSettings.multiWindowAccess &&
        this.inAppWebView!.customSettings.allowWindowOpenMethod) {
        Log.d(TAG, 'onConsole window.open about:blank hook → synthesize');
        this.synthesizeAboutBlankCreateWindow();
        return true;
      }
      if (this.inAppWebView != null && this.inAppWebView!.channelDelegate != null) {
        let messageLevel: number = this.mapMessageLevel(event.message.getMessageLevel());
        this.inAppWebView!.channelDelegate.onConsoleMessage(consoleMessage, messageLevel);
        return true;
      }
    } catch (e) {
      Log.e(TAG, 'onConsole error: ' + JSON.stringify(e));
    }
    return false;
  }

  /**
   * Maps OHOS native MessageLevel to Dart-side ConsoleMessageLevel.
   *
   * OHOS native MessageLevel enum values (from @ohos.web.webview):
   *   Debug = 1, Error = 4, Info = 2, Log = 5, Warn = 3
   *
   * Dart ConsoleMessageLevel enum values (aligned with Android):
   *   TIP = 0, LOG = 1, WARNING = 2, ERROR = 3, DEBUG = 4
   */
  private static readonly OHOS_MSG: OHOSMessageLevels = {
    DEBUG: 1, ERROR: 4, INFO: 2, LOG: 5, WARN: 3
  };
  private static readonly DART_MSG: DartConsoleMessageLevels = {
    TIP: 0, LOG: 1, WARNING: 2, ERROR: 3, DEBUG: 4
  };

  private mapMessageLevel(nativeLevel: number): number {
    switch (nativeLevel) {
      case InAppWebViewClient.OHOS_MSG.DEBUG:
        return InAppWebViewClient.DART_MSG.DEBUG;
      case InAppWebViewClient.OHOS_MSG.ERROR:
        return InAppWebViewClient.DART_MSG.ERROR;
      case InAppWebViewClient.OHOS_MSG.INFO:
        return InAppWebViewClient.DART_MSG.LOG;
      case InAppWebViewClient.OHOS_MSG.LOG:
        return InAppWebViewClient.DART_MSG.LOG;
      case InAppWebViewClient.OHOS_MSG.WARN:
        return InAppWebViewClient.DART_MSG.WARNING;
      default:
        return InAppWebViewClient.DART_MSG.LOG;
    }
  }
  onDownloadStart = (event: OnDownloadStartEvent) => { //对应安卓setDownloadListener
    try {
      Log.d(TAG, 'onDownloadStart=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      if (this.inAppWebView!.customSettings.useOnDownloadStart) {
        let downloadStartRequest = new DownloadStartRequest(
          event.url,
          event.userAgent,
          event.contentDisposition,
          event.mimetype,
          event.contentLength,
          URLUtil.guessFileName(event.url, event.contentDisposition, event.mimetype),
          null
        );
        this.inAppWebView!.channelDelegate?.onDownloadStartRequest(downloadStartRequest)
      }
    } catch (e) {
      Log.e(TAG, 'onDownloadStart error: ' + JSON.stringify(e));
    }
  }
  onErrorReceive = (event: OnErrorReceiveEvent) => {
    try {
      Log.d(TAG, 'onErrorReceive=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      let request: WebResourceRequest = event.request;
      let error: WebResourceError = event.error;
      if (request.isMainFrame()) {
        this.inAppWebView!.clearNavigateBackFlag();
        this.inAppWebView!.pendingSkipAfterRedirectBlock = false;
        this.inAppWebView!.pendingSkipDirection = 0;
        if (this.inAppWebView!.customSettings.disableDefaultErrorPage) {
          this.inAppWebView!.stopLoading();
          this.inAppWebView!.getController().loadUrl('about:blank');
        }

        this.inAppWebView!.isLoading = false;
        this.previousAuthRequestFailureCount = 0;
        this.credentialsProposed = null;

        if (this.inAppBrowserDelegate != null) {
          let type = error.getErrorCode();
          let description = error.getErrorInfo();
          this.inAppBrowserDelegate.didFailNavigation(request.getRequestUrl(), type, description);
        }
      }
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onReceivedError(
          WebResourceRequestExt.fromWebResourceRequest(request),
          WebResourceErrorExt.fromWebResourceError(error));
      }
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'onErrorReceive error: ' + JSON.stringify(err));
    }
  }
  onHttpErrorReceive = (event: OnHttpErrorReceiveEvent) => {
    Log.d(TAG, 'onHttpErrorReceive=' + JSON.stringify(event))
    if (!this.isWebViewAlive()) {
      return;
    }
    if (this.inAppWebView!.channelDelegate == null) {
      return;
    }
    try {
      let request: WebResourceRequest = event.request;
      let response: WebResourceResponse = event.response;
      if (request == null || response == null) {
        Log.e(TAG, 'onHttpErrorReceive: request or response is null');
        return;
      }
      this.inAppWebView!.channelDelegate.onReceivedHttpError(
        WebResourceRequestExt.fromWebResourceRequest(request),
        WebResourceResponseExt.fromWebResourceResponse(response));
    } catch (e) {
      Log.e(TAG, 'onHttpErrorReceive failed', e as Error);
    }
  }
  onPageBegin = (event: OnPageBeginEvent) => {
    try {
      Log.d(TAG, 'onPageBegin=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      this.inAppWebView!.hasBeforeUnloadHandler = false;
      this.inAppWebView!.beforeUnloadNavigationPending = false;
      this.inAppWebView!.pendingBeforeUnloadTargetUrl = null;
      this.inAppWebView!.isLoading = true;
      this.inAppWebView!.resetLoadStopTracking();
      this.inAppWebView!.disposeWebMessageChannels();
      this.inAppWebView!.userContentController!.resetContentWorlds();
      this.loadCustomJavaScriptOnPageStarted(this.inAppWebView!);
      this.inAppWebView!.applyTransparentBackgroundToPage();

      if (this.inAppBrowserDelegate != null) {
        this.inAppBrowserDelegate.didStartNavigation(event.url);
      }

      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onLoadStart(event.url);
      }
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'onPageBegin error: ' + JSON.stringify(err));
    }
  }
  onPageEnd = (event: OnPageEndEvent) => {
    try {
      Log.d(TAG, 'onPageEnd=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      let clientCertLoadStopAlreadyDispatched = false;
      if (this.inAppWebView!.clientCertHttpFallbackPending) {
        // Keep deferring until waitForClientCertPageReadyThenDispatchLoadStop releases.
        Log.d(TAG, 'onPageEnd: deferring during client cert HTTP fallback');
        return;
      } else if (this.inAppWebView!.clientCertLoadStopDispatched) {
        // Poller already dispatched loadStop; skip duplicate data: dispatch.
        clientCertLoadStopAlreadyDispatched = true;
        this.inAppWebView!.clientCertLoadStopDispatched = false;
      }
      this.inAppWebView!.clearNavigateBackFlag();
      this.inAppWebView!.syncCurUrlFromPageEnd(event.url as string);
      if (this.inAppWebView!.pendingSkipAfterRedirectBlock) {
        this.inAppWebView!.pendingSkipAfterRedirectBlock = false;
        let skipDirection = this.inAppWebView!.pendingSkipDirection;
        this.inAppWebView!.pendingSkipDirection = 0;
        if (skipDirection === -1 && this.inAppWebView!.canGoBack()) {
          Log.d(TAG, 'Auto-skipping intermediate page after redirect block, calling goBack again');
          this.inAppWebView!.goBack();
          return;
        } else if (skipDirection === 1 && this.inAppWebView!.canGoForward()) {
          Log.d(TAG, 'Auto-skipping intermediate page after redirect block, calling goForward again');
          this.inAppWebView!.goForward();
          return;
        }
      }
      if (this.inAppWebView!.channelDelegate != null && !clientCertLoadStopAlreadyDispatched) {
        this.loadCustomJavaScriptOnPageFinished(this.inAppWebView!);
        this.inAppWebView!.tryDispatchLoadStopIfNeeded(event.url as string);
      } else {
        this.loadCustomJavaScriptOnPageFinished(this.inAppWebView!);
      }
      this.installWindowOpenAboutBlankHookIfNeeded();
      if (this.inAppWebView != null) {
        this.inAppWebView!.notifyLoadDataPageReady();
      }
      this.inAppWebView!.isLoading = false;
      this.inAppWebView!.applyJsUserAgentOverride();
      this.inAppWebView!.applyTransparentBackgroundToPage();
      this.previousAuthRequestFailureCount = 0;
      this.credentialsProposed = null;

      if (this.inAppBrowserDelegate != null) {
        this.inAppBrowserDelegate.didFinishNavigation(event.url);
      }

      web_webview.WebCookieManager.saveCookieAsync()

      if (this.inAppWebView!.inAppBrowserDelegate != null) {
        const platformReadyTimer = setTimeout(() => {
          if (!this.isWebViewAlive()) {
            return;
          }
          this.inAppWebView!.getController().runJavaScriptExt(
            JavaScriptBridgeJS.PLATFORM_READY_IN_APP_BROWSER_JS_SOURCE);
        }, 50);
        this.inAppWebView!.pendingTimers.push(platformReadyTimer);
      } else if (this.inAppWebView!.controller != null) {
        let js = JavaScriptBridgeJS.PLATFORM_READY_JS_SOURCE;
        this.inAppWebView!.getController().runJavaScriptExt(js);
      }
      this.inAppWebView!.refreshScrollMetricsAsync();
      try {
        this.inAppWebView!.contentBlockerHandler.applyCssDisplayNoneRulesOnPageLoad(this.inAppWebView!);
      } catch (e) {
        Log.e(TAG, 'applyCssDisplayNoneRulesOnPageLoad failed', e);
      }
    } catch (e) {
      Log.e(TAG, 'onPageEnd error: ' + JSON.stringify(e));
    }
  }
  onProgressChange = (event: OnProgressChangeEvent) => {
    try {
      Log.d(TAG, 'onProgressChange=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      if (this.inAppBrowserDelegate != null) {
        this.inAppBrowserDelegate.didChangeProgress(event.newProgress);
      }
      this.progress = event.newProgress
      this.loadCustomJavaScriptOnPageStarted(this.inAppWebView!);
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onProgressChanged(event.newProgress);
      }
      if (event.newProgress >= 100 && this.inAppWebView!.isLoading) {
        this.inAppWebView!.tryDispatchLoadStopIfNeeded(this.inAppWebView!.getUrl());
      }
    } catch (e) {
      Log.e(TAG, 'onProgressChange error: ' + JSON.stringify(e));
    }
  }
  onTitleReceive = (event: OnTitleReceiveEvent) => {
    try {
      Log.d(TAG, 'onTitleReceive=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      if (this.inAppBrowserDelegate != null) {
        this.inAppBrowserDelegate.didChangeTitle(event.title);
      }
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onTitleChanged(event.title);
      }
    } catch (e) {
      Log.e(TAG, 'onTitleReceive error: ' + JSON.stringify(e));
    }
  }
  onRefreshAccessedHistory = (event: OnRefreshAccessedHistoryEvent) => {
    try {
      Log.d(TAG, 'onRefreshAccessedHistory=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      if (this.inAppBrowserDelegate != null) {
        this.inAppBrowserDelegate.didUpdateVisitedHistory(event.url);
      }
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onUpdateVisitedHistory(event.url, event.isRefreshed);
      }
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'onRefreshAccessedHistory error: ' + JSON.stringify(err));
    }
  }
  onRenderExited = (event: OnRenderExitedEvent) => {
    try {
      Log.d(TAG, 'onRenderExited=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      if (this.inAppWebView!.customSettings.useOnRenderProcessGone && this.inAppWebView!.channelDelegate != null) {
        let didCrash = event.renderExitReason == RenderExitReason.ProcessCrashed;
        this.inAppWebView!.channelDelegate.onRenderProcessGone(didCrash, event.renderExitReason);
      }
    } catch (e) {
      Log.e(TAG, 'onRenderExited error: ' + JSON.stringify(e));
    }
  }
  onShowFileSelector = (event: OnShowFileSelectorEvent) => {
    Log.d(TAG, 'onShowFileSelector=' + JSON.stringify(event))
    Log.d(TAG, 'onShowFileSelector=' + JSON.stringify(event.fileSelector))
    if (!this.isWebViewAlive()) {
      return false;
    }
    let acceptTypes: Array<string> = event.fileSelector.getAcceptType();
    let allowMultiple = event.fileSelector.getMode() == FileSelectorMode.FileOpenMultipleMode;
    let captureEnabled: boolean = event.fileSelector.isCapture();
    let images = this.acceptsImages(acceptTypes);
    let video = this.acceptsVideo(acceptTypes);
    if (captureEnabled) {
      if (!this.needsCameraPermission()) {
        if (images || video) {
          let pickerProfile: cameraPicker.PickerProfile = {
            cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
          };
          cameraPicker.pick(this.inAppWebView!.context!,
            images ? [cameraPicker.PickerMediaType.PHOTO] : [cameraPicker.PickerMediaType.VIDEO], pickerProfile)
            .then(result => {
              event.result.handleFileList([result.resultUri]);
            }).catch((err: BusinessError) => {
            event.result.handleFileList([]);
            Log.e(TAG, `the pick call failed. error code: ${err.code}`);
          });
          return true;
        }
      }
    }

    return false;
  }
  onResourceLoad = (event: OnResourceLoadEvent) => {
    // TODO 没有找到安卓对于方法
    Log.d(TAG, 'onResourceLoad=' + JSON.stringify(event))
  }
  onScaleChange = (event: OnScaleChangeEvent) => {
    try {
      Log.d(TAG, 'onScaleChange=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      this.inAppWebView!.zoomScale = event.newScale / Util.getPixelDensity();

      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onZoomScaleChanged(event.oldScale, event.newScale);
      }
    } catch (e) {
      Log.e(TAG, 'onScaleChange error: ' + JSON.stringify(e));
    }
  }
  onInterceptRequest = (event: OnInterceptRequestEvent) => { //对应安卓shouldInterceptRequest
    try {
      if (!this.isWebViewAlive()) {
        return null;
      }
      let request = WebResourceRequestExt.fromWebResourceRequest(event.request);
      Log.d(TAG, 'onInterceptRequest=' + JSON.stringify(event))
      if (this.shouldBypassLocalNetworkAccessChecks(request.getUrl())) {
        let method = request.getMethod().toUpperCase();
        if (method === 'OPTIONS') {
          return WebResourceResponseHelper.buildCorsPreflightResponse();
        }
        if (!RequestBodyReader.needsRequestBody(method)) {
          if (this.shouldProxyPrivateNetworkRequest(request)) {
            // 与 Android/iOS 对齐：私网子资源 / loopback 主框架请求开启拦截时先咨询 Dart，
            // Dart 返回 null 再走 @ohos.net.http 代理（保持私网可访问，body 不涉及）。
            if (this.inAppWebView!.customSettings.useShouldInterceptRequest &&
              this.inAppWebView!.channelDelegate != null) {
              return this.interceptThroughDart(request, undefined, (webResourceResponse) => {
                this.interceptPrivateNetworkRequest(request, webResourceResponse);
              });
            }
            return this.interceptPrivateNetworkRequest(request, new WebResourceResponse());
          }
          return null;
        }
      }
      if (this.inAppWebView!.customSettings.useShouldInterceptRequest &&
        request.getMethod().toUpperCase() === 'OPTIONS' &&
        this.isRemoteHttpUrl(request.getUrl())) {
        return WebResourceResponseHelper.buildCorsPreflightResponse();
      }
      if (this.inAppWebView!.customSettings.useShouldInterceptRequest &&
        this.shouldUseSchemeHandlerForUrl(request.getUrl(), request.getMethod())) {
        // Scheme handler owns POST/PUT/PATCH with readable body; do not claim here.
        return null;
      }
      let requestBodyPromise = RequestBodyReader.needsRequestBody(request.getMethod())
        ? RequestBodyReader.startReading(event.request)
        : undefined;
      if (this.inAppWebView!.webViewAssetLoaderExt != null && this.inAppWebView!.webViewAssetLoaderExt.loader != null) {
        try {
          let url = new uri.URI(request.getUrl());
          let webResourceResponse = this.inAppWebView!.webViewAssetLoaderExt.loader.shouldInterceptRequest(url);
          if (webResourceResponse != null) {
            return webResourceResponse;
          }
        } catch (e) {
          Log.e(TAG, '', e);
        }
      }
      if (this.inAppWebView!.customSettings.useShouldInterceptRequest) {
        return this.interceptThroughDart(request, requestBodyPromise, (webResourceResponse) => {
          this.fetchOriginalResource(request, webResourceResponse, requestBodyPromise);
        });
      }

      let url: string = request.getUrl();
      let scheme: string | null = null;
      try {
        const parsedScheme = new uri.URI(url).scheme;
        if (parsedScheme != null && parsedScheme.length > 0) {
          scheme = parsedScheme.toLowerCase();
        }
      } catch (e) {
        Log.e(TAG, 'Failed to parse URL scheme: ' + url, e);
      }
      if (scheme == null) {
        const match = url.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):/);
        if (match != null && match.length > 1) {
          scheme = match[1].toLowerCase();
        }
      }

      if (scheme != null &&
        this.inAppWebView!.customSettings.resourceCustomSchemes != null &&
        this.inAppWebView!.customSettings.resourceCustomSchemes.indexOf(scheme) > -1) {
        if (this.inAppWebView!.channelDelegate != null) {
          try {
            let customSchemeResponse =
              this.inAppWebView!.channelDelegate.onLoadResourceWithCustomScheme(request);
            if (customSchemeResponse != null) {
              let resourceResponse = new WebResourceResponse();
              let contentBlockerResponse: WebResourceResponse | null = null;
              try {
                contentBlockerResponse = this.inAppWebView!.contentBlockerHandler.checkUrl(this.inAppWebView!, request,
                  customSchemeResponse.getContentType());
              } catch (e) {
                Log.e(TAG, '', e);
              }
              if (contentBlockerResponse != null) {
                resourceResponse.setResponseData(contentBlockerResponse.getResponseData())
                resourceResponse.setResponseMimeType(contentBlockerResponse.getResponseMimeType())
                resourceResponse.setResponseEncoding(contentBlockerResponse.getResponseEncoding())
                resourceResponse.setResponseCode(contentBlockerResponse.getResponseCode())
                resourceResponse.setReasonMessage(contentBlockerResponse.getReasonMessage())
                resourceResponse.setResponseHeader(contentBlockerResponse.getResponseHeader())
                resourceResponse.setResponseIsReady(true)
              } else {
                this.applyCustomSchemeResponseBody(resourceResponse, customSchemeResponse);
              }
              return resourceResponse;
            }
          } catch (e) {
            Log.e(TAG, '', e);
          }
          return null;
        }
      }

      let response: WebResourceResponse | null = null;
      if (this.inAppWebView!.contentBlockerHandler.getRuleList().length > 0) {
        try {
          response = this.inAppWebView!.contentBlockerHandler.checkUrl(this.inAppWebView!, request);
        } catch (e) {
          Log.e(TAG, '', e);
        }
      }
      Log.d(TAG, 'onInterceptRequestend= end')
      return response;
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'onInterceptRequest error', err);
      return null;
    }
  }
  onHttpAuthRequest = (event: OnHttpAuthRequestEvent) => {
    try {
      Log.d(TAG, 'onHttpAuthRequest=' + JSON.stringify(event))
      this.onReceivedHttpAuthRequest(event.handler, event.host, event.realm)
      return true;
    } catch (e) {
      Log.e(TAG, 'onHttpAuthRequest error: ' + JSON.stringify(e));
      return true;
    }
  }
  onSslErrorEventReceive = (event: OnSslErrorEventReceiveEvent) => {
    try {
      Log.d(TAG, 'onSslErrorEventReceive=' + JSON.stringify(event))
      this.onReceivedSslErrorEventReceive(event.handler, event.error)
    } catch (e) {
      Log.e(TAG, 'onSslErrorEventReceive error: ' + JSON.stringify(e));
    }
  }
  onClientAuthenticationRequest = (event: OnClientAuthenticationEvent) => {
    try {
      Log.d(TAG, 'onClientAuthenticationRequest=' + JSON.stringify(event))
      this.onReceivedClientAuthenticationRequest(event.handler, event.host, event.port, event.keyTypes, event.issuers)
    } catch (e) {
      Log.e(TAG, 'onClientAuthenticationRequest error: ' + JSON.stringify(e));
    }
  }
  onPermissionRequest = (event: OnPermissionRequestEvent) => {
    try {
    const _this = this;
    if (_this.inAppWebView != null && _this.inAppWebView!.channelDelegate != null) {

      const request = event.request;
      // 先通知 Dart 层，让 Dart 回调决定 GRANT 还是 DENY。
      // 如果 Dart 返回 GRANT，再检查/请求系统级权限；如果 Dart 返回 DENY，直接拒绝。
      _this.inAppWebView!.channelDelegate?.onPermissionRequest(
        request.getOrigin(),
        request.getAccessibleResource(),
        null,
        new InnerPermissionRequestCallback(request, _this)
      );
    } else {
      event.request.deny();
    }
    Log.d(TAG, 'onPermissionRequest=' + JSON.stringify(event))
    } catch (e) {
      Log.e(TAG, 'onPermissionRequest error: ' + JSON.stringify(e));
    }
  }
  onContextMenuShow = (event: OnContextMenuShowEvent) => {
    try {
      Log.d(TAG, 'onContextMenuShow=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return true;
      }
      let hv: web_webview.HitTestValue = this.inAppWebView!.getController().getHitTestValue();
      this.inAppWebView!.lastContextMenuLinkUrl = hv.extra;
      this.inAppWebView!.lastContextMenuSourceUrl = null;
      this.inAppWebView!.lastContextMenuHitTestType = hv.type;
      Log.w(TAG, 'onContextMenuShow stored extra=' + hv.extra + ' type=' + hv.type);
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onLongPressHitTestResult(event as Object as HitTestResult);
        return false;
      }
      return true;
    } catch (e) {
      Log.e(TAG, 'onContextMenuShow error: ' + JSON.stringify(e));
      return true;
    }
  }
  onContextMenuHide = () => {
    try {
      Log.d(TAG, 'onContextMenuHide=')
      if (this.inAppWebView != null && this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onHideContextMenu();
      }
    } catch (e) {
      Log.e(TAG, 'onContextMenuHide error: ' + JSON.stringify(e));
    }
  }
  onScroll = (event: OnScrollEvent) => {
    try {
      Log.d(TAG, 'onScroll=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      this.inAppWebView!.updateScrollPositionFromNative(event.xOffset, event.yOffset);
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onScrollChanged(event.xOffset,
          event.yOffset);
      }
    } catch (e) {
      Log.e(TAG, 'onScroll error: ' + JSON.stringify(e));
    }
  }
  onGeolocationShow = (event: OnGeolocationShowEvent) => {
    try {
      Log.d(TAG, 'onGeolocationShow=' + JSON.stringify(event))
      const origin: string = event.origin as string;
      const geolocation: JsGeolocationHandler = event.geolocation as JsGeolocationHandler;
      if (this.inAppWebView == null || this.inAppWebView!.channelDelegate == null) {
        geolocation.invoke(origin, false, false);
        return;
      }
      this.inAppWebView!.geolocationShowHandled = true;
      this.inAppWebView!.channelDelegate.onGeolocationPermissionsShowPrompt(origin,
        new InnerGeolocationPermissionsShowPromptCallback(origin, geolocation));
      const locationPermissions: Permissions[] = [
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION'
      ];
      this.requestPermissions(locationPermissions).catch((error: BusinessError) => {
        Log.w(TAG, 'onGeolocationShow requestPermissions failed: ' + JSON.stringify(error));
      });
    } catch (e) {
      Log.e(TAG, 'onGeolocationShow error: ' + JSON.stringify(e));
    }
  }
  onGeolocationHide = () => {
    Log.d(TAG, 'onGeolocationHide=')
    if (this.inAppWebView != null && this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.channelDelegate.onGeolocationPermissionsHidePrompt();
    }
  }

  public dispatchManualGeolocationPrompt(origin: string): void {
    if (this.inAppWebView == null || this.inAppWebView!.channelDelegate == null) {
      return;
    }
    this.inAppWebView!.geolocationShowHandled = true;
    this.inAppWebView!.channelDelegate.onGeolocationPermissionsShowPrompt(origin,
      new ManualGeolocationPermissionsShowPromptCallback(origin));
  }

  onFullScreenEnter = (event: FullScreenEnterEvent) => {
    try {
      if (!this.isWebViewAlive()) {
        return;
      }
      let context = this.inAppWebView!.context! as common.UIAbilityContext;
      let windowClass = context.windowStage.getMainWindowSync();
      let windowProperties = windowClass.getWindowProperties();
      this.isOriginalLayoutFullScreen = windowProperties.isLayoutFullScreen;
      this.isOriginalFullScreen = windowProperties.isFullScreen;
      windowClass.setWindowLayoutFullScreen(true)
      windowClass.setWindowSystemBarEnable([])
      this.fullScreenExitHandler = event.handler
      Log.d(TAG, 'onFullScreenEnter=' + JSON.stringify(event))
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onEnterFullscreen();
      }
      this.inAppWebView!.setInFullscreen(true);
    } catch (e) {
      Log.e(TAG, 'onFullScreenEnter error: ' + JSON.stringify(e));
    }
  }
  onFullScreenExit = () => {
    try {
      Log.d(TAG, 'onFullScreenExit=')
      if (!this.isWebViewAlive()) {
        return;
      }
      let context = this.inAppWebView!.context! as common.UIAbilityContext;
      let windowClass = context.windowStage.getMainWindowSync();
      windowClass.setWindowLayoutFullScreen(this.isOriginalLayoutFullScreen)
      windowClass.setWindowSystemBarEnable(this.isOriginalFullScreen ? [] : ['status', 'navigation'])
      if (this.fullScreenExitHandler) {
        this.fullScreenExitHandler.exitFullScreen()
      }
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onExitFullscreen();
      }
      this.inAppWebView!.setInFullscreen(false);
    } catch (e) {
      Log.e(TAG, 'onFullScreenExit error: ' + JSON.stringify(e));
    }
  }
  onWindowNew = (event: OnWindowNewEvent) => {
    try {
      Log.d(TAG, 'onWindowNew=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      // NOTE: This callback is only registered on the OHOS Web component when
      // multiWindowAccess is true (see OhosWebView.ets). When multiWindowAccess
      // is false, OHOS handles window.open() internally by navigating the
      // current window, preserving the back/forward history.
      try {
        event.handler.setWebController(null);
      } catch (error) {
        Log.e(TAG, 'onWindowNew clear handler failed: ' + JSON.stringify(error));
      }
    let targetUrl: string = event.targetUrl;
    const isAboutBlankTarget: boolean =
      targetUrl == null || targetUrl.length === 0 || targetUrl === 'about:blank';
    // Console-hook may have already synthesized create-window for about:blank.
    if (isAboutBlankTarget && (Date.now() - this.lastAboutBlankCreateWindowMs) < 800) {
      Log.d(TAG, 'onWindowNew about:blank skipped (already synthesized)');
      return;
    }
    let windowId = 0;
    let popupController = new web_webview.WebviewController();
    if (this.plugin != null && this.plugin!.inAppWebViewManager != null) {
      let manager = this.plugin!.inAppWebViewManager;
      manager.cleanupStaleWindowState();
      manager.windowAutoincrementId++;
      windowId = manager.windowAutoincrementId;
      manager.windowWebViewMessages.set(windowId, event.handler);
      manager.windowWebViewControllers.set(windowId, popupController);
      if (targetUrl != null && targetUrl.length > 0) {
        manager.windowWebViewUrls.set(windowId, targetUrl);
      }
    }

    // about:blank completes inside onWindowNew before Flutter can mount a Web
    // component → InnerCompleteWindowNew stalls the renderer and deferred
    // onCreateWindow never runs. Keep handler null; Flutter binds the stored
    // popup controller when the windowId WebView is created.
    if (isAboutBlankTarget) {
      this.lastAboutBlankCreateWindowMs = Date.now();
    }
    if (!isAboutBlankTarget) {
      try {
        event.handler.setWebController(popupController);
      } catch (error) {
        Log.e(TAG, 'onWindowNew setWebController failed: ' + JSON.stringify(error));
      }
    }

    this.dispatchOnCreateWindow(event.targetUrl, event.isUserTrigger, event.isAlert, windowId,
      isAboutBlankTarget ? null : event.handler);
    } catch (e) {
      Log.e(TAG, 'onWindowNew error: ' + JSON.stringify(e));
    }
  }

  /**
   * JS window.open(about:blank) fallback when ArkWeb skips onWindowNew (stale _blank binding).
   */
  public synthesizeAboutBlankCreateWindow(): void {
    if (!this.isWebViewAlive()) {
      Log.w(TAG, 'synthesizeAboutBlankCreateWindow skipped: webview not alive');
      return;
    }
    const now: number = Date.now();
    if (now - this.lastAboutBlankCreateWindowMs < 800) {
      Log.d(TAG, 'synthesizeAboutBlankCreateWindow debounced');
      return;
    }
    this.lastAboutBlankCreateWindowMs = now;
    Log.d(TAG, 'synthesizeAboutBlankCreateWindow');
    let windowId = 0;
    let popupController = new web_webview.WebviewController();
    if (this.plugin != null && this.plugin!.inAppWebViewManager != null) {
      let manager = this.plugin!.inAppWebViewManager;
      manager.cleanupStaleWindowState();
      manager.windowAutoincrementId++;
      windowId = manager.windowAutoincrementId;
      manager.windowWebViewControllers.set(windowId, popupController);
      manager.windowWebViewUrls.set(windowId, 'about:blank');
    }
    this.dispatchOnCreateWindow('about:blank', false, false, windowId, null);
  }

  private installWindowOpenAboutBlankHookIfNeeded(): void {
    if (!this.isWebViewAlive()) {
      return;
    }
    if (!this.inAppWebView!.customSettings.multiWindowAccess ||
      !this.inAppWebView!.customSettings.allowWindowOpenMethod) {
      return;
    }
    try {
      // Ensure hook exists after loadData / navigations (document-start may miss some paths).
      this.inAppWebView!.getController().runJavaScript(WindowOpenAboutBlankJS.SOURCE);
    } catch (error) {
      Log.e(TAG, 'installWindowOpenAboutBlankHookIfNeeded failed: ' + JSON.stringify(error));
    }
  }

  private dispatchOnCreateWindow(
    targetUrl: string,
    isUserTrigger: boolean,
    isAlert: boolean,
    windowId: number,
    controllerHandler: ControllerHandler | null
  ): void {
    let request = new URLRequest(targetUrl, 'GET', null, new Map<string, string>());
    let createWindowAction =
      new CreateWindowAction(request, true, isUserTrigger, false, windowId, isAlert);
    let channelDelegate = this.inAppWebView!.channelDelegate;
    let parentWebView = this.inAppWebView!;
    setTimeout(() => {
      Log.d(TAG, 'dispatchOnCreateWindow windowId=' + windowId + ' url=' + targetUrl);
      if (channelDelegate != null && !parentWebView.isDisposed()) {
        channelDelegate.onCreateWindow(createWindowAction,
          new InnerCreateWindowCallback(parentWebView, windowId, controllerHandler));
      }
    }, 0);
  }
  onWindowExit = () => {
    try {
      Log.d(TAG, 'onWindowExit=')
      if (!this.isWebViewAlive()) {
        return;
      }
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onCloseWindow();
      }
      const windowId = this.inAppWebView!.windowId;
      if (windowId != null && windowId != undefined &&
        this.plugin != null && this.plugin.inAppWebViewManager != null) {
        const manager = this.plugin.inAppWebViewManager;
        const handler = manager.windowWebViewMessages.get(windowId);
        if (handler != null) {
          try {
            handler.setWebController(null);
          } catch (error) {
            Log.e(TAG, 'onWindowExit setWebController(null) failed: ' + JSON.stringify(error));
          }
        }
        manager.windowWebViewMessages.delete(windowId);
        manager.windowWebViewControllers.delete(windowId);
        manager.windowWebViewUrls.delete(windowId);
      }
    } catch (e) {
      Log.e(TAG, 'onWindowExit error: ' + JSON.stringify(e));
    }
  }
  onSearchResultReceive = (event: OnSearchResultReceiveEvent) => {
    try {
      Log.d(TAG, 'onSearchResultReceive=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }

      const activeMatchOrdinal = Number(event.activeMatchOrdinal);
      const numberOfMatches = Number(event.numberOfMatches);
      const isDoneCounting = event.isDoneCounting === true;

      if (Number.isNaN(activeMatchOrdinal) || Number.isNaN(numberOfMatches)) {
        Log.e(TAG, 'onSearchResultReceive missing required fields: ' + JSON.stringify(event))
        return;
      }

      const findInteractionController = this.inAppWebView!.findInteractionController;
      if (findInteractionController != null &&
          findInteractionController.channelDelegate != null) {
        findInteractionController.channelDelegate.onFindResultReceived(
          activeMatchOrdinal,
          numberOfMatches,
          isDoneCounting
        );
      }

      const channelDelegate = this.inAppWebView!.channelDelegate;
      if (channelDelegate != null) {
        channelDelegate.onFindResultReceived(
          activeMatchOrdinal,
          numberOfMatches,
          isDoneCounting
        );
      }
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'onSearchResultReceive error: ' + JSON.stringify(err));
    }
  }
  onDataResubmitted = (event: OnDataResubmittedEvent) => {
    Log.d(TAG, 'onDataResubmitted=' + JSON.stringify(event))
    if (!this.isWebViewAlive()) {
      return;
    }
    let callback = new InnerFormResubmissionCallback(event.handler);
    if (this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.channelDelegate.onFormResubmission(this.inAppWebView!.getController().getUrl(), callback);
    } else {
      callback.defaultBehaviour(null);
    }
  }
  onPageVisible = (event: OnPageVisibleEvent) => {
    try {
      Log.d(TAG, 'onPageVisible=' + JSON.stringify(event))
      if (!this.isWebViewAlive()) {
        return;
      }
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onPageCommitVisible(event.url);
      }
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'onPageVisible error: ' + JSON.stringify(err));
    }
  }
  onInterceptKeyEvent = (event: KeyEvent) => {
    Log.d(TAG, 'onInterceptKeyEvent=' + JSON.stringify(event))
    // TODO
    return false;
  }
  onTouchIconUrlReceived = (event: OnTouchIconUrlReceivedEvent) => {
    Log.d(TAG, 'onTouchIconUrlReceived=' + JSON.stringify(event))
    if (!this.isWebViewAlive()) {
      return;
    }
    if (this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.channelDelegate.onReceivedTouchIconUrl(event.url, event.precomposed);
    }
  }
  onFaviconReceived = async (event: OnFaviconReceivedEvent) => {
    Log.d(TAG, 'onFaviconReceived=' + JSON.stringify(event))
    if (!this.isWebViewAlive()) {
      return;
    }
    let options: image.PackingOption = {
      format: 'image/png',
      quality: 100
    };
    let packer = image.createImagePacker();
    let imageBuffer = await packer.packing(event.favicon, options);
    if (!this.isWebViewAlive()) {
      await event.favicon.release()
      await packer.release()
      return;
    }
    if (this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.channelDelegate.onReceivedIcon(imageBuffer);
    }
    await event.favicon.release()
    await packer.release()
  }
  onAudioStateChanged = (event: OnAudioStateChangedEvent) => {
    Log.d(TAG, 'onAudioStateChanged=' + JSON.stringify(event))
    // TODO
  }
  onFirstContentfulPaint = (event: OnFirstContentfulPaintEvent) => {
    Log.d(TAG, 'onFirstContentfulPaint=' + JSON.stringify(event))
    if (!this.isWebViewAlive()) {
      return;
    }
    if (this.inAppWebView!.isLoading) {
      this.inAppWebView!.tryDispatchLoadStopIfNeeded(this.inAppWebView!.getUrl());
    }
  }
  onLoadIntercept = (event: OnLoadInterceptEvent) : boolean => {
    let request: WebResourceRequest = event.data;
    let requestUrl: string = request.getRequestUrl();
    Log.d(TAG, 'onLoadIntercept=' + requestUrl)
    if (requestUrl != null && InAppWebViewClient.isChromeSafeBrowsingTestUrl(requestUrl)) {
      this.handleChromeSafeBrowsingTestUrl(requestUrl);
      return true;
    }
    if (this.inAppWebView!.customSettings.useOnNavigationResponse && request.isMainFrame()) {
      if (this.skipNextNavigationResponseCheck) {
        this.skipNextNavigationResponseCheck = false;
        return false;
      }
      return this.handleOnNavigationResponse(requestUrl, request.isMainFrame());
    }
    return false;
  }

  private guessMimeTypeForUrl(url: string): string {
    const lower = url.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'text/html';
    }
    if (lower.endsWith('.css')) {
      return 'text/css';
    }
    if (lower.endsWith('.js')) {
      return 'application/javascript';
    }
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return 'text/html';
    }
    return 'text/html';
  }

  private canShowMimeTypeForUrl(url: string): boolean {
    const mimeType = this.guessMimeTypeForUrl(url);
    return mimeType.startsWith('text/') ||
      mimeType.includes('json') ||
      mimeType.includes('xml') ||
      mimeType.includes('javascript') ||
      mimeType.includes('html');
  }

  private buildNavigationResponseMap(url: string, isForMainFrame: boolean): Map<string, Any> {
    const mimeType = this.guessMimeTypeForUrl(url);
    let responseMap: Map<string, Any> = new Map<string, Any>();
    responseMap.set('url', url);
    responseMap.set('expectedContentLength', 0);
    responseMap.set('mimeType', mimeType);
    responseMap.set('suggestedFilename', null);
    responseMap.set('textEncodingName', null);
    responseMap.set('headers', new Map<string, Any>());
    responseMap.set('statusCode', 200);

    let map: Map<string, Any> = new Map<string, Any>();
    map.set('canShowMIMEType', this.canShowMimeTypeForUrl(url));
    map.set('isForMainFrame', isForMainFrame);
    map.set('response', responseMap);
    return map;
  }

  private handleOnNavigationResponse(requestUrl: string, isForMainFrame: boolean): boolean {
    if (!this.isWebViewAlive() || this.inAppWebView!.channelDelegate == null) {
      return false;
    }
    if (requestUrl == null || requestUrl.length === 0) {
      return false;
    }
    let callback = new SyncNavigationResponseCallback();
    this.inAppWebView!.channelDelegate.onNavigationResponse(
      this.buildNavigationResponseMap(requestUrl, isForMainFrame),
      callback);
    if (!callback.waitResponseWithTimeout(5000)) {
      // Timed out: mirror shouldOverrideUrlLoading — cancel stalled request and reload.
      this.reloadAfterNavigationResponseAllow(requestUrl);
      return true;
    }
    let policy = callback.result ?? NavigationResponsePolicy.ALLOW;
    switch (policy) {
      case NavigationResponsePolicy.CANCEL:
      case NavigationResponsePolicy.DOWNLOAD:
        return true;
      case NavigationResponsePolicy.ALLOW:
      default:
        // ArkWeb does not reliably resume the original load after a sync wait in
        // onLoadIntercept when returning false. Cancel + explicit loadUrl instead.
        this.reloadAfterNavigationResponseAllow(requestUrl);
        return true;
    }
  }

  private reloadAfterNavigationResponseAllow(requestUrl: string): void {
    if (!this.isWebViewAlive()) {
      return;
    }
    // Must not loadUrl synchronously inside onLoadIntercept: returning true from
    // the outer callback can cancel the nested programmatic load. Defer one tick.
    setTimeout(() => {
      if (!this.isWebViewAlive()) {
        return;
      }
      try {
        this.skipNextNavigationResponseCheck = true;
        this.inAppWebView!.getController().loadUrl(requestUrl);
      } catch (error) {
        this.skipNextNavigationResponseCheck = false;
        Log.e(TAG, 'reloadAfterNavigationResponseAllow loadUrl failed', error as Error);
      }
    }, 0);
  }

  static isChromeSafeBrowsingTestUrl(url: string): boolean {
    return url.startsWith('chrome://safe-browsing/');
  }

  static parseChromeSafeBrowsingThreatType(url: string): number {
    const typeMatch = url.match(/[?&]type=([^&]+)/);
    if (typeMatch == null) {
      return 0;
    }
    switch (typeMatch[1]) {
      case 'malware':
        return 1;
      case 'phishing':
        return 2;
      case 'unwanted':
        return 3;
      case 'billing':
        return 4;
      default:
        return 0;
    }
  }

  handleChromeSafeBrowsingTestUrlIfNeeded(url: string): boolean {
    if (!InAppWebViewClient.isChromeSafeBrowsingTestUrl(url)) {
      return false;
    }
    this.handleChromeSafeBrowsingTestUrl(url);
    return true;
  }

  handleChromeSafeBrowsingTestUrl(url: string): void {
    if (!this.isWebViewAlive() || this.inAppWebView!.channelDelegate == null) {
      return;
    }
    this.inAppWebView!.isLoading = true;
    this.inAppWebView!.channelDelegate.onLoadStart(url);
    const threatType = InAppWebViewClient.parseChromeSafeBrowsingThreatType(url);
    const resultCallback = new InnerSafeBrowsingHitCallback(this.inAppWebView!, url);
    this.inAppWebView!.channelDelegate.onSafeBrowsingHit(url, threatType, resultCallback);
  }
  onOverrideUrlLoading =  (request: WebResourceRequest) : boolean => {
    if (!this.isWebViewAlive()) {
      return false;
    }
    const requestUrl = request.getRequestUrl();
    // Defensive: previously requestUrl was passed through without a null/empty check.
    // Normal WebView navigation should never supply a blank URL; if it does, cancel here
    // (return true) instead of invoking Flutter shouldOverrideUrlLoading — edge-case behavior
    // change from 'enter callback' to 'cancel navigation' when the URL is absent.
    if (requestUrl == null || requestUrl === '') {
      Log.w(TAG, 'onOverrideUrlLoading: requestUrl is null or empty, cancel navigation');
      return true;
    }
    if (InAppWebViewClient.isChromeSafeBrowsingTestUrl(requestUrl)) {
      this.handleChromeSafeBrowsingTestUrl(requestUrl);
      return true;
    }
    Log.d(TAG, 'onOverrideUrlLoading=' + requestUrl)
    if (this.tryHandleBeforeUnloadNavigationPolyfill(request, requestUrl)) {
      return true;
    }
    // Allow the first main-frame navigation during back/forward (the
    // back/forward target itself). Block subsequent main-frame navigations
    // that occur during the same back/forward operation (e.g. JS redirects
    // on the target page), matching the behavior of other platforms.
    if (this.inAppWebView!.isNavigatingBackOrForward && this.inAppWebView!.navigateBackOrForwardDirection !== 0 && request.isMainFrame()) {
      if (this.inAppWebView!.backForwardNavigationAllowCount > 0) {
        this.inAppWebView!.backForwardNavigationAllowCount--;
        return false;
      }
      Log.d(TAG, 'Blocking navigation during goBack/goForward: ' + requestUrl);
      this.inAppWebView!.pendingSkipAfterRedirectBlock = true;
      this.inAppWebView!.pendingSkipDirection = this.inAppWebView!.navigateBackOrForwardDirection;
      return true;
    }
    if (this.inAppWebView!.customSettings.useShouldOverrideUrlLoading) {
      let headers = new Map<string, string>()
      request.getRequestHeader().forEach(header => headers.set(header.headerKey, header.headerValue));

      this.onShouldOverrideUrlLoading(
        this.inAppWebView!,
        requestUrl,
        request.getRequestMethod(),
        headers,
        request.isMainFrame(),
        request.isRequestGesture(),
        request.isRedirect());

      if (this.inAppWebView!.regexToCancelSubFramesLoadingCompiled != null) {
        if (request.isMainFrame())
          return true
        else {
          return this.inAppWebView!.regexToCancelSubFramesLoadingCompiled!.test(requestUrl);
        }
      } else {
        // There isn't any way to load an URL for a frame that is not the main frame,
        // so if the request is not for the main frame, the navigation is allowed.
        return request.isMainFrame();
      }
    }
    return false;
  }

  onRequestSelected = () => {
    Log.d(TAG, 'onRequestSelected=')
    if (!this.isWebViewAlive()) {
      return;
    }
    if(this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.channelDelegate.onRequestFocus();
    }
  }
  onScreenCaptureRequest = (event: OnScreenCaptureRequestEvent) => {
    Log.d(TAG, 'onScreenCaptureRequest=' + JSON.stringify(event))
    // TODO
  }
  onOverScroll = (event: OnOverScrollEvent) => {
    Log.d(TAG, 'onOverScroll=' + JSON.stringify(event));
    if (!this.isWebViewAlive()) {
      return;
    }
    const webView = this.inAppWebView!;
    if (webView.channelDelegate == null) {
      return;
    }
    // 1. x/y = 真实滚动位置（与 getScrollX/getScrollY 一致）
    let scrollX: number;
    let scrollY: number;
    try {
      const pageOffset = webView.getController().getPageOffset();
      scrollX = Math.round(pageOffset.x);
      scrollY = Math.round(pageOffset.y);
    } catch (error) {
      const e = error as BusinessError;
      Log.e(TAG, `onOverScroll getPageOffset ErrorCode: ${e.code}, Message: ${e.message}`);
      return;
    }
    // 2. 从 OHOS 过滚动偏移推导「是否在边界 overscroll」
    const overScrollX: number = event.xOffset;
    const overScrollY: number = event.yOffset;
    const clampedXAtBoundary: boolean = Math.abs(overScrollX) > 0;
    const clampedYAtBoundary: boolean = Math.abs(overScrollY) > 0;
    // 3. 纵向能否滚（同步）
    const canScrollVertically: boolean = webView.canScrollVertically();
    // 4. 横向能否滚（异步，保留 PR #194 的 onReceiveValue 修复）
    webView.canScrollHorizontally({
      onReceiveValue: (canScroll: boolean | null): void => {
        Log.d(TAG, 'onOverScroll callback canScroll=' + canScroll);
        if (!this.isWebViewAlive() || webView.channelDelegate == null) {
          return;
        }
        if (canScroll == null) {
          return;
        }
        // 5. 对齐 Android：canScroll * clampedAtBoundary
        const overScrolledHorizontally: boolean = canScroll && clampedXAtBoundary;
        const overScrolledVertically: boolean = canScrollVertically && clampedYAtBoundary;
        if (overScrolledHorizontally || overScrolledVertically) {
          webView.channelDelegate.onOverScrolled(
            scrollX,
            scrollY,
            overScrolledHorizontally,
            overScrolledVertically
          );
        }
      }
    });
  }
  onNavigationEntryCommitted = () => {
    Log.d(TAG, 'onNavigationEntryCommitted=')
    // TODO
  }
  onSafeBrowsingCheckResult = (threatType: ThreatType) => {
    try {
      Log.d(TAG, 'onSafeBrowsingCheckResult=')
      if (!this.isWebViewAlive()) {
        return;
      }
      if (this.inAppWebView!.channelDelegate != null) {
        let url = this.inAppWebView!.getController().getUrl();
        let resultCallback = new InnerSafeBrowsingHitCallback(this.inAppWebView!, url);
        this.inAppWebView!.channelDelegate.onSafeBrowsingHit(url, threatType, resultCallback);
      }
    } catch (e) {
      Log.e(TAG, 'onSafeBrowsingCheckResult error: ' + JSON.stringify(e));
    }
  }
  onNativeEmbedLifecycleChange = (callback: NativeEmbedDataInfo) => {
    Log.d(TAG, 'onNativeEmbedLifecycleChange=')
    // TODO
  }
  onNativeEmbedGestureEvent = (callback: NativeEmbedTouchInfo) => {
    Log.d(TAG, 'onNativeEmbedGestureEvent=')
    // TODO
  }
  onRenderProcessNotResponding = (data: RenderProcessNotRespondingData) => {
    try {
      if (!this.isWebViewAlive()) {
        return;
      }
      let callback = new InnerRenderProcessUnresponsiveCallback(this.inAppWebView!)
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onRenderProcessUnresponsive(this.inAppWebView!.getUrl(), callback);
      } else {
        callback.defaultBehaviour(null);
      }
    } catch (e) {
      Log.e(TAG, 'onRenderProcessNotResponding error: ' + JSON.stringify(e));
    }
  }
  onRenderProcessResponding = () => {
    try {
      if (!this.isWebViewAlive()) {
        return;
      }
      let callback = new InnerRenderProcessResponsiveCallback(this.inAppWebView!)
      if (this.inAppWebView!.channelDelegate != null) {
        this.inAppWebView!.channelDelegate.onRenderProcessResponsive(this.inAppWebView!.getUrl(), callback);
      } else {
        callback.defaultBehaviour(null);
      }
    } catch (e) {
      Log.e(TAG, 'onRenderProcessResponding error: ' + JSON.stringify(e));
    }
  }

  // 异步检查/申请系统级权限（ohos.permission.CAMERA 等）。
  // 检查/请求系统权限，返回 Promise。
  // 如果无需映射的系统权限（如 ProtectedMediaId），直接 resolve(true)。
  public resolveSystemPermissions(request: PermissionRequest): Promise<boolean> {
    let permissionList: Permissions[] = [];
    let accessibleResource = request.getAccessibleResource();
    accessibleResource.forEach(item => {
      if (this.permissionValues.has(item)) {
        permissionList.push(this.permissionValues.get(item)!);
      }
    });

    if (permissionList.length === 0) {
      return Promise.resolve(true);
    }

    return this.requestPermissions(permissionList);
  }

  // 申请权限
  private requestPermissions(permissionList:Array<Permissions>):Promise<boolean>{
    const _this = this;
    return new Promise(async (resolve, reject) => {
      try {
        // 筛选没授权的权限
        const withoutAuthorizationList = new ArrayList<Permissions>();
        for (let i = 0; i < permissionList.length; i++) {
          const item =  permissionList[i];
          const isAuthorization = await _this.checkPermissionGrant(item);
          if(!isAuthorization){
            withoutAuthorizationList.add(item);
          }
        }

        if(withoutAuthorizationList.isEmpty()){
          resolve(true);
          return;
        }

        // 请求权限
        const atManager = abilityAccessCtrl.createAtManager();
        const permissionsFromUserRes = await atManager.requestPermissionsFromUser(getContext(this),
          withoutAuthorizationList.convertToArray());

        // 判断请求的权限是否全部授权
        let allGranted = true;
        for (let i = 0; i < permissionsFromUserRes.authResults.length; i++) {
          const authItem = permissionsFromUserRes.authResults[i];
          if (authItem !== 0) {
            allGranted = false;
            break;
          }
        }
        if (allGranted) {
          resolve(true);
          return;
        }

        // 筛选 需要二次授权的权限
        allGranted = true;
        for (let i = 0; i < permissionsFromUserRes.authResults.length; i++) {
          const authItem =  permissionsFromUserRes.authResults[i];
          // 没授权，没系统弹窗
          if(authItem!==0 && permissionsFromUserRes.dialogShownResults != null && !permissionsFromUserRes.dialogShownResults[i]){
            // 引导用户授权
            const permissionOnSettingRes = await atManager.requestPermissionOnSetting(getContext(this),
              [permissionsFromUserRes.permissions[i] as Permissions])
            if (permissionOnSettingRes[0] !== 0) {
              allGranted = false;
              break;
            }
          }
        }
        resolve(allGranted);
      }catch (error) {
        Log.e(TAG,`Failed requestPermissions error is ${error}`);
        reject(error)
      }
    });
  }

  // 检查权限
  private async  checkPermissionGrant(permission: Permissions): Promise<boolean> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;

    // 获取应用程序的accessTokenID。
    let tokenId: number = 0;
    try {
      let bundleInfo: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      let appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
      tokenId = appInfo.accessTokenId;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.e(TAG,`Failed to get bundle info for self. Code is ${err.code}, message is ${err.message}`);
    }

    // 校验应用是否被授予权限。
    try {
      grantStatus = await atManager.checkAccessToken(tokenId, permission);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      Log.e(TAG,`Failed to check access token. Code is ${err.code}, message is ${err.message}`);
    }

    return grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }


  private onShouldOverrideUrlLoading(webView: InAppWebView, url: string, method: string,
    headers: Map<string, string>,
    isForMainFrame: boolean, hasGesture: boolean, isRedirect: boolean) {
    let request = new URLRequest(url, method, null, headers);
    let navigationAction = new NavigationAction(request, isForMainFrame, hasGesture, isRedirect);

    let callback = new InnerShouldOverrideUrlLoadingCallback(this.inAppWebView!, url, headers, isForMainFrame)
    if (this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.channelDelegate.shouldOverrideUrlLoading(navigationAction, callback);
    } else {
      callback.defaultBehaviour(null);
    }
  }

  private async onReceivedHttpAuthRequest(handler: HttpAuthHandler, host: string, realm: string) {
    let url = this.inAppWebView!.getController().getUrl();
    let protocol = 'https';
    let port = 0;

    if (url != null) {
      try {
        let uriurl = new uri.URI(url);
        protocol = uriurl.scheme;
        port = Number.parseInt(uriurl.port);
      } catch (e) {
        Log.e(TAG, '', e);
      }
    }

    this.previousAuthRequestFailureCount++;

    if (this.credentialsProposed == null) {
      this.credentialsProposed = await CredentialDatabase.getInstance(this.inAppWebView!.context!)
        .getHttpAuthCredentials(host, protocol, realm, port);
    }

    let credentialProposed: URLCredential | null = null;
    if (this.credentialsProposed != null &&
      this.credentialsProposed.length > 0) {
      credentialProposed = this.credentialsProposed.get(0);
    }

    let certificate: cert.X509Cert | null = null;
    let certificates = await this.inAppWebView!.getController().getCertificate();
    if (certificates && certificates.length > 0) {
      certificate = certificates[0];
    }
    let protectionSpace = new URLProtectionSpace(host, protocol, realm, port, null, certificate, null);
    let challenge =
      new HttpAuthenticationChallenge(protectionSpace, this.previousAuthRequestFailureCount,
        credentialProposed);

    let callback = new InnerReceivedHttpAuthRequestCallback(this, this.inAppWebView!, handler,
    host, protocol, realm, port);
    if (this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.channelDelegate.onReceivedHttpAuthRequest(challenge, callback);
    } else {
      callback.defaultBehaviour(null);
    }
  }

  private onReceivedSslErrorEventReceive(handler: SslErrorHandler, sslError: SslError) {
    let url = this.inAppWebView!.getController().getUrl();
    let host = '';
    let protocol = 'https';
    let port = 0;

    try {
      let uriurl = new uri.URI(url);
      host = uriurl.host;
      protocol = uriurl.scheme;
      port = Number.parseInt(uriurl.port);
    } catch (e) {
      Log.e(TAG, '', e);
    }

    // TODO  sslError.getCertificate()没有这方法 用null先适配
    let protectionSpace = new URLProtectionSpace(host, protocol, null, port, null, null, sslError);
    let challenge = new ServerTrustChallenge(protectionSpace);
    let callback = new InnerReceivedServerTrustAuthRequestCallback(handler);
    if (this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.channelDelegate.onReceivedServerTrustAuthRequest(challenge, callback);
    } else {
      // 直接调用 handler.handleCancel() 拒绝 SSL 连接。消除了对 defaultBehaviour 实现细节的依赖。
      handler.handleCancel();
    }
  }

  private onReceivedClientAuthenticationRequest(handler: ClientAuthenticationHandler, host: string,
    port: number, keyTypes: Array<string>, issuers: Array<string>) {
    let url = this.inAppWebView!.getController().getUrl();
    let protocol = 'https';

    if (url != null) {
      try {
        let uriurl = new uri.URI(url);
        protocol = uriurl.scheme;
      } catch (e) {
        Log.e(TAG, '', e);
      }
    }

    let protectionSpace = new URLProtectionSpace(host, protocol, null, port, null, null, null);
    let challenge = new ClientCertChallenge(protectionSpace, issuers, keyTypes);

    let callback = new InnerReceivedClientCertRequestCallback(this.inAppWebView!, handler);
    if (this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.clientCertHttpFallbackPending = true;
      this.inAppWebView!.channelDelegate.onReceivedClientCertRequestBlocking(challenge, callback);
    } else {
      callback.defaultBehaviour(null);
    }
  }

  private loadCustomJavaScriptOnPageStarted(webView: InAppWebView | null) {
    if (webView == null || webView.controller == null) {
      return;
    }
    const uc = webView.userContentController;
    if (uc == null) {
      return;
    }
    let resetUserScriptFlagsJs = 'if (window.' + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ' != null) {' +
      'window.' + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + '._userScriptsAtDocumentStartLoaded = false;' +
      'window.' + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + '._userScriptsAtDocumentEndLoaded = false;' +
      '}';
    webView.getController().runJavaScriptExt(resetUserScriptFlagsJs);
    let source = uc.generateWrappedCodeForDocumentStart();
    webView.getController().runJavaScriptExt(source)
  }

  private loadCustomJavaScriptOnPageFinished(webView: InAppWebView | null) {
    if (webView == null) {
      return;
    }
    // Idempotent; tryDispatchLoadStopIfNeeded also injects before onLoadStop.
    webView.injectDocumentEndScriptsIfNeeded();
  }

  private needsCameraPermission(): boolean {
    return false
  }

  private acceptsVideo(types: Array<string>): boolean {
    let mimeTypes = this.getAcceptedMimeType(types);
    return this.acceptsAny(mimeTypes) || this.arrayContainsString(mimeTypes, 'video');
  }

  private acceptsImages(types: Array<string>): boolean {
    let mimeTypes = this.getAcceptedMimeType(types);
    return this.acceptsAny(mimeTypes) || this.arrayContainsString(mimeTypes, 'image');
  }

  private getAcceptedMimeType(types: Array<string>): Array<string> {
    if (this.isArrayEmpty(types)) {
      return ['*/*'];
    }
    let mimeTypes = new Array<string>();
    for (let i = 0; i < types.length; i++) {
      let t = types[i];
      // convert file extensions to mime types
      if (t.indexOf('.') > -1) {
        let mimeType = MimeTypes.getMimeTypeFromExtension(t.replace('.', ''));
        mimeTypes[i] = mimeType;
      } else {
        mimeTypes[i] = t;
      }
    }
    return mimeTypes;
  }

  private acceptsAny(types: Array<string>) {
    if (this.isArrayEmpty(types)) {
      return true;
    }
    for (let type of types) {
      if (type == '*/*') {
        return true;
      }
    }
    return false;
  }

  private arrayContainsString(array: Array<string>, pattern: string): boolean {
    for (let content of array) {
      if (content != null && content.indexOf(pattern) > -1) {
        return true;
      }
    }
    return false;
  }

  private isArrayEmpty(arr: Array<string>): boolean {
    // when our array returned from getAcceptTypes() has no values set from the webview
    // i.e. <input type='file' />, without any 'accept' attr
    // will be an array with one empty string element, afaik
    return arr.length == 0 || (arr.length == 1 && arr[0].length == 0);
  }
}

class InnerJsAlertCallback extends JsAlertCallback implements IPendingJsDialog {
  private client: InAppWebViewClient;
  private result: JsResult;
  private message: string;
  private settled: boolean = false;

  constructor(client: InAppWebViewClient, result: JsResult, message: string) {
    super();
    this.client = client;
    this.result = result;
    this.message = message;
    this.client.registerPendingJsDialog(this);
  }

  private safeConfirm(): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.result.handleConfirm();
    } catch (e) {
      Log.e(TAG, 'handleConfirm failed: ' + JSON.stringify(e));
    }
    this.client.unregisterPendingJsDialog(this);
  }

  private safeCancel(): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.result.handleCancel();
    } catch (e) {
      Log.e(TAG, 'handleCancel failed: ' + JSON.stringify(e));
    }
    this.client.unregisterPendingJsDialog(this);
  }

  forceCancel(): void {
    this.safeCancel();
  }

  nonNullSuccess(response: JsAlertResponse): boolean {
    if (response.isHandledByClient()) {
      let action = response.getAction();
      action = action != null ? action : 1;
      switch (action) {
        case 0:
          this.safeConfirm();
          break;
        case 1:
        default:
          this.safeCancel();
      }
      return false;
    }
    return true;
  }

  defaultBehaviour(response: JsAlertResponse | null): void {
    let responseMessage: string | null = null;
    let confirmButtonTitle: string | null = null;
    if (response != null) {
      responseMessage = response.getMessage();
      confirmButtonTitle = response.getConfirmButtonTitle();
    }
    this.createAlertDialog(this.message, responseMessage, confirmButtonTitle);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.safeCancel();
  }

  notImplemented(): void {
    this.safeCancel();
  }

  private createAlertDialog(message: string, responseMessage: string | null,
    confirmButtonTitle: string | null) {
    let alertMessage = (responseMessage != null && responseMessage.length > 0) ? responseMessage : message;
    AlertDialog.show(
      {
        message: alertMessage,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        confirm: {
          value: confirmButtonTitle != null ? confirmButtonTitle : '确定',
          action: () => {
            this.safeConfirm()
          }
        },
        cancel: () => {
          this.safeCancel()
        }
      }
    )
  }
}

class InnerJsConfirmCallback extends JsConfirmCallback implements IPendingJsDialog {
  private client: InAppWebViewClient;
  private result: JsResult;
  private message: string;
  private settled: boolean = false;

  constructor(client: InAppWebViewClient, result: JsResult, message: string) {
    super();
    this.client = client;
    this.result = result;
    this.message = message;
    this.client.registerPendingJsDialog(this);
  }

  private safeConfirm(): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.result.handleConfirm();
    } catch (e) {
      Log.e(TAG, 'handleConfirm failed: ' + JSON.stringify(e));
    }
    this.client.unregisterPendingJsDialog(this);
  }

  private safeCancel(): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.result.handleCancel();
    } catch (e) {
      Log.e(TAG, 'handleCancel failed: ' + JSON.stringify(e));
    }
    this.client.unregisterPendingJsDialog(this);
  }
  forceCancel(): void {
    this.safeCancel();
  }

  nonNullSuccess(response: JsConfirmResponse): boolean {
    if (response.isHandledByClient()) {
      let action = response.getAction();
      action = action != null ? action : 1;
      switch (action) {
        case 0:
          this.safeConfirm();
          break;
        case 1:
        default:
          this.safeCancel();
      }
      return false;
    }
    return true;
  }

  defaultBehaviour(response: JsConfirmResponse | null): void {
    let responseMessage: string | null = null;
    let confirmButtonTitle: string | null = null;
    let cancelButtonTitle: string | null = null;
    if (response != null) {
      responseMessage = response.getMessage();
      confirmButtonTitle = response.getConfirmButtonTitle();
      cancelButtonTitle = response.getCancelButtonTitle();
    }
    this.createConfirmDialog(this.message, responseMessage, confirmButtonTitle, cancelButtonTitle);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.safeCancel();
  }
  notImplemented(): void {
    this.safeCancel();
  }

  private createConfirmDialog(message: string, responseMessage: string | null,
    confirmButtonTitle: string | null, cancelButtonTitle: string | null) {
    let alertMessage = (responseMessage != null && responseMessage.length > 0) ? responseMessage : message;
    AlertDialog.show(
      {
        message: alertMessage,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: cancelButtonTitle != null ? cancelButtonTitle : '取消',
          action: () => {
            this.safeCancel()
          }
        },
        secondaryButton: {
          defaultFocus: true,
          value: confirmButtonTitle != null ? confirmButtonTitle : '确定',
          action: () => {
            this.safeConfirm()
          }
        },
        cancel: () => {
          this.safeCancel()
        }
      }
    )
  }
}

class InnerJsPromptCallback extends JsPromptCallback implements IPendingJsDialog {
  private client: InAppWebViewClient;
  private result: JsResult;
  private message: string;
  private defaultValue: string;
  private uiObject: Object;
  private settled: boolean = false;
  private customDialogId: number = -1;

  constructor(client: InAppWebViewClient, result: JsResult, message: string, defaultValue: string, uiObject: Object) {
    super();
    this.client = client;
    this.result = result;
    this.message = message;
    this.defaultValue = defaultValue;
    this.uiObject = uiObject;
    this.client.registerPendingJsDialog(this);
  }

  private closeDialogIfAny(): void {
    if (this.customDialogId < 0) {
      return;
    }
    let id = this.customDialogId;
    this.customDialogId = -1;
    try {
      promptAction.closeCustomDialog(id);
    } catch (e) {
      Log.w(TAG, 'closeCustomDialog failed: ' + JSON.stringify(e));
    }
  }

  private safePromptConfirm(value: string | null): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.result.handlePromptConfirm(value != null ? value : '');
    } catch (e) {
      Log.e(TAG, 'handlePromptConfirm failed: ' + JSON.stringify(e));
    }
    this.closeDialogIfAny();
    this.client.unregisterPendingJsDialog(this);
  }

  private safeCancel(): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.result.handleCancel();
    } catch (e) {
      Log.e(TAG, 'handleCancel failed: ' + JSON.stringify(e));
    }
    this.closeDialogIfAny();
    this.client.unregisterPendingJsDialog(this);
  }
  forceCancel(): void {
    this.safeCancel();
  }

  nonNullSuccess(response: JsPromptResponse): boolean {
    if (response.isHandledByClient()) {
      let action = response.getAction();
      action = action != null ? action : 1;
      switch (action) {
        case 0:
          this.safePromptConfirm(response.getValue());
          break;
        case 1:
        default:
          this.safeCancel();
      }
      return false;
    }
    return true;
  }

  defaultBehaviour(response: JsPromptResponse | null): void {
    let responseMessage: string | null = null;
    let responseDefaultValue: string | null = null;
    let value: string | null = null;
    let confirmButtonTitle: string | null = null;
    let cancelButtonTitle: string | null = null;
    if (response != null) {
      responseMessage = response.getMessage();
      responseDefaultValue = response.getDefaultValue();
      value = response.getValue();
      confirmButtonTitle = response.getConfirmButtonTitle();
      cancelButtonTitle = response.getCancelButtonTitle();
    }
    this.createPromptDialog(this.message, this.defaultValue, responseMessage, responseDefaultValue, value,
      cancelButtonTitle, confirmButtonTitle);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.safeCancel();
  }
  notImplemented(): void {
    this.safeCancel();
  }

  private createPromptDialog(message: string, defaultValue: string, responseMessage: string | null,
    responseDefaultValue: string | null, value: string | null, cancelButtonTitle: string | null,
    confirmButtonTitle: string | null) {
    if (this.settled) {
      return;
    }
    let initValue =
      (responseDefaultValue != null && responseDefaultValue.length > 0) ? responseDefaultValue : defaultValue;
    let alertMessage = (responseMessage != null && responseMessage.length > 0) ? responseMessage : message;
    let finalValue = value;
    let isCancel = true;
    try {
      promptAction.openCustomDialog({
        builder: ohosPromptDialogBuilder.bind(this.uiObject, initValue, alertMessage, cancelButtonTitle,
          confirmButtonTitle, () => {
            isCancel = false
            this.safeCancel()
          }, (value: string | null) => {
            isCancel = false
            this.safePromptConfirm(finalValue != null ? finalValue : value);
          }),
        alignment: DialogAlignment.Center,
        onDidDisappear: () => {
          if (isCancel) {
            this.safeCancel()
          }
        }
      }).then((dialogId: number) => {
        if (this.settled) {
          try {
            promptAction.closeCustomDialog(dialogId);
          } catch (e) {
            Log.w(TAG, 'closeCustomDialog (already settled) failed: ' + JSON.stringify(e));
          }
          return;
        }
        this.customDialogId = dialogId
      }).catch((e: Object) => {
        Log.e(TAG, 'openCustomDialog failed: ' + JSON.stringify(e));
        this.safeCancel();
      })
    } catch (e) {
      Log.e(TAG, 'createPromptDialog sync throw:' + JSON.stringify(e));
      this.safeCancel();
    }
  }
}

/** Synthetic JsResult used when ArkWeb onBeforeUnload does not fire. */
class BeforeUnloadNavigationJsResult {
  private webView: InAppWebView;
  private targetUrl: string;

  constructor(webView: InAppWebView, targetUrl: string) {
    this.webView = webView;
    this.targetUrl = targetUrl;
  }

  handleConfirm(): void {
    this.webView.beforeUnloadNavigationAllowedUrl = this.targetUrl;
    this.webView.hasBeforeUnloadHandler = false;
    this.webView.beforeUnloadNavigationPending = false;
    this.webView.pendingBeforeUnloadTargetUrl = null;
    try {
      this.webView.getController().loadUrl(this.targetUrl);
    } catch (e) {
      Log.e(TAG, 'beforeUnload polyfill loadUrl failed: ' + JSON.stringify(e));
    }
  }

  handleCancel(): void {
    this.webView.beforeUnloadNavigationPending = false;
    this.webView.pendingBeforeUnloadTargetUrl = null;
  }

  handlePromptConfirm(_value: string): void {
    this.handleConfirm();
  }
}

class InnerJsBeforeUnloadCallback extends JsBeforeUnloadCallback implements IPendingJsDialog {
  private client: InAppWebViewClient;
  private result: JsResult;
  private message: string;
  private settled: boolean = false;

  constructor(client: InAppWebViewClient, result: JsResult, message: string) {
    super();
    this.client = client;
    this.result = result;
    this.message = message;
    this.client.registerPendingJsDialog(this);
  }

  private safeConfirm(): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.result.handleConfirm();
    } catch (e) {
      Log.e(TAG, 'handleConfirm failed: ' + JSON.stringify(e));
    }
    this.client.unregisterPendingJsDialog(this);
  }

  private safeCancel(): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.result.handleCancel();
    } catch (e) {
      Log.e(TAG, 'handleCancel failed: ' + JSON.stringify(e));
    }
    this.client.unregisterPendingJsDialog(this);
  }
  forceCancel(): void {
    this.safeCancel();
  }

  nonNullSuccess(response: JsBeforeUnloadResponse): boolean {
    if (response.isHandledByClient()) {
      let action = response.getAction();
      action = action != null ? action : 1;
      switch (action) {
        case 0:
          this.safeConfirm();
          break;
        case 1:
        default:
          this.safeCancel();
      }
      return false;
    }
    return true;
  }

  defaultBehaviour(response: JsBeforeUnloadResponse | null): void {
    let responseMessage: string | null = null;
    let confirmButtonTitle: string | null = null;
    let cancelButtonTitle: string | null = null;
    if (response != null) {
      responseMessage = response.getMessage();
      confirmButtonTitle = response.getConfirmButtonTitle();
      cancelButtonTitle = response.getCancelButtonTitle();
    }
    this.createBeforeUnloadDialog(this.message, responseMessage, confirmButtonTitle, cancelButtonTitle);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.safeCancel();
  }
  notImplemented(): void {
    this.safeCancel();
  }

  private createBeforeUnloadDialog(message: string, responseMessage: string | null,
    confirmButtonTitle: string | null, cancelButtonTitle: string | null) {
    let alertMessage = (responseMessage != null && responseMessage.length > 0) ? responseMessage : message;
    AlertDialog.show(
      {
        message: alertMessage,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: cancelButtonTitle != null ? cancelButtonTitle : '取消',
          action: () => {
            this.safeCancel()
          }
        },
        secondaryButton: {
          defaultFocus: true,
          value: confirmButtonTitle != null ? confirmButtonTitle : '确定',
          action: () => {
            this.safeConfirm()
          }
        },
        cancel: () => {
          this.safeCancel()
        }
      }
    )
  }
}

class InnerPermissionRequestCallback extends PermissionRequestCallback {
  private request: PermissionRequest;
  private client: InAppWebViewClient;

  constructor(request: PermissionRequest, client: InAppWebViewClient) {
    super();
    this.request = request;
    this.client = client;
  }

  nonNullSuccess(response: PermissionResponse): boolean {
    let action = response.getAction();
    if (action != null) {
      switch (action) {
        case 1: {
          // 先检查/请求系统级权限，再根据结果调用 grant() 或 deny()
          this.client.resolveSystemPermissions(this.request)
            .then((granted) => {
              if (granted) {
                let accessibleResource = this.request.getAccessibleResource();
                this.request.grant(accessibleResource);
              } else {
                this.request.deny();
              }
            })
            .catch((error: BusinessError) => {
              Log.e(TAG, `resolveSystemPermissions error: ${error}`);
              this.request.deny();
            });
          break;
        }
        case 0:
        default:
          this.request.deny();
      }
      return false;
    }
    return true;
  }

  defaultBehaviour(response: PermissionResponse | null): void {
    this.request.deny();
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}



interface JsGeolocationHandler {
  invoke(origin: string, allow: boolean, retain: boolean): void;
}

class ManualGeolocationPermissionsShowPromptCallback extends GeolocationPermissionsShowPromptCallback {
  private origin: string;

  constructor(origin: string) {
    super();
    this.origin = origin;
  }

  nonNullSuccess(response: GeolocationPermissionShowPromptResponse): boolean {
    if (response.isAllow()) {
      try {
        web_webview.GeolocationPermissions.allowGeolocation(response.getOrigin());
      } catch (error) {
        Log.w(TAG, 'allowGeolocation failed: ' + JSON.stringify(error));
      }
    }
    return false;
  }

  defaultBehaviour(response: GeolocationPermissionShowPromptResponse | null): void {
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}

class InnerGeolocationPermissionsShowPromptCallback extends GeolocationPermissionsShowPromptCallback {
  private geolocation: JsGeolocationHandler;
  private origin: string;

  constructor(origin: string, geolocation: JsGeolocationHandler) {
    super();
    this.geolocation = geolocation;
    this.origin = origin;
  }

  nonNullSuccess(response: GeolocationPermissionShowPromptResponse): boolean {
    this.geolocation.invoke(response.getOrigin(), response.isAllow(), response.isRetain());
    return false;
  }

  defaultBehaviour(response: GeolocationPermissionShowPromptResponse | null): void {
    this.geolocation.invoke(this.origin, false, false);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}

class InnerReceivedHttpAuthRequestCallback extends ReceivedHttpAuthRequestCallback {
  private handler: HttpAuthHandler;
  private host: string;
  private finalProtocol: string;
  private realm: string;
  private finalPort: number;
  private inAppWebView: InAppWebView;
  private client: InAppWebViewClient;

  constructor(client: InAppWebViewClient, inAppWebView: InAppWebView, handler: HttpAuthHandler, host: string,
    protocol: string, realm: string, port: number) {
    super();
    this.client = client;
    this.handler = handler;
    this.host = host;
    this.finalProtocol = protocol;
    this.realm = realm;
    this.finalPort = port;
    this.inAppWebView = inAppWebView;
  }

  nonNullSuccess(response: HttpAuthResponse): boolean {
    let action = response.getAction();
    if (action != null) {
      switch (action) {
        case 1:
          let username = response.getUsername();
          let password = response.getPassword();
          let permanentPersistence = response.isPermanentPersistence();
          if (permanentPersistence) {
            CredentialDatabase.getInstance(this.inAppWebView!.context!)
              .setHttpAuthCredential(this.host, this.finalProtocol, this.realm, this.finalPort, username, password);
          }
          this.handler.confirm(username, password);
          break;
        case 2:
          if (this.client.credentialsProposed && this.client.credentialsProposed!.length > 0) {
            let credential = this.client.credentialsProposed!.removeByIndex(0);
            this.handler.confirm(credential.getUsername(), credential.getPassword());
          } else {
            this.handler.cancel();
          }
          // used custom CredentialDatabase!
          // handler.useHttpAuthUsernamePassword();
          break;
        case 0:
        default:
          this.client.credentialsProposed = null;
          this.client.previousAuthRequestFailureCount = 0;
          this.handler.cancel();
      }
      return false;
    }
    return true;
  }

  defaultBehaviour(result: HttpAuthResponse | null): void {
    if (result == null) {
      this.handler.cancel();
    } else {
      this.nonNullSuccess(result)
    }
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}

class InnerReceivedServerTrustAuthRequestCallback extends ReceivedServerTrustAuthRequestCallback {
  private handler: SslErrorHandler;

  constructor(handler: SslErrorHandler) {
    super();
    this.handler = handler;
  }

  nonNullSuccess(response: ServerTrustAuthResponse): boolean {
    let action = response.getAction();
    if (action != null) {
      switch (action) {
        case 1:
          this.handler.handleConfirm();
          break;
        case 0:
        default:
          this.handler.handleCancel();
      }
      return false;
    }
    return true;
  }

  defaultBehaviour(result: ServerTrustAuthResponse | null) {
    if (result != null) {
      this.nonNullSuccess(result);
    } else {
      this.handler.handleCancel();
    }
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}

class InnerReceivedClientCertRequestCallback extends SyncBaseCallbackResultImpl<ClientCertResponse> {
  private handler: ClientAuthenticationHandler;
  private inAppWebView: InAppWebView;

  constructor(inAppWebView: InAppWebView, handler: ClientAuthenticationHandler) {
    super();
    this.inAppWebView = inAppWebView;
    this.handler = handler;
  }

  decodeResult(obj: Object | null): ClientCertResponse | null {
    return ClientCertResponse.fromMap(obj as Map<string, Any>);
  }

  nonNullSuccess(response: ClientCertResponse): boolean {
    let action = response.getAction();
    if (action != null && this.inAppWebView!.plugin != null) {
      switch (action) {
        case 1: {
          let paths = ClientCertUtil.resolveClientCertConfirmPaths(
            this.inAppWebView!.plugin!,
            this.inAppWebView!.context!,
            response.getCertificatePath(),
            response.getCertificatePassword(),
            response.getKeyStoreType()
          );
          if (paths != null) {
            Log.d(TAG, 'Client certificate confirm: ' + paths.priKeyFile);
            this.handler.confirm(paths.priKeyFile, paths.certChainFile);
          } else {
            Log.e(TAG, 'Client certificate path resolution failed');
            this.inAppWebView!.clientCertHttpFallbackPending = false;
            this.handler.cancel();
            break;
          }
          let httpPaths = ClientCertUtil.resolveHttpClientCertPaths(
            this.inAppWebView!.plugin!,
            this.inAppWebView!.context!,
            response.getCertificatePath(),
            response.getKeyStoreType(),
            response.getCertificatePassword()
          );
          if (httpPaths != null) {
            this.inAppWebView!.loadClientCertUrlViaHttp(this.inAppWebView!.getUrl(), httpPaths);
          }
        }
          break;
        case 2:
          this.inAppWebView!.clientCertHttpFallbackPending = false;
          this.handler.ignore();
          break;
        case 0:
        default:
          this.inAppWebView!.clientCertHttpFallbackPending = false;
          this.handler.cancel();
      }
      return false;
    }
    return true;
  }

  defaultBehaviour(result: ClientCertResponse | null) {
    if (result != null) {
      this.nonNullSuccess(result);
    } else {
      this.handler.cancel();
    }
    super.defaultBehaviour(result);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}

class InnerCreateWindowCallback extends CreateWindowCallback {
  private finalWindowId: number;
  private inAppWebView: InAppWebView;
  private controllerHandler: ControllerHandler | null;

  constructor(inAppWebView: InAppWebView, finalWindowId: number, controllerHandler: ControllerHandler | null) {
    super();
    this.inAppWebView = inAppWebView;
    this.finalWindowId = finalWindowId;
    this.controllerHandler = controllerHandler;
  }

  nonNullSuccess(handledByClient: boolean): boolean {
    if (!handledByClient) {
      this.releasePendingWindow();
    }
    return !handledByClient;
  }

  defaultBehaviour(handledByClient: boolean | null) {
    if (handledByClient !== true) {
      this.releasePendingWindow();
    }
  }

  private releasePendingWindow(): void {
    if (this.controllerHandler != null) {
      try {
        this.controllerHandler.setWebController(null);
      } catch (error) {
        Log.e(TAG, 'releasePendingWindow setWebController(null) failed: ' + JSON.stringify(error));
      }
    }
    if (this.inAppWebView!.plugin != null && this.inAppWebView!.plugin.inAppWebViewManager != null) {
      this.inAppWebView!.plugin.inAppWebViewManager.cleanupStaleWindowState();
    }
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}

class InnerFormResubmissionCallback extends FormResubmissionCallback {
  private hanlder: DataResubmissionHandler;

  constructor(hanlder: DataResubmissionHandler) {
    super();
    this.hanlder = hanlder;
  }

  nonNullSuccess(action: number): boolean {
    switch (action) {
      case 0:
        this.hanlder.resend();
        break;
      case 1:
      default:
        this.hanlder.cancel();
    }
    return false;
  }

  defaultBehaviour(result: number | null) {
    if (result != null) {
      this.nonNullSuccess(result);
    } else {
      this.hanlder.cancel();
    }
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
};

class InnerShouldOverrideUrlLoadingCallback extends ShouldOverrideUrlLoadingCallback {

  private inAppWebView: InAppWebView;
  private url: string;
  private headers: Map<string, string>;
  private isForMainFrame: boolean;

  constructor(inAppWebView: InAppWebView, url: string, headers: Map<string, string>, isForMainFrame: boolean) {
    super();
    this.inAppWebView = inAppWebView;
    this.url = url;
    this.headers = headers;
    this.isForMainFrame = isForMainFrame;
  }

  nonNullSuccess(result: NavigationActionPolicy) : boolean {
    switch (result) {
      case NavigationActionPolicy.ALLOW:
        this.allowShouldOverrideUrlLoading(this.inAppWebView!, this.url, this.headers, this.isForMainFrame);
        break;
      case NavigationActionPolicy.CANCEL:
      default:
        break;
    }
    return false;
  }

  defaultBehaviour(result: NavigationActionPolicy | null) {
    this.allowShouldOverrideUrlLoading(this.inAppWebView!, this.url, this.headers, this.isForMainFrame);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }

  // App integration: add querySchemes: ['weixin'] in entry module.json5 for WeChat Pay URL scheme queries.
  allowShouldOverrideUrlLoading(inAppWebView: InAppWebView, url: string, headers: Map<string, string>,
    isForMainFrame: boolean) {
    if (isForMainFrame) {
      const loadHeaders = ensureRefererHeader(inAppWebView, headers);
      this.inAppWebView!.getController().loadUrl(url, this.inAppWebView!.toWebHeaders(loadHeaders));
    }
  }
};

class InnerSafeBrowsingHitCallback extends SafeBrowsingHitCallback {
  private inAppWebView: InAppWebView;
  private url: string;

  constructor(inAppWebView: InAppWebView, url: string) {
    super();
    this.inAppWebView = inAppWebView;
    this.url = url;
  }

  private completeSafeBrowsingProceed(): void {
    if (this.inAppWebView!.channelDelegate != null) {
      this.inAppWebView!.isLoading = false;
      this.inAppWebView!.channelDelegate.onLoadStop(this.url);
    }
  }

  public nonNullSuccess(response: SafeBrowsingResponse): boolean {
    let action = response.getAction();
    if (action != null) {
      switch (action) {
        case 0:
          try {
            this.inAppWebView!.getController().loadUrl('about:blank');
          } catch (error) {
            Log.e(TAG, 'backToSafety loadUrl failed', error as Error);
          }
          return false;
        case 1:
          this.completeSafeBrowsingProceed();
          return false;
        case 2:
        default:
          return false;
      }
    }
    return true;
  }

  defaultBehaviour(result: SafeBrowsingResponse | null): void {
    if (result != null) {
      this.nonNullSuccess(result);
    }
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}

class InnerRenderProcessUnresponsiveCallback extends RenderProcessUnresponsiveCallback {
  private inAppWebView: InAppWebView;

  constructor(inAppWebView: InAppWebView) {
    super();
    this.inAppWebView = inAppWebView;
  }

  public nonNullSuccess(action: number): boolean {
    switch (action) {
      case 0:
        this.inAppWebView!.getController().terminateRenderProcess();
        break;
    }
    return false;
  }

  defaultBehaviour(result: number | null) {

  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}

class InnerRenderProcessResponsiveCallback extends RenderProcessResponsiveCallback {
  private inAppWebView: InAppWebView;

  constructor(inAppWebView: InAppWebView) {
    super();
    this.inAppWebView = inAppWebView;
  }

  public nonNullSuccess(action: number): boolean {
    switch (action) {
      case 0:
        this.inAppWebView!.getController().terminateRenderProcess();
        break;
    }
    return false;
  }

  defaultBehaviour(result: number | null) {

  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(TAG, errorCode + ', ' + ((errorMessage != null) ? errorMessage : ''));
    this.defaultBehaviour(null);
  }
}
