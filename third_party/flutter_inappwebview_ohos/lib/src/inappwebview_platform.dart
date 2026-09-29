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

import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import 'chrome_safari_browser/chrome_safari_browser.dart';
import 'cookie_manager.dart';
import 'http_auth_credentials_database.dart';
import 'find_interaction/main.dart';
import 'in_app_browser/in_app_browser.dart';
import 'in_app_webview/main.dart';
import 'print_job/main.dart';
import 'pull_to_refresh/main.dart';
import 'web_message/main.dart';
import 'web_storage/main.dart';
import 'process_global_config.dart';
import 'proxy_controller.dart';
import 'service_worker_controller.dart';
import 'tracing_controller.dart';
import 'webview_asset_loader.dart';
import 'webview_environment/main.dart';
import 'webview_feature.dart' as wv;

/// Implementation of [InAppWebViewPlatform] using the WebView API.
class OhosInAppWebViewPlatform extends InAppWebViewPlatform {
  /// Registers this class as the default instance of [InAppWebViewPlatform].
  static void registerWith() {
    InAppWebViewPlatform.instance = OhosInAppWebViewPlatform();
  }

  /// Creates a new [OhosCookieManager].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [CookieManager] in `flutter_inappwebview` instead.
  @override
  OhosCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) {
    return OhosCookieManager(params);
  }

  /// Creates a new [OhosInAppWebViewController].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [InAppWebViewController] in `flutter_inappwebview` instead.
  @override
  OhosInAppWebViewController createPlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) {
    return OhosInAppWebViewController(params);
  }

  /// Creates a new empty [OhosInAppWebViewController] to access static methods.
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [InAppWebViewController] in `flutter_inappwebview` instead.
  @override
  OhosInAppWebViewController createPlatformInAppWebViewControllerStatic() {
    return OhosInAppWebViewController.static();
  }

  /// Creates a new [OhosInAppWebViewWidget].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [InAppWebView] in `flutter_inappwebview` instead.
  @override
  OhosInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return OhosInAppWebViewWidget(params);
  }

  /// Creates a new [OhosFindInteractionController].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [FindInteractionController] in `flutter_inappwebview` instead.
  @override
  OhosFindInteractionController createPlatformFindInteractionController(
    PlatformFindInteractionControllerCreationParams params,
  ) {
    return OhosFindInteractionController(params);
  }

  /// Creates a new [OhosPrintJobController].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [PrintJobController] in `flutter_inappwebview` instead.
  @override
  OhosPrintJobController createPlatformPrintJobController(
    PlatformPrintJobControllerCreationParams params,
  ) {
    return OhosPrintJobController(params);
  }

  /// Creates a new [OhosPullToRefreshController].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [PullToRefreshController] in `flutter_inappwebview` instead.
  @override
  OhosPullToRefreshController createPlatformPullToRefreshController(
    PlatformPullToRefreshControllerCreationParams params,
  ) {
    return OhosPullToRefreshController(params);
  }

  /// Creates a new [OhosWebMessageChannel].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [WebMessageChannel] in `flutter_inappwebview` instead.
  @override
  OhosWebMessageChannel createPlatformWebMessageChannel(
    PlatformWebMessageChannelCreationParams params,
  ) {
    return OhosWebMessageChannel(params);
  }

  /// Creates a new empty [OhosWebMessageChannel] to access static methods.
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [WebMessageChannel] in `flutter_inappwebview` instead.
  @override
  OhosWebMessageChannel createPlatformWebMessageChannelStatic() {
    return OhosWebMessageChannel.static();
  }

  /// Creates a new [OhosWebMessageListener].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [WebMessageListener] in `flutter_inappwebview` instead.
  @override
  OhosWebMessageListener createPlatformWebMessageListener(
    PlatformWebMessageListenerCreationParams params,
  ) {
    return OhosWebMessageListener(params);
  }

  /// Creates a new [OhosJavaScriptReplyProxy].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [JavaScriptReplyProxy] in `flutter_inappwebview` instead.
  @override
  OhosJavaScriptReplyProxy createPlatformJavaScriptReplyProxy(
    PlatformJavaScriptReplyProxyCreationParams params,
  ) {
    return OhosJavaScriptReplyProxy(params);
  }

  /// Creates a new [OhosWebMessagePort].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [WebMessagePort] in `flutter_inappwebview` instead.
  @override
  OhosWebMessagePort createPlatformWebMessagePort(
    PlatformWebMessagePortCreationParams params,
  ) {
    return OhosWebMessagePort(params);
  }

  /// Creates a new [OhosWebStorage].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [OhosWebStorage] in `flutter_inappwebview` instead.
  @override
  OhosWebStorage createPlatformWebStorage(
    PlatformWebStorageCreationParams params,
  ) {
    return OhosWebStorage(params);
  }

  /// Creates a new [OhosLocalStorage].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [OhosLocalStorage] in `flutter_inappwebview` instead.
  @override
  OhosLocalStorage createPlatformLocalStorage(
    PlatformLocalStorageCreationParams params,
  ) {
    return OhosLocalStorage(params);
  }

  /// Creates a new [OhosSessionStorage].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [PlatformSessionStorage] in `flutter_inappwebview` instead.
  @override
  OhosSessionStorage createPlatformSessionStorage(
    PlatformSessionStorageCreationParams params,
  ) {
    return OhosSessionStorage(params);
  }

  /// Creates a new [OhosHeadlessInAppWebView].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [HeadlessInAppWebView] in `flutter_inappwebview` instead.
  @override
  OhosHeadlessInAppWebView createPlatformHeadlessInAppWebView(
    PlatformHeadlessInAppWebViewCreationParams params,
  ) {
    return OhosHeadlessInAppWebView(params);
  }

  /// Creates a new [OhosHttpAuthCredentialDatabase].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [HttpAuthCredentialDatabase] in `flutter_inappwebview` instead.
  @override
  OhosHttpAuthCredentialDatabase createPlatformHttpAuthCredentialDatabase(
    PlatformHttpAuthCredentialDatabaseCreationParams params,
  ) {
    return OhosHttpAuthCredentialDatabase(params);
  }

  /// Creates a new [OhosInAppBrowser].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [InAppBrowser] in `flutter_inappwebview` instead.
  @override
  OhosInAppBrowser createPlatformInAppBrowser(
    PlatformInAppBrowserCreationParams params,
  ) {
    return OhosInAppBrowser(params);
  }

  /// Creates a new empty [OhosInAppBrowser] to access static methods.
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [InAppBrowser] in `flutter_inappwebview` instead.
  @override
  OhosInAppBrowser createPlatformInAppBrowserStatic() {
    return OhosInAppBrowser.static();
  }

  /// Creates a new [OhosProcessGlobalConfig].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [ProcessGlobalConfig] in `flutter_inappwebview` instead.
  @override
  OhosProcessGlobalConfig createPlatformProcessGlobalConfig(
    PlatformProcessGlobalConfigCreationParams params,
  ) {
    return OhosProcessGlobalConfig(params);
  }

  /// Creates a new [OhosProxyController].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [ProxyController] in `flutter_inappwebview` instead.
  @override
  OhosProxyController createPlatformProxyController(
    PlatformProxyControllerCreationParams params,
  ) {
    return OhosProxyController(params);
  }

  /// Creates a new [OhosServiceWorkerController].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [ServiceWorkerController] in `flutter_inappwebview` instead.
  @override
  OhosServiceWorkerController createPlatformServiceWorkerController(
    PlatformServiceWorkerControllerCreationParams params,
  ) {
    return OhosServiceWorkerController(params);
  }

  /// Creates a new empty [OhosServiceWorkerController] to access static methods.
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [ServiceWorkerController] in `flutter_inappwebview` instead.
  @override
  OhosServiceWorkerController createPlatformServiceWorkerControllerStatic() {
    return OhosServiceWorkerController.static();
  }

  /// Creates a new [OhosTracingController].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [TracingController] in `flutter_inappwebview` instead.
  @override
  OhosTracingController createPlatformTracingController(
    PlatformTracingControllerCreationParams params,
  ) {
    return OhosTracingController(params);
  }

  /// Creates a new [OhosAssetsPathHandler].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [AssetsPathHandler] in `flutter_inappwebview` instead.
  @override
  OhosAssetsPathHandler createPlatformAssetsPathHandler(
    PlatformAssetsPathHandlerCreationParams params,
  ) {
    return OhosAssetsPathHandler(params);
  }

  /// Creates a new [OhosResourcesPathHandler].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [ResourcesPathHandler] in `flutter_inappwebview` instead.
  @override
  OhosResourcesPathHandler createPlatformResourcesPathHandler(
    PlatformResourcesPathHandlerCreationParams params,
  ) {
    return OhosResourcesPathHandler(params);
  }

  /// Creates a new [OhosInternalStoragePathHandler].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [InternalStoragePathHandler] in `flutter_inappwebview` instead.
  @override
  OhosInternalStoragePathHandler createPlatformInternalStoragePathHandler(
    PlatformInternalStoragePathHandlerCreationParams params,
  ) {
    return OhosInternalStoragePathHandler(params);
  }

  /// Creates a new [OhosCustomPathHandler].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [CustomPathHandler] in `flutter_inappwebview` instead.
  @override
  OhosCustomPathHandler createPlatformCustomPathHandler(
    PlatformCustomPathHandlerCreationParams params,
  ) {
    return OhosCustomPathHandler(params);
  }

  /// Creates a new [wv.OhosWebViewFeature].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [WebViewFeature] in `flutter_inappwebview` instead.
  @override
  wv.OhosWebViewFeature createPlatformWebViewFeature(
    PlatformWebViewFeatureCreationParams params,
  ) {
    return wv.OhosWebViewFeature(params);
  }

  /// Creates a new empty [wv.OhosWebViewFeature] to access static methods.
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [WebViewFeature] in `flutter_inappwebview` instead.
  @override
  wv.OhosWebViewFeature createPlatformWebViewFeatureStatic() {
    return wv.OhosWebViewFeature.static();
  }

  /// Creates a new [OhosChromeSafariBrowser].
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [ChromeSafariBrowser] in `flutter_inappwebview` instead.
  @override
  OhosChromeSafariBrowser createPlatformChromeSafariBrowser(
    PlatformChromeSafariBrowserCreationParams params,
  ) {
    return OhosChromeSafariBrowser(params);
  }

  /// Creates a new empty [OhosChromeSafariBrowser] to access static methods.
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [ChromeSafariBrowser] in `flutter_inappwebview` instead.
  @override
  OhosChromeSafariBrowser createPlatformChromeSafariBrowserStatic() {
    return OhosChromeSafariBrowser.static();
  }

  /// Creates a new empty [OhosWebStorageManager] to access static methods.
  ///
  /// This function should only be called by the app-facing package.
  /// Look at using [WebStorageManager] in `flutter_inappwebview` instead.
  @override
  OhosWebStorageManager createPlatformWebStorageManager(
      PlatformWebStorageManagerCreationParams params) {
    return OhosWebStorageManager(params);
  }

  /// Creates a new [OhosWebViewEnvironment].
  @override
  OhosWebViewEnvironment createPlatformWebViewEnvironment(
    PlatformWebViewEnvironmentCreationParams params,
  ) {
    return OhosWebViewEnvironment(params);
  }

  /// Creates a new empty [OhosWebViewEnvironment] to access static methods.
  @override
  OhosWebViewEnvironment createPlatformWebViewEnvironmentStatic() {
    return OhosWebViewEnvironment.static();
  }
}
