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
import { Any, Log, MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import InAppBrowserSession from '../in_app_browser/InAppBrowserSession';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import ContentWorld from '../types/ContentWorld';
import URLRequest from '../types/URLRequest';
import { WebViewChannelDelegateMethods } from './WebViewChannelDelegateMethods';
import InAppWebView from './in_app_webview/InAppWebView';
import InAppBrowserSettings from '../in_app_browser/InAppBrowserSettings';
import { HashMap, List, util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import InAppWebViewSettings from './in_app_webview/InAppWebViewSettings';
import PrintJobSettings from '../print_job/PrintJobSettings';
import HitTestResult from '../types/HitTestResult';
import UserScript from '../types/UserScript';
import WebMessagePortCompatExt from '../types/WebMessagePortCompatExt';
import { WebMessageChannel } from './web_message/WebMessageChannel';
import WebMessageCompatExt from '../types/WebMessageCompatExt';
import WebMessageListener from './web_message/WebMessageListener';
import ChannelResultUtil from '../types/ChannelResultUtil';
import DownloadStartRequest from '../types/DownloadStartRequest';
import BaseCallbackResultImpl from '../types/BaseCallbackResultImpl';
import JsAlertResponse from '../types/JsAlertResponse';
import JsConfirmResponse from '../types/JsConfirmResponse';
import JsPromptResponse from '../types/JsPromptResponse';
import JsBeforeUnloadResponse from '../types/JsBeforeUnloadResponse';
import CreateWindowAction from '../types/CreateWindowAction';
import GeolocationPermissionShowPromptResponse from '../types/GeolocationPermissionShowPromptResponse';
import PermissionResponse from '../types/PermissionResponse';
import WebResourceRequestExt from '../types/WebResourceRequestExt';
import WebResourceErrorExt from '../types/WebResourceErrorExt';
import WebResourceResponseExt from '../types/WebResourceResponseExt';
import WebResourceResponseHelper from '../types/WebResourceResponseHelper';
import HttpAuthResponse from '../types/HttpAuthResponse';
import HttpAuthenticationChallenge from '../types/HttpAuthenticationChallenge';
import SyncBaseCallbackResultImpl from '../types/SyncBaseCallbackResultImpl';
import CustomSchemeResponse from '../types/CustomSchemeResponse';
import { NavigationActionPolicy } from '../types/NavigationActionPolicy';
import { NavigationResponsePolicy } from '../types/NavigationResponsePolicy';
import NavigationAction from '../types/NavigationAction';
import SslCertificateExt from '../types/SslCertificateExt';
import ServerTrustAuthResponse from '../types/ServerTrustAuthResponse';
import ServerTrustChallenge from '../types/ServerTrustChallenge';
import ClientCertResponse from '../types/ClientCertResponse';
import ClientCertChallenge from '../types/ClientCertChallenge';
import SafeBrowsingResponse from '../types/SafeBrowsingResponse';

const LOG_TAG = 'WebViewChannelDelegate';
const DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER = 1;

export default class WebViewChannelDelegate extends ChannelDelegateImpl {
  private webView: InAppWebView | null = null;

  constructor(webView: InAppWebView, channel: MethodChannel) {
    super(channel);
    this.webView = webView;
  }

  public async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    let method: WebViewChannelDelegateMethods;
    try {
      method = WebViewChannelDelegateMethods[call.method];
    } catch (e) {
      result.notImplemented();
      return;
    }
    if (method === undefined || method === null) {
      result.notImplemented();
      return;
    }
    try {
    switch (method) {
      case WebViewChannelDelegateMethods.getUrl:
        result.success((this.webView != null) ? this.webView!.getUrl() : null);
        break;
      case WebViewChannelDelegateMethods.getTitle:
        result.success((this.webView != null) ? this.webView!.getTitle() : null);
        break;
      case WebViewChannelDelegateMethods.getProgress:
        result.success((this.webView != null) ? this.webView!.getProgress() : null);
        break;
      case WebViewChannelDelegateMethods.loadUrl:
        if (this.webView != null) {
          try {
            let urlRequest = call.argument('urlRequest') as Map<string, Object> | null;
            if (urlRequest != null) {
              let request = URLRequest.fromMap(urlRequest);
              await this.webView!.loadUrl(URLRequest.fromMap(urlRequest)!);
            }
            result.success(true);
          } catch (e) {
            result.error('loadUrlError', e?.message ?? 'Unknown error', null);
          }
        }
        break;
      case WebViewChannelDelegateMethods.postUrl:
        if (this.webView != null) {
          try {
            let url: string | null = call.argument('url') as string | null;
            let postData: ArrayBuffer | null = call.argument('postData') as ArrayBuffer | null;
            if (url != null && postData != null) {
              await this.webView!.postUrl(url, postData);
            }
            result.success(true);
          } catch (e) {
            result.error('postUrlError', e?.message ?? 'Unknown error', null);
          }
        }
        break;
      case WebViewChannelDelegateMethods.loadData:
        if (this.webView != null) {
          let data: string | null = call.argument('data') as string | null;
          if (data == null) {
            result.error('loadDataError', 'data parameter is required', null);
            break;
          }
          let mimeType: string = call.argument('mimeType') as string;
          let encoding: string = call.argument('encoding') as string;
          let baseUrl: string = call.argument('baseUrl') as string;
          let historyUrl: string = call.argument('historyUrl') as string;
          this.webView!.loadDataWithBaseURL(baseUrl, data, mimeType, encoding, historyUrl).then(() => {
            result.success(true);
          }).catch((e: Object) => {
            ChannelResultUtil.reportError(LOG_TAG, 'loadData', result, e);
          });
        } else {
          result.success(true);
        }
        break;
      case WebViewChannelDelegateMethods.loadFile:
        if (this.webView != null && this.webView instanceof InAppWebView) {
          let assetFilePath: string | null = call.argument('assetFilePath') as string | null;
          if (assetFilePath == null || assetFilePath.length === 0) {
            result.error('loadFileError', 'assetFilePath parameter is required', null);
            break;
          }
          (this.webView as InAppWebView).loadFile(assetFilePath).then(() => {
            result.success(true);
          }).catch((e: Object) => {
            ChannelResultUtil.reportError(LOG_TAG, 'loadFile', result, e);
          });
        } else {
          result.success(true);
        }
        break;
      case WebViewChannelDelegateMethods.evaluateJavascript:
        if (this.webView != null) {
          let source: string = call.argument('source');
          let contentWorldMap: Map<string, Any> = call.argument('contentWorld') as Map<string, Any>;
          let contentWorld: ContentWorld | null = ContentWorld.fromMap(contentWorldMap);
          this.webView!.evaluateJavascript(source, contentWorld!, {
            onReceiveValue: (value: string | null): void => {
              result.success(value);
            },
            onError: (error: string): void => {
              result.error(LOG_TAG, error, null);
            }
          });
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.injectJavascriptFileFromUrl:
        if (this.webView != null) {
          let urlFile: string = call.argument('urlFile');
          let scriptHtmlTagAttributes: Map<string, Any> = call.argument('scriptHtmlTagAttributes') as Map<string, Any>;
          this.webView!.injectJavascriptFileFromUrl(urlFile, scriptHtmlTagAttributes);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.injectCSSCode:
        if (this.webView != null) {
          let source: string = call.argument('source');
          this.webView!.injectCSSCode(source);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.injectCSSFileFromUrl:
        if (this.webView != null) {
          let urlFile: string = call.argument('urlFile');
          let cssLinkHtmlTagAttributes: Map<string, Any> = call.argument('cssLinkHtmlTagAttributes') as Map<string, Any>;
          this.webView!.injectCSSFileFromUrl(urlFile, cssLinkHtmlTagAttributes);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.reload:
        if (this.webView != null)
          this.webView!.reload();
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.goBack:
        if (this.webView != null)
          this.webView!.goBack();
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.canGoBack:
        result.success((this.webView != null) && this.webView!.canGoBack());
        break;
      case WebViewChannelDelegateMethods.goForward:
        if (this.webView != null)
          this.webView!.goForward();
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.canGoForward:
        result.success((this.webView != null) && this.webView!.canGoForward());
        break;
      case WebViewChannelDelegateMethods.goBackOrForward:
        if (this.webView != null)
          this.webView!.goBackOrForward(call.argument('steps') as number);
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.canGoBackOrForward:
        result.success((this.webView != null) && this.webView!.canGoBackOrForward(call.argument('steps') as number));
        break;
      case WebViewChannelDelegateMethods.stopLoading:
        if (this.webView != null)
          this.webView!.stopLoading();
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.isLoading:
        result.success((this.webView != null) && this.webView!.getLoading());
        break;
      case WebViewChannelDelegateMethods.takeScreenshot:
        if (this.webView != null) {
          let screenshotConfiguration: Map<string, Any> = call.argument('screenshotConfiguration') as Map<string, Any>;
          this.webView!.takeScreenshot(screenshotConfiguration, result);
        } else
          result.success(null);
        break;
      case WebViewChannelDelegateMethods.setSettings:
        if (this.webView != null && this.webView!.getInAppBrowserDelegate() instanceof InAppBrowserSession) {
          let session: InAppBrowserSession = this.webView!.getInAppBrowserDelegate() as InAppBrowserSession;
          let inAppBrowserSettings: InAppBrowserSettings = new InAppBrowserSettings();
          let inAppBrowserSettingsMap: Map<string, Any> = call.argument('settings') as Map<string, Any>;
          inAppBrowserSettings.parse(inAppBrowserSettingsMap);
          session.setSettings(inAppBrowserSettings, inAppBrowserSettingsMap);
        } else if (this.webView != null) {
          let inAppWebViewSettings: InAppWebViewSettings = new InAppWebViewSettings();
          let inAppWebViewSettingsMap: Map<string, Any> = call.argument('settings') as Map<string, Any>;
          inAppWebViewSettings.parse(inAppWebViewSettingsMap);
          this.webView!.setSettings(inAppWebViewSettings, inAppWebViewSettingsMap);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.getSettings:
        try {
          if (this.webView != null && this.webView!.getInAppBrowserDelegate() instanceof InAppBrowserSession) {
            let session: InAppBrowserSession = this.webView!.getInAppBrowserDelegate() as InAppBrowserSession;
            result.success(session.getCustomSettings());
          } else {
            result.success((this.webView != null) ? this.webView!.getCustomSettings() : null);
          }
        } catch (e) {
          Log.e(LOG_TAG, 'getSettings error: ' + e);
          result.error(LOG_TAG, e?.message ?? 'getSettings failed', null);
        }
        break;
      case WebViewChannelDelegateMethods.close:
        if (this.webView != null && this.webView!.getInAppBrowserDelegate() instanceof InAppBrowserSession) {
          let session: InAppBrowserSession = this.webView!.getInAppBrowserDelegate() as InAppBrowserSession;
          session.close(result);
        } else {
          result.notImplemented();
        }
        break;
      case WebViewChannelDelegateMethods.show:
        if (this.webView != null && this.webView!.getInAppBrowserDelegate() instanceof InAppBrowserSession) {
          let session: InAppBrowserSession = this.webView!.getInAppBrowserDelegate() as InAppBrowserSession;
          session.show();
          result.success(true);
        } else {
          result.notImplemented();
        }
        break;
      case WebViewChannelDelegateMethods.hide:
        if (this.webView != null && this.webView!.getInAppBrowserDelegate() instanceof InAppBrowserSession) {
          let session: InAppBrowserSession = this.webView!.getInAppBrowserDelegate() as InAppBrowserSession;
          session.hide();
          result.success(true);
        } else {
          result.notImplemented();
        }
        break;
      case WebViewChannelDelegateMethods.isHidden:
        if (this.webView != null && this.webView!.getInAppBrowserDelegate() instanceof InAppBrowserSession) {
          let session: InAppBrowserSession = this.webView!.getInAppBrowserDelegate() as InAppBrowserSession;
          result.success(session.isHidden);
        } else {
          result.notImplemented();
        }
        break;
      case WebViewChannelDelegateMethods.getCopyBackForwardList:
        result.success((this.webView != null) ? this.webView!.getCopyBackForwardList() : null);
        break;
      case WebViewChannelDelegateMethods.startSafeBrowsing:
        if (this.webView != null && this.webView instanceof InAppWebView) {
          result.success((this.webView as InAppWebView).startSafeBrowsing());
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.clearCache:
        if (this.webView != null) {
          try {
            // Match Android: clear cache only, NOT cookies
            this.webView!.getController().removeCache(true);
          } catch (e) {
            Log.e(LOG_TAG, 'clearCache error: ' + JSON.stringify(e));
          }
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.clearSslPreferences:
        if (this.webView != null)
          this.webView!.clearSslPreferences();
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.findAll:
        if (this.webView != null) {
          let find: string = call.argument('find');
          this.webView!.findAllAsync(find);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.findNext:
        if (this.webView != null) {
          let forward: boolean = call.argument('forward') as boolean;
          this.webView!.findNext(forward);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.clearMatches:
        if (this.webView != null) {
          this.webView!.clearMatches();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.scrollTo:
        if (this.webView != null) {
          let x: number = call.argument('x') as number;
          let y: number = call.argument('y') as number;
          let animated: boolean = call.argument('animated') as boolean;
          this.webView!.scrollTo(x, y, animated);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.scrollBy:
        if (this.webView != null) {
          let x: number = call.argument('x') as number;
          let y: number = call.argument('y') as number;
          let animated: boolean = call.argument('animated') as boolean;
          this.webView!.scrollBy(x, y, animated);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.pause:
        if (this.webView != null) {
          this.webView!.onPause();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.resume:
        if (this.webView != null) {
          this.webView!.onResume();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.pauseTimers:
        if (this.webView != null) {
          this.webView!.pauseTimers();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.resumeTimers:
        if (this.webView != null) {
          this.webView!.resumeTimers();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.printCurrentPage:
        if (this.webView != null) {
          let settings: PrintJobSettings = new PrintJobSettings();
          let settingsMap: Map<string, Any> | null = call.argument('settings') as Map<string, Any> | null;
          if (settingsMap != null) {
            settings.parse(settingsMap);
          }
          let printResult: string | null = this.webView!.printCurrentPage(settings);
          result.success(printResult);
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.getContentHeight:
        if (this.webView instanceof InAppWebView) {
          result.success(this.webView!.getContentHeight());
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.getContentWidth:
        if (this.webView instanceof InAppWebView) {
          this.webView!.getContentWidth({
            onReceiveValue(contentWidth: number | null): void {
              result.success(contentWidth);
            }
          });
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.zoomBy:
        try {
          if (this.webView != null) {
            let zoomFactor: number = call.argument('zoomFactor') as number;
            this.webView!.zoomBy(zoomFactor as number);
          }
          result.success(true);
        } catch (e) {
          result.error('zoomBy error', e.message, null);
        }
        break;
      case WebViewChannelDelegateMethods.getOriginalUrl:
        result.success((this.webView != null) ? this.webView!.getOriginalUrl() : null);
        break;
      case WebViewChannelDelegateMethods.getZoomScale:
        if (this.webView instanceof InAppWebView) {
          result.success(this.webView!.getZoomScale());
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.getSelectedText:
        if ((this.webView instanceof InAppWebView)) {
          this.webView!.getSelectedText({
            onReceiveValue(value: string | null): void {
              result.success(value);
            }
          });
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.getHitTestResult:
        if (this.webView instanceof InAppWebView) {
          result.success(HitTestResult.fromWebViewHitTestResult(this.webView!.getHitTestResult())!.toMap());
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.pageDown:
        if (this.webView != null) {
          let bottom: boolean = call.argument('bottom') as boolean;
          result.success(this.webView!.pageDown(bottom));
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.pageUp:
        if (this.webView != null) {
          let top: boolean = call.argument('top') as boolean;
          result.success(this.webView!.pageUp(top));
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.saveWebArchive:
        if (this.webView != null) {
          let filePath: string = call.argument('filePath');
          let autoname: boolean = call.argument('autoname') as boolean;
          this.webView!.saveWebArchive(filePath, autoname, {
            onReceiveValue(value: string | null) {
              result.success(value);
            }
          });
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.zoomIn:
        if (this.webView != null) {
          result.success(this.webView!.zoomIn());
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.zoomOut:
        if (this.webView != null) {
          result.success(this.webView!.zoomOut());
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.clearFocus:
        if (this.webView != null) {
          this.webView!.clearFocus();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.setContextMenu:
        if (this.webView != null) {
          let contextMenu: Map<string, Any> = call.argument('contextMenu') as Map<string, Any>;
          this.webView!.setContextMenu(contextMenu);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.requestFocusNodeHref:
        if (this.webView != null) {
          try {
                 result.success(await this.webView!.requestFocusNodeHref());
               } catch (error) {
                 const e = error as BusinessError;
                 Log.e(LOG_TAG, `requestFocusNodeHref ErrorCode: ${e.code}, Message: ${e.message}`);
                 result.error('requestFocusNodeHrefError', e.message, null);
               }
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.requestImageRef:
        if (this.webView != null) {
          try {
                 result.success(await this.webView!.requestImageRef());
               } catch (error) {
                 const e = error as BusinessError;
                 Log.e(LOG_TAG, `requestImageRef ErrorCode: ${e.code}, Message: ${e.message}`);
                 result.error('requestImageRefError', e.message, null);
               }
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.getScrollX:
        if (this.webView != null) {
          try {
            result.success(this.webView!.getScrollXSync());
          } catch (error) {
            const e = error as BusinessError;
            Log.e(LOG_TAG, `getScrollX ErrorCode: ${e.code}, Message: ${e.message}`);
            result.error(LOG_TAG, e.message, null);
            return;
          }
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.getScrollY:
        if (this.webView != null) {
          try {
            result.success(this.webView!.getScrollYSync());
          } catch (error) {
            const e = error as BusinessError;
            Log.e(LOG_TAG, `getScrollY ErrorCode: ${e.code}, Message: ${e.message}`);
            result.error(LOG_TAG, e.message, null);
            return;
          }
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.getCertificate:
        if (this.webView != null) {
          result.success(await SslCertificateExt.toMap(await this.webView!.getCertificate()));
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.clearHistory:
        if (this.webView != null) {
          this.webView!.clearHistory();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.addUserScript:
        if (this.webView != null && this.webView!.getUserContentController() != null) {
          let userScriptMap: Map<string, Any> = call.argument('userScript') as Map<string, Any>;
          let userScript: UserScript | null = UserScript.fromMap(userScriptMap);
          let userContentController = this.webView!.getUserContentController()!;
          result.success(userContentController.addUserOnlyScript(userScript!));
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.removeUserScript:
        if (this.webView != null && this.webView!.getUserContentController() != null) {
          let userScriptMap: Map<string, Any> = call.argument('userScript') as Map<string, Any>;
          let userScript: UserScript | null = UserScript.fromMap(userScriptMap);
          let userContentController = this.webView!.getUserContentController()!;
          result.success(userContentController
            .removeUserOnlyScript(userScript!));
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.removeUserScriptsByGroupName:
        if (this.webView != null && this.webView!.getUserContentController() != null) {
          let groupName: string = call.argument('groupName');
          this.webView!.getUserContentController()!.removeUserOnlyScriptsByGroupName(groupName);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.removeAllUserScripts:
        if (this.webView != null && this.webView!.getUserContentController() != null) {
          this.webView!.getUserContentController()!.removeAllUserOnlyScripts();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.callAsyncJavaScript:
        if (this.webView != null) {
          let functionBody: string = call.argument('functionBody');
          let functionArguments: Map<string, Any> | null = call.argument('arguments') as Map<string, Any> | null;
          let contentWorldMap: Map<string, Any> | null = call.argument('contentWorld') as Map<string, Any> | null;
          let contentWorld: ContentWorld | null = contentWorldMap != null ? ContentWorld.fromMap(contentWorldMap) : null;
          this.webView!.callAsyncJavaScript(functionBody, functionArguments ?? new Map<string, Any>(), contentWorld, {
            onReceiveValue: (value: string | null): void => {
              result.success(value);
            }
          });
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.isSecureContext:
        if (this.webView != null) {
          this.webView!.isSecureContext({
            onReceiveValue(value: boolean | null): void {
              result.success(value);
            }
          });
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.createWebMessageChannel:
        if (this.webView != null) {
          result.success(this.webView!.createCompatWebMessageChannel().toMap());
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.postWebMessage:
        try {
          let targetOrigin: string = call.argument('targetOrigin');
          let dataArg: string | Array<number> | null = call.argument('data');
          let type: number = (call.argument('type') as number) ?? 0;
          let messageData: string = '';
          if (type == DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER && dataArg != null) {
            let bytes = dataArg as Array<number>;
            for (let i = 0; i < bytes.length; i++) {
              messageData += String.fromCharCode(bytes[i]);
            }
          } else {
            messageData = dataArg != null ? (dataArg as string) : '';
          }
          // ports 是扁平数组: [channelId0, index0, channelId1, index1, ...]
          // 因为 MethodChannel 对嵌套 Map 序列化有问题，所以用扁平数组传递
          let portsRaw: Array<string | number> = call.argument('ports') as Array<string | number>;
          let compatPorts: List<web_webview.WebMessagePort> = new List<web_webview.WebMessagePort>();
          if (portsRaw != null && portsRaw.length >= 2) {
            for (let i = 0; i < portsRaw.length; i += 2) {
              let channelId: string = portsRaw[i] as string;
              let dartIndex: number = portsRaw[i + 1] as number;
              let webMessageChannel: WebMessageChannel | undefined = this.webView!.getWebMessageChannels().get(channelId);
              if (webMessageChannel != null) {
                // Dart index=0 (port1) -> compatPorts[1] (Native端), Dart index=1 (port2) -> compatPorts[0] (传JS端)
                let nativeIndex: number = dartIndex == 0 ? 1 : 0;
                compatPorts.add(webMessageChannel.compatPorts[nativeIndex]);
                // 标记端口为已转移 (对齐 Android)
                let transferredIdx: number = dartIndex == 0 ? 1 : 3;
                webMessageChannel.portState[transferredIdx] = true;
              }
            }
          }
          if (this.webView instanceof InAppWebView) {
            this.webView!.getController().postMessage(messageData, compatPorts.convertToArray(), targetOrigin)
            result.success(true);
          }
        } catch (e) {
          result.error(LOG_TAG, 'postWebMessage error: ' + (e.message ?? JSON.stringify(e)), null);
        }
        break;
      case WebViewChannelDelegateMethods.addWebMessageListener:
        if (this.webView != null) {
          let webMessageListenerMap: Map<string, Any> = call.argument('webMessageListener') as Map<string, Any>;
          let webMessageListener: WebMessageListener | null = WebMessageListener.fromMap(this.webView, this.webView!.getPlugin()
            .messenger, webMessageListenerMap);
          try {
            this.webView!.addWebMessageListener(webMessageListener!);
            result.success(true);
          } catch (e) {
            result.error(LOG_TAG, e.getMessage(), null);
          }
        } else {
          result.success(true);
        }
        break;
      case WebViewChannelDelegateMethods.canScrollVertically:
        if (this.webView != null) {
          this.webView!.measureCanScrollVertically({
            onReceiveValue: (canScroll: boolean | null): void => {
              result.success(canScroll);
            }
          });
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.canScrollHorizontally:
        if (this.webView != null) {
          this.webView!.canScrollHorizontally({
            onReceiveValue: (canScroll: boolean | null): void => {
              result.success(canScroll);
            }
          });
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.isInFullscreen:
        if (this.webView != null) {
          result.success(this.webView!.isInFullscreen());
        } else {
          result.success(false);
        }
        break;
      case WebViewChannelDelegateMethods.setAllMediaPlaybackSuspended:
        if (this.webView != null && this.webView instanceof InAppWebView) {
          let suspended: boolean = call.argument('suspended') as boolean;
          (this.webView as InAppWebView).setAllMediaPlaybackSuspended(suspended);
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.closeAllMediaPresentations:
        if (this.webView != null && this.webView instanceof InAppWebView) {
          (this.webView as InAppWebView).closeAllMediaPresentations();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.requestMediaPlaybackState:
        if (this.webView != null && this.webView instanceof InAppWebView) {
          (this.webView as InAppWebView).requestMediaPlaybackState(result);
        } else {
          result.success(null);
        }
        break;
      case WebViewChannelDelegateMethods.clearFormData:
        if (this.webView != null && this.webView instanceof InAppWebView) {
          (this.webView as InAppWebView).clearFormData();
        }
        result.success(true);
        break;
      case WebViewChannelDelegateMethods.getMetaThemeColor:
        if (this.webView != null) {
          let themeColorSource: string = "(function() {" +
            "function isVisibleColor(color) {" +
            "  return color != null && color.length > 0 && color !== 'rgba(0, 0, 0, 0)' && color !== 'transparent' && color !== 'initial' && color !== 'inherit';" +
            "}" +
            "var meta = document.querySelector('meta[name=\"theme-color\"], meta[name=\"theme_color\"], meta[name=\"msapplication-TileColor\"]');" +
            "if (meta != null && meta.content != null && meta.content.length > 0) return meta.content;" +
            "var metas = document.head != null ? document.head.getElementsByTagName('meta') : [];" +
            "for (var i = 0; i < metas.length; i++) {" +
            "  var metaNode = metas[i];" +
            "  var name = (metaNode.getAttribute('name') || metaNode.name || '').toLowerCase();" +
            "  if (name === 'theme-color' && metaNode.content != null && metaNode.content.length > 0) return metaNode.content;" +
            "}" +
            "var elements = [document.querySelector('header'), document.querySelector('nav'), document.body, document.documentElement];" +
            "for (var j = 0; j < elements.length; j++) {" +
            "  var element = elements[j];" +
            "  if (element == null) continue;" +
            "  var backgroundColor = window.getComputedStyle(element).backgroundColor;" +
            "  if (isVisibleColor(backgroundColor)) return backgroundColor;" +
            "}" +
            "return null;" +
            "})();";
          this.webView!.evaluateJavascript(themeColorSource, null, {
            onReceiveValue: (value: string | null): void => {
              if (value == null || value === 'null' || value === 'undefined' || value.length === 0) {
                result.success(null);
                return;
              }
              let colorValue: string = value;
              if (colorValue.startsWith("\"") && colorValue.endsWith("\"")) {
                colorValue = colorValue.substring(1, colorValue.length - 1);
              }
              result.success(colorValue);
            }
          });
        } else {
          result.success(null);
        }
        break;
      default:
        result.notImplemented();
        break;
    }
    } catch (e) {
      Log.e(LOG_TAG, `Unhandled exception in ${call.method}: ${e}`);
      result.error(LOG_TAG, e?.message ?? 'Unknown error', null);
    }
  }

  public onFindResultReceived(activeMatchOrdinal: number, numberOfMatches: number, isDoneCounting: boolean): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return
    let obj: Map<string, Any> = new Map<string, Any>()
    obj.set('activeMatchOrdinal', activeMatchOrdinal);
    obj.set('numberOfMatches', numberOfMatches);
    obj.set('isDoneCounting', isDoneCounting);
    channel.invokeMethod('onFindResultReceived', obj);
  }

  public async onLongPressHitTestResult(hitTestResult: HitTestResult): Promise<void> {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return
    let nativeHitResult: HitTestResult | null =
      HitTestResult.fromWebViewHitTestResult(this.webView!.getHitTestResult());
    if (nativeHitResult != null) {
      // If native extra is null, try context menu data stored in onContextMenuShow
      if (nativeHitResult.getExtra() == null && this.webView instanceof InAppWebView) {
        let cmExtra: string | null = this.webView!.lastContextMenuLinkUrl;
        if (cmExtra == null) {
          cmExtra = this.webView!.lastContextMenuSourceUrl;
        }
        if (cmExtra != null) {
          nativeHitResult.setExtra(cmExtra);
        }
      }
      // If native type is Unknown, try cached type from onContextMenuShow.
      // Repeated long-press invocations may cause getHitTestValue() to return
      // Unknown even during a valid context menu callback; the first call in
      // onContextMenuShow caches the correct type.
      if (nativeHitResult.getType() === HitTestResult.unknownType &&
      this.webView instanceof InAppWebView) {
        let cachedType: number =
          HitTestResult.getFlutterHitTestResultType(this.webView!.lastContextMenuHitTestType);
        nativeHitResult.setType(cachedType);
      }
      channel.invokeMethod('onLongPressHitTestResult', nativeHitResult.toMap())
      channel.invokeMethod('onCreateContextMenu', nativeHitResult.toMap())
    }
  }

  public onScrollChanged(x: number, y: number): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('x', x);
    obj.set('y', y);
    channel.invokeMethod('onScrollChanged', obj);
  }

  public onDownloadStartRequest(downloadStartRequest: DownloadStartRequest) {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return
    channel.invokeMethod('onDownloadStartRequest', downloadStartRequest.toMap())
  }

  public onCreateContextMenu(hitTestResult: HitTestResult) {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return
    channel.invokeMethod('onCreateContextMenu', hitTestResult.toMap())
  }

  public onOverScrolled(scrollX: number, scrollY: number, clampedX: boolean, clampedY: boolean): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('x', scrollX);
    obj.set('y', scrollY);
    obj.set('clampedX', clampedX);
    obj.set('clampedY', clampedY);
    channel.invokeMethod('onOverScrolled', obj);
  }

  public onContextMenuActionItemClicked(itemId: number, itemTitle: string): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('id', itemId);
    obj.set('androidId', itemId);
    obj.set('iosId', null);
    obj.set('title', itemTitle);
    channel.invokeMethod('onContextMenuActionItemClicked', obj);
  }

  public onHideContextMenu(): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return
    let obj: Map<string, Any> = new Map<string, Any>()
    channel.invokeMethod('onHideContextMenu', obj)
  }

  public onEnterFullscreen(): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return
    let obj: Map<string, Any> = new Map<string, Any>()
    channel.invokeMethod('onEnterFullscreen', obj);
  }

  public onExitFullscreen(): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return
    let obj: Map<string, Any> = new Map<string, Any>()
    channel.invokeMethod('onExitFullscreen', obj);
  }

  public onJsAlert(url: string, message: string, isMainFrame: boolean | null, callback: JsAlertCallback): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    obj.set('message', message);
    obj.set('isMainFrame', isMainFrame);
    channel.invokeMethod('onJsAlert', obj, callback);
  }

  public onJsConfirm(url: string, message: string, isMainFrame: boolean | null, callback: JsConfirmCallback): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    obj.set('message', message);
    obj.set('isMainFrame', isMainFrame);
    channel.invokeMethod('onJsConfirm', obj, callback);
  }

  public onJsPrompt(url: string, message: string, defaultValue: string, isMainFrame: boolean | null, callback: JsPromptCallback): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    obj.set('message', message);
    obj.set('defaultValue', defaultValue);
    obj.set('isMainFrame', isMainFrame);
    channel.invokeMethod('onJsPrompt', obj, callback);
  }

  public onJsBeforeUnload(url: string, message: string, callback: JsBeforeUnloadCallback): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    obj.set('message', message);
    channel.invokeMethod('onJsBeforeUnload', obj, callback);
  }

  public onCreateWindow(createWindowAction: CreateWindowAction, callback: CreateWindowCallback) {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    channel.invokeMethod('onCreateWindow', createWindowAction.toMap(), callback);
  }

  public onCloseWindow(): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    channel.invokeMethod('onCloseWindow', obj);
  }

  public onGeolocationPermissionsShowPrompt(origin: string, callback: GeolocationPermissionsShowPromptCallback): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('origin', origin)
    channel.invokeMethod('onGeolocationPermissionsShowPrompt', obj, callback);
  }

  public onGeolocationPermissionsHidePrompt(): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    channel.invokeMethod('onGeolocationPermissionsHidePrompt', obj);
  }

  public onConsoleMessage(message: string, messageLevel: number): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('message', message);
    obj.set('messageLevel', messageLevel);
    channel.invokeMethod('onConsoleMessage', obj);
  }

  public onProgressChanged(progress: number): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('progress', progress);
    channel.invokeMethod('onProgressChanged', obj);
  }

  public onTitleChanged(title: string): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('title', title);
    channel.invokeMethod('onTitleChanged', obj);
  }

  public onReceivedIcon(icon: ArrayBuffer): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    // MethodChannel on OHOS cannot carry ArrayBuffer; send plain byte list for Dart Uint8List.
    obj.set('icon', Array.from(new Uint8Array(icon)));
    channel.invokeMethod('onReceivedIcon', obj);
  }

  public onReceivedTouchIconUrl(url: string, precomposed: boolean): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    obj.set('precomposed', precomposed);
    channel.invokeMethod('onReceivedTouchIconUrl', obj);
  }

  public onPermissionRequest(origin: string, resources: Array<string>, frame: Object | null, callback: PermissionRequestCallback) {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('origin', origin);
    obj.set('resources', resources);
    obj.set('frame', frame);
    channel.invokeMethod('onPermissionRequest', obj, callback);
  }

  public onPermissionRequestCanceled(origin: string, resources: List<string>): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('origin', origin);
    obj.set('resources', resources);
    channel.invokeMethod('onPermissionRequestCanceled', obj);
  }

  public onLoadStart(url: string) {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    channel.invokeMethod('onLoadStart', obj);
  }

  public onLoadStop(url: string) {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    // Defer delivery so Dart listeners (e.g. broadcast StreamController in tests)
    // can subscribe before the event is emitted on fast/cached OHOS page loads.
    setTimeout(() => {
      if (this.getChannel() == null) {
        return;
      }
      channel.invokeMethod('onLoadStop', obj);
    }, 0);
  }

  public onUpdateVisitedHistory(url: string, isReload: boolean) {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    obj.set('isReload', isReload);
    channel.invokeMethod('onUpdateVisitedHistory', obj);
  }

  public onRequestFocus() {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) {
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    channel.invokeMethod('onRequestFocus', obj);
  }

  public onReceivedError(request: WebResourceRequestExt, error: WebResourceErrorExt): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('request', request.toMap());
    obj.set('error', error.toMap());
    channel.invokeMethod('onReceivedError', obj);
  }

  public onReceivedHttpError(request: WebResourceRequestExt, errorResponse: WebResourceResponseExt): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('request', request.toMap());
    obj.set('errorResponse', errorResponse.toMap());
    channel.invokeMethod('onReceivedHttpError', obj);
  }

  public async onReceivedHttpAuthRequest(challenge: HttpAuthenticationChallenge, callback: ReceivedHttpAuthRequestCallback) {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    channel.invokeMethod('onReceivedHttpAuthRequest', await challenge.toMap(), callback);
  }

  public async onReceivedServerTrustAuthRequest(challenge: ServerTrustChallenge, callback: ReceivedServerTrustAuthRequestCallback) {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    channel.invokeMethod('onReceivedServerTrustAuthRequest', await challenge.toMap(), callback);
  }

  public async onReceivedClientCertRequest(challenge: ClientCertChallenge,
    callback: ReceivedClientCertRequestCallback) {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    channel.invokeMethod('onReceivedClientCertRequest', await challenge.toMap(), callback);
  }

  public onReceivedClientCertRequestBlocking(
    challenge: ClientCertChallenge,
    callback: SyncBaseCallbackResultImpl<ClientCertResponse>
  ): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    channel.invokeMethod('onReceivedClientCertRequest', challenge.toSyncMap(), callback);
    if (!callback.waitResponseWithTimeout(5000)) {
      Log.w(LOG_TAG, 'onReceivedClientCertRequest timed out');
      callback.defaultBehaviour(null);
    }
  }

  shouldInterceptRequest(request: WebResourceRequestExt){
    let channel = this.getChannel();
    if (channel == null) return null;
    let callback = new SyncShouldInterceptRequestCallback();
    channel.invokeMethod('shouldInterceptRequest', request.toMap(), callback);
    if (!callback.waitResponseWithTimeout(5000)) {
      return null;
    }
    return callback.result;
  }

  shouldInterceptRequestAsync(request: WebResourceRequestExt, callback: BaseCallbackResultImpl<WebResourceResponseExt>) {
    let channel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    channel.invokeMethod('shouldInterceptRequest', request.toMap(), callback);
  }

  onLoadResourceWithCustomScheme(request: WebResourceRequestExt): CustomSchemeResponse | null {
    let channel = this.getChannel();
    if (channel == null) {
      return null;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('request', request.toMap());
    let callback = new SyncLoadResourceWithCustomSchemeCallback();
    channel.invokeMethod('onLoadResourceWithCustomScheme', obj, callback);
    if (!callback.waitResponseWithTimeout(5000)) {
      return null;
    }
    return callback.result;
  }

  shouldOverrideUrlLoading(navigationAction: NavigationAction, callback: ShouldOverrideUrlLoadingCallback) {
    let channel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    channel.invokeMethod('shouldOverrideUrlLoading', navigationAction.toMap(), callback);
  }

  onNavigationResponse(navigationResponse: Map<string, Any>, callback: SyncNavigationResponseCallback): void {
    let channel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    channel.invokeMethod('onNavigationResponse', navigationResponse, callback);
  }

  onCallJsHandler(handlerName: string, args: string, callback: CallJsHandlerCallback) {
    let channel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('handlerName', handlerName);
    obj.set('args', args);
    channel.invokeMethod('onCallJsHandler', obj, callback);
  }

  onPrintRequest(url: string, printJobId: string, callback: PrintRequestCallback) {
    let channel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    obj.set('printJobId', printJobId);
    channel.invokeMethod('onPrintRequest', obj, callback);
  }

  onZoomScaleChanged(oldScale: number, newScale: number) {
    let channel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('oldScale', oldScale);
    obj.set('newScale', newScale);
    channel.invokeMethod('onZoomScaleChanged', obj);
  }

  onRenderProcessGone(didCrash: boolean, rendererPriorityAtExit: number) {
    let channel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('didCrash', didCrash);
    obj.set('rendererPriorityAtExit', rendererPriorityAtExit);
    channel.invokeMethod('onRenderProcessGone', obj);
  }

  onPageCommitVisible(url: string) {
    let channel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    channel.invokeMethod('onPageCommitVisible', obj);
  }

  onFormResubmission(url: string, callback: FormResubmissionCallback) {
    let channel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    channel.invokeMethod('onFormResubmission', obj, callback);
  }

  onSafeBrowsingHit(url: string, threatType: ThreatType, callback: SafeBrowsingHitCallback) {
    let channel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    obj.set('threatType', threatType);
    channel.invokeMethod('onSafeBrowsingHit', obj, callback);
  }

  onRenderProcessUnresponsive(url: string, callback: RenderProcessUnresponsiveCallback) {
    let channel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    channel.invokeMethod('onRenderProcessUnresponsive', obj, callback);
  }

  onRenderProcessResponsive(url: string, callback: RenderProcessResponsiveCallback) {
    let channel = this.getChannel();
    if (channel == null) {
      callback.defaultBehaviour(null);
      return;
    }
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('url', url);
    channel.invokeMethod('onRenderProcessResponsive', obj, callback);
  }

  dispose(): void {
    super.dispose();
    this.webView = null;
  }
}

export class JsAlertCallback extends BaseCallbackResultImpl<JsAlertResponse> {
  public decodeResult(obj: Object | null): JsAlertResponse | null {
    return JsAlertResponse.fromMap(obj as Map<string, Any>);
  }
}

export class JsConfirmCallback extends BaseCallbackResultImpl<JsConfirmResponse> {
  public decodeResult(obj: Object | null): JsConfirmResponse | null {
    return JsConfirmResponse.fromMap(obj as Map<string, Any>);
  }
}

export class JsPromptCallback extends BaseCallbackResultImpl<JsPromptResponse> {
  public decodeResult(obj: Object | null): JsPromptResponse | null {
    return JsPromptResponse.fromMap(obj as Map<string, Any>);
  }
}

export class JsBeforeUnloadCallback extends BaseCallbackResultImpl<JsBeforeUnloadResponse> {
  public decodeResult(obj: Object | null): JsBeforeUnloadResponse | null {
    return JsBeforeUnloadResponse.fromMap(obj as Map<string, Any>);
  }
}

export class CreateWindowCallback extends BaseCallbackResultImpl<Boolean> {
  public decodeResult(obj: Object | null): Boolean | null {
    if (obj === true || obj === false) {
      return obj as boolean;
    }
    return null;
  }
}

export class GeolocationPermissionsShowPromptCallback extends BaseCallbackResultImpl<GeolocationPermissionShowPromptResponse> {
  public decodeResult(obj: Object | null): GeolocationPermissionShowPromptResponse | null {
    return GeolocationPermissionShowPromptResponse.fromMap(obj as Map<string, Any>);
  }
}

export class PermissionRequestCallback extends BaseCallbackResultImpl<PermissionResponse> {
  public decodeResult(obj: Object | null): PermissionResponse | null {
    return PermissionResponse.fromMap(obj as Map<string, Any>);
  }
}

export class ReceivedHttpAuthRequestCallback extends BaseCallbackResultImpl<HttpAuthResponse> {
  public decodeResult(obj: Object | null): HttpAuthResponse | null {
    return HttpAuthResponse.fromMap(obj as Map<string, Any>);
  }
}

class ShouldInterceptRequestCallback extends BaseCallbackResultImpl<WebResourceResponseExt> {
  public decodeResult(obj: Object | null): WebResourceResponseExt | null {
    return WebResourceResponseExt.fromMap(obj as Map<string, Any>);
  }
}

export class ShouldInterceptRequestAsyncCallback extends BaseCallbackResultImpl<WebResourceResponseExt> {
  private webResourceResponse: WebResourceResponse;
  private onNullResponse: (() => void) | null;
  private TAG: string = 'ShouldInterceptRequestAsyncCallback';

  constructor(webResourceResponse: WebResourceResponse, onNullResponse: (() => void) | null = null) {
    super();
    this.webResourceResponse = webResourceResponse;
    this.onNullResponse = onNullResponse;
  }

  public decodeResult(obj: Object | null): WebResourceResponseExt | null {
    return WebResourceResponseExt.fromMap(obj as Map<string, Any>);
  }

  public success(obj: Object | null): void {
    let result = this.decodeResult(obj);
    if (result != null) {
      try {
        WebResourceResponseHelper.applyBytesToWebResourceResponse(
          this.webResourceResponse,
          result.getData(),
          result.getContentType() ?? '',
          result.getContentEncoding() ?? ''
        );
        if (result.getStatusCode()) {
          this.webResourceResponse.setResponseCode(result.getStatusCode());
        }
        if (result.getReasonPhrase()) {
          this.webResourceResponse.setReasonMessage(result.getReasonPhrase());
        }
        if (result.getHeaders()) {
          this.webResourceResponse.setResponseHeader(result.getHeaderArray());
        }
      } catch (e) {
        Log.e(this.TAG, 'Error setting response data: ' + e);
      }
      this.webResourceResponse.setResponseIsReady(true);
    } else {
      // Dart 返回了空值 —— 不要进行拦截。
      // 将请求委托给空响应处理器去获取原始资源，
      // 因为我们已经向 Web 组件返回了一个延期的 WebResourceResponse
      if (this.onNullResponse != null) {
        this.onNullResponse!();
      } else {
        this.webResourceResponse.setResponseIsReady(false);
      }
    }
  }

  public error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(this.TAG, 'shouldInterceptRequest error: ' + errorCode + ' ' + errorMessage);
    if (this.onNullResponse != null) {
      this.onNullResponse!();
    } else {
      this.webResourceResponse.setResponseIsReady(false);
    }
  }

  public notImplemented(): void {
    if (this.onNullResponse != null) {
      this.onNullResponse!();
    } else {
      this.webResourceResponse.setResponseIsReady(false);
    }
  }

  public defaultBehaviour(result: WebResourceResponseExt | null): void {
    if (this.onNullResponse != null) {
      this.onNullResponse!();
    } else {
      this.webResourceResponse.setResponseIsReady(false);
    }
  }
}

export class HybridShouldInterceptRequestCallback extends SyncBaseCallbackResultImpl<WebResourceResponseExt> {
  private webResourceResponse: WebResourceResponse;
  private onNullResponse: (() => void) | null;
  private isAsyncMode: boolean = false;
  private TAG: string = 'HybridShouldInterceptRequestCallback';

  constructor(webResourceResponse: WebResourceResponse, onNullResponse: (() => void) | null = null) {
    super();
    this.webResourceResponse = webResourceResponse;
    this.onNullResponse = onNullResponse;
  }

  switchToAsyncMode(): void {
    this.isAsyncMode = true;
  }

  public decodeResult(obj: Object | null): WebResourceResponseExt | null {
    return WebResourceResponseExt.fromMap(obj as Map<string, Any>);
  }

  private handleNullResponse(): void {
    if (this.onNullResponse != null) {
      this.onNullResponse!();
    } else {
      this.webResourceResponse.setResponseIsReady(false);
    }
  }

  private fillResponse(result: WebResourceResponseExt): void {
    try {
      WebResourceResponseHelper.applyBytesToWebResourceResponse(
        this.webResourceResponse,
        result.getData(),
        result.getContentType() ?? '',
        result.getContentEncoding() ?? ''
      );
      if (result.getStatusCode()) {
        this.webResourceResponse.setResponseCode(result.getStatusCode());
      }
      if (result.getReasonPhrase()) {
        this.webResourceResponse.setReasonMessage(result.getReasonPhrase());
      }
      if (result.getHeaders()) {
        this.webResourceResponse.setResponseHeader(result.getHeaderArray());
      }
    } catch (e) {
      Log.e(this.TAG, 'Error setting response data: ' + e);
    }
    this.webResourceResponse.setResponseIsReady(true);
  }

  public success(obj: Object | null): void {
    if (!this.isAsyncMode) {
      super.success(obj);
      return;
    }
    let result = this.decodeResult(obj);
    if (result != null) {
      this.fillResponse(result);
    } else {
      this.handleNullResponse();
    }
  }

  public error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    if (!this.isAsyncMode) {
      super.error(errorCode, errorMessage, errorDetails);
      return;
    }
    Log.e(this.TAG, 'shouldInterceptRequest error: ' + errorCode + ' ' + errorMessage);
    this.handleNullResponse();
  }

  public notImplemented(): void {
    if (!this.isAsyncMode) {
      super.notImplemented();
      return;
    }
    this.handleNullResponse();
  }

  public defaultBehaviour(result: WebResourceResponseExt | null): void {
    if (!this.isAsyncMode) {
      super.defaultBehaviour(result);
      return;
    }
    this.handleNullResponse();
  }
}

export class SchemeShouldInterceptRequestCallback extends BaseCallbackResultImpl<WebResourceResponseExt> {
  private resourceHandler: web_webview.WebResourceHandler;
  private onNullResponse: (() => void) | null;
  private TAG: string = 'SchemeShouldInterceptRequestCallback';

  constructor(resourceHandler: web_webview.WebResourceHandler, onNullResponse: (() => void) | null = null) {
    super();
    this.resourceHandler = resourceHandler;
    this.onNullResponse = onNullResponse;
  }

  public decodeResult(obj: Object | null): WebResourceResponseExt | null {
    return WebResourceResponseExt.fromMap(obj as Map<string, Any>);
  }

  private handleNullResponse(): void {
    if (this.onNullResponse != null) {
      this.onNullResponse!();
    } else {
      WebResourceResponseHelper.failResourceHandler(this.resourceHandler);
    }
  }

  public success(obj: Object | null): void {
    let result = this.decodeResult(obj);
    if (result != null) {
      try {
        WebResourceResponseHelper.applyExtToResourceHandler(this.resourceHandler, result);
      } catch (e) {
        Log.e(this.TAG, 'Error setting scheme handler response: ' + e);
        this.handleNullResponse();
      }
    } else {
      this.handleNullResponse();
    }
  }

  public error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {
    Log.e(this.TAG, 'shouldInterceptRequest error: ' + errorCode + ' ' + errorMessage);
    this.handleNullResponse();
  }

  public notImplemented(): void {
    this.handleNullResponse();
  }

  public defaultBehaviour(result: WebResourceResponseExt | null): void {
    this.handleNullResponse();
  }
}

class SyncShouldInterceptRequestCallback extends SyncBaseCallbackResultImpl<WebResourceResponseExt> {
  public decodeResult(obj: Object | null): WebResourceResponseExt | null {
    return (new ShouldInterceptRequestCallback()).decodeResult(obj);
  }
}

class LoadResourceWithCustomSchemeCallback extends BaseCallbackResultImpl<CustomSchemeResponse> {
  public decodeResult(obj: Object | null): CustomSchemeResponse | null {
    return CustomSchemeResponse.fromMap(obj as Map<string, Any>);
  }
}

class SyncLoadResourceWithCustomSchemeCallback extends SyncBaseCallbackResultImpl<CustomSchemeResponse> {
  public decodeResult(obj: Object | null): CustomSchemeResponse | null {
    return (new LoadResourceWithCustomSchemeCallback()).decodeResult(obj);
  }
}

export class ShouldOverrideUrlLoadingCallback extends BaseCallbackResultImpl<NavigationActionPolicy> {
  public decodeResult(obj: Object | null): NavigationActionPolicy {
    if (!(typeof obj == 'number')) {
      return NavigationActionPolicy.CANCEL;
    }
    return obj;
  }
}

export class SyncNavigationResponseCallback extends SyncBaseCallbackResultImpl<number> {
  public decodeResult(obj: Object | null): number {
    if (typeof obj === 'number') {
      return obj as number;
    }
    return NavigationResponsePolicy.CANCEL;
  }

  nonNullSuccess(result: number): boolean {
    this.result = result;
    return false;
  }

  defaultBehaviour(result: number | null): void {
    this.result = NavigationResponsePolicy.ALLOW;
    super.defaultBehaviour(result);
  }
}

export class CallJsHandlerCallback extends BaseCallbackResultImpl<Object> {
  public decodeResult(obj: Object | null): Object | null {
    return obj;
  }
}

export class PrintRequestCallback extends BaseCallbackResultImpl<boolean> {
  public decodeResult(obj: Object | null): boolean {
    return obj === true;
  }
}

export class ReceivedServerTrustAuthRequestCallback extends BaseCallbackResultImpl<ServerTrustAuthResponse> {
  public decodeResult(obj: Object | null): ServerTrustAuthResponse | null {
    return ServerTrustAuthResponse.fromMap(obj as Map<string, Any>);
  }
}

export class ReceivedClientCertRequestCallback extends BaseCallbackResultImpl<ClientCertResponse> {
  public decodeResult(obj: Object | null): ClientCertResponse | null {
    return ClientCertResponse.fromMap(obj as Map<string, Any>);
  }
}

export class SyncReceivedClientCertRequestCallback extends SyncBaseCallbackResultImpl<ClientCertResponse> {
  public decodeResult(obj: Object | null): ClientCertResponse | null {
    return ClientCertResponse.fromMap(obj as Map<string, Any>);
  }
}

export class FormResubmissionCallback extends BaseCallbackResultImpl<number> {
  decodeResult(obj: Object | null): number | null {
    return typeof obj == 'number' ? obj as number : null;
  }
}

export class SafeBrowsingHitCallback extends BaseCallbackResultImpl<SafeBrowsingResponse> {
  public decodeResult(obj: Object | null): SafeBrowsingResponse | null {
    return SafeBrowsingResponse.fromMap(obj as Map<string, Any>);
  }
}

export class RenderProcessUnresponsiveCallback extends BaseCallbackResultImpl<number> {
  public decodeResult(obj: Object | null): number | null {
    return typeof obj == 'number' ? obj as number : null;
  }
}

export class RenderProcessResponsiveCallback extends BaseCallbackResultImpl<number> {
  public decodeResult(obj: Object | null): number | null {
    return typeof obj == 'number' ? obj as number : null;
  }
}