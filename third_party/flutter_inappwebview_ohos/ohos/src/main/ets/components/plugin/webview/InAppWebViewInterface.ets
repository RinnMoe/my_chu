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

import web_webview from '@ohos.web.webview';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { InAppBrowserDelegate } from '../in_app_browser/InAppBrowserDelegate';
import ContentWorld from '../types/ContentWorld';
import URLRequest from '../types/URLRequest';
import UserContentController from '../types/UserContentController';
import { ValueCallback } from '../types/ValueCallback';
import { WebMessageChannel } from './web_message/WebMessageChannel';
import HitTestResult from '../types/HitTestResult';
import { HashMap } from '@kit.ArkTS';
import PrintJobSettings from '../print_job/PrintJobSettings';
import WebMessageListener from './web_message/WebMessageListener';
import { Any } from '@ohos/flutter_ohos';
import cert from '@ohos.security.cert';

export default interface InAppWebViewInterface {
  loadUrl(urlRequest: URLRequest): void;

  postUrl(url: string, postData: ArrayBuffer): void;

  loadDataWithBaseURL(baseUrl: string, data: string, mimeType: string, encoding: string, historyUrl: string): void;

  loadFile(assetFilePath: string): void;

  getController(): web_webview.WebviewController

  getSafeCustomUserAgent(): string;

  getPlugin(): InAppWebViewFlutterPlugin;

  getWebMessageChannels(): Map<string, WebMessageChannel>;

  getUserContentController(): UserContentController | null

  evaluateJavascript(source: string, contentWorld: ContentWorld | null, resultCallback: ValueCallback<string> | null): void;

  injectJavascriptFileFromUrl(urlFile: string, scriptHtmlTagAttributes: Map<string, Any>): void;

  injectCSSCode(source: string): void

  injectCSSFileFromUrl(urlFile: string, cssLinkHtmlTagAttributes: Map<string, Any>): void

  takeScreenshot(screenshotConfiguration: Map<string, Any> | null, result: MethodResult): void

  getInAppBrowserDelegate(): InAppBrowserDelegate | null

  getCustomSettings(): Map<string, Any> | null

  getCopyBackForwardList(): HashMap<string, Any>

  clearAllCache(): void

  clearCookies(): void

  scrollTo(x: number, y: number, animated: boolean): void

  scrollBy(x: number, y: number, animated: boolean): void

  printCurrentPage(settings: PrintJobSettings): string | null

  setContextMenu(contextMenu: Map<string, Any>): void

  requestFocusNodeHref(): Promise<Map<string, Any>>

  requestImageRef(): Promise<Map<string, Any>>

  createCompatWebMessageChannel(): WebMessageChannel

  addWebMessageListener(webMessageListener: WebMessageListener): void

  canScrollVertically(): boolean

  canScrollHorizontally(callback: ValueCallback<boolean>): void

  getUrl(): string

  getTitle(): string

  getProgress(): number

  reload(): void

  canGoBack(): boolean

  goBack(): void

  canGoForward(): boolean

  goForward(): void

  canGoBackOrForward(steps: number): boolean

  goBackOrForward(steps: number): void

  stopLoading(): void

  getLoading(): boolean

  clearSslPreferences(): void

  findAllAsync(find: string): void

  findNext(forward: boolean): void

  clearMatches(): void

  onPause(): void

  onResume(): void

  pauseTimers(): void

  resumeTimers(): void

  getContentHeight(): number

  zoomBy(zoomFactor: number): void

  getOriginalUrl(): string

  getHitTestResult(): web_webview.HitTestValue

  pageDown(bottom: boolean): boolean

  pageUp(top: boolean): boolean

  zoomIn(): boolean

  zoomOut(): boolean

  clearFocus(): void

  getCertificate(): Promise<cert.X509Cert | null>

  clearHistory(): void

  refresh(): void

  scrollToTop(): void
}