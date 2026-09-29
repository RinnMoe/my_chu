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

import { Any, BinaryMessenger, Log, MethodChannel } from '@ohos/flutter_ohos';
import { Disposable } from '../../types/Disposable';
import InAppWebView from '../in_app_webview/InAppWebView';
import InAppWebViewInterface from '../InAppWebViewInterface';
import WebMessageListenerChannelDelegate from './WebMessageListenerChannelDelegate';
import { List, uri } from '@kit.ArkTS';
import WebMessageCompatExt from '../../types/WebMessageCompatExt';
import Util from '../../Util';
import WebMessageListenerJS from '../../plugin_scripts_js/WebMessageListenerJS';
import PluginScript from '../../types/PluginScript';
import { UserScriptInjectionTime } from '../../types/UserScriptInjectionTime';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';

const LOG_TAG = 'WebMessageListener'
const METHOD_CHANNEL_NAME_PREFIX = 'com.pichillilorenzo/flutter_inappwebview_web_message_listener_'

export default class WebMessageListener implements Disposable {
  public id: string
  public jsObjectName: string
  public allowedOriginRules: Set<string>
  public webView: InAppWebViewInterface | null
  public channelDelegate: WebMessageListenerChannelDelegate | null
  public lastSourceOrigin: string | null = null
  public lastIsMainFrame: boolean = true
  private injectedPluginScript: PluginScript | null = null

  constructor(id: string, webView: InAppWebViewInterface, messenger: BinaryMessenger | null, jsObjectName: string, allowedOriginRules: Set<string>) {
    this.id = id
    this.webView = webView
    this.jsObjectName = jsObjectName
    this.allowedOriginRules = allowedOriginRules
    let channel: MethodChannel = new MethodChannel(messenger!, METHOD_CHANNEL_NAME_PREFIX + this.id + '_' + this.jsObjectName);
    this.channelDelegate = new WebMessageListenerChannelDelegate(this, channel);
  }

  public initJsInstance(): void {
    if (this.webView != null) {
      let jsObjectNameEscaped: string = Util.replaceAll(this.jsObjectName, "\'", "\\'");
      let allowedOriginRulesStringList: List<String> = new List<String>();
      for (let allowedOriginRule of this.allowedOriginRules) {
        if (allowedOriginRule === '*') {
          allowedOriginRulesStringList.add("'*'");
        } else {
          let rule: uri.URI = new uri.URI(allowedOriginRule);
          let host: string = rule.host != null ? "'" + Util.replaceAll(rule.host, "\'", "\\'") + "'" : "null";
          let portLiteral: string = "null";
          if (rule.port != null && rule.port !== "" && rule.port !== "-1") {
            portLiteral = rule.port;
          }
          allowedOriginRulesStringList.add("{scheme: '" + rule.scheme + "', host: " + host + ", port: " + portLiteral + "}");
        }
      }
      let allowedOriginRulesString: string = allowedOriginRulesStringList.convertToArray().join(", ");

      let source: string = "(function() {" +
        "  var allowedOriginRules = [" + allowedOriginRulesString + "];" +
        "  var isPageBlank = window.location.href === 'about:blank';" +
        "  var scheme = !isPageBlank ? window.location.protocol.replace(':', '') : null;" +
        "  var host = !isPageBlank ? window.location.hostname : null;" +
        "  var port = !isPageBlank ? window.location.port : null;" +
        "  var wml = window." + WebMessageListenerJS.WEB_MESSAGE_LISTENER_HELPER_NAME + ";" +
        "  if (wml != null && wml._isOriginAllowed != null && wml._isOriginAllowed(allowedOriginRules, scheme, host, port)) {" +
        "      window['" + jsObjectNameEscaped + "'] = new FlutterInAppWebViewWebMessageListener('" + jsObjectNameEscaped + "');" +
        "  }" +
        "})();";
      this.injectedPluginScript = new PluginScript(
        'WebMessageListener-' + this.jsObjectName,
        source,
        UserScriptInjectionTime.AT_DOCUMENT_START,
        null,
        false,
        null
      );
      this.webView.getUserContentController()?.addPluginScript(this.injectedPluginScript);
      // For pages already loaded, AT_DOCUMENT_START scripts won't execute.
      // Immediately evaluate the JS to inject the listener object.
      if (this.webView instanceof InAppWebView) {
        (this.webView as InAppWebView).evaluateJavascript(source, null, null);
      }
    }
  }

  public static fromMap(webView: InAppWebViewInterface, messenger: BinaryMessenger | null, map: Map<string, Any> | null): WebMessageListener | null {
    if (map == null) {
      return null;
    }
    let id: string = map.get('id') as string;
    let jsObjectName: string = map.get('jsObjectName') as string;
    if (jsObjectName == null) return null
    let allowedOriginRuleList: List<string> = map.get('allowedOriginRules') as List<string>;
    if (allowedOriginRuleList == null) return null
    let allowedOriginRules: Set<string> = new Set<string>(allowedOriginRuleList);
    return new WebMessageListener(id, webView, messenger, jsObjectName, allowedOriginRules);
  }

  public handlePostMessageFromJs(jsObjectName: string, message: WebMessageCompatExt,
    sourceOrigin: string | null, isMainFrame: boolean): void {
    if (this.jsObjectName !== jsObjectName) {
      return;
    }
    this.lastSourceOrigin = sourceOrigin;
    this.lastIsMainFrame = isMainFrame;
    if (this.channelDelegate != null) {
      this.channelDelegate.onPostMessage(message, sourceOrigin ?? '', isMainFrame);
    }
  }

  public postMessageForInAppWebView(message: WebMessageCompatExt | null, result: MethodResult): void {
    if (this.webView == null || !(this.webView instanceof InAppWebView)) {
      result.success(false);
      return;
    }
    let inAppWebView: InAppWebView = this.webView as InAppWebView;
    if (message == null) {
      result.success(true);
      return;
    }
    let jsObjectNameEscaped: string = Util.replaceAll(this.jsObjectName, "\'", "\\'");
    let payload: string = message.toJsPayloadLiteral();
    let source: string =
      '(function() {' +
      '  var listener = window[\'' + jsObjectNameEscaped + '\'];' +
      '  if (listener == null) { return; }' +
      '  var data = ' + payload + ';' +
      '  var event = new MessageEvent(\'message\', { data: data });' +
      '  if (typeof listener.onmessage === \'function\') { listener.onmessage(event); }' +
      '  if (listener.listeners != null) { listener.listeners.forEach(function(cb) { try { cb(event); } catch (e) {} }); }' +
      '})();';
    try {
      inAppWebView.evaluateJavascript(source, null, null);
      result.success(true);
    } catch (error) {
      Log.e(LOG_TAG, 'postMessageForInAppWebView failed: ' + JSON.stringify(error));
      result.error(LOG_TAG, String(error), null);
    }
  }

  public dispose(): void {
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    // Remove injected PluginScript from UserContentController to prevent
    // JS from calling a released native handler.
    if (this.webView != null && this.injectedPluginScript != null) {
      try {
        this.webView.getUserContentController()?.removePluginScript(
          this.injectedPluginScript);
      } catch (e) {
        Log.e(LOG_TAG, 'dispose removePluginScript failed: ' + JSON.stringify(e));
      }
      this.injectedPluginScript = null;
    }
    this.webView = null;
  }
}
