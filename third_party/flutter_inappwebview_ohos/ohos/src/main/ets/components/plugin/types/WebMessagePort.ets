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

import JavaScriptBridgeJS from '../plugin_scripts_js/JavaScriptBridgeJS'
import InAppWebViewInterface from '../webview/InAppWebViewInterface'
import { WebMessageChannel } from '../webview/web_message/WebMessageChannel'
import { ValueCallback } from './ValueCallback'
import WebMessage from './WebMessage'
import { ArrayList, List } from '@kit.ArkTS'
import Util from '../Util'

export default class WebMessagePort {
  public name: string

  public webMessageChannel: WebMessageChannel | null

  public isClosed: boolean = false

  public isTransferred: boolean = false

  public isStarted: boolean = false

  constructor(name: string, webMessageChannel: WebMessageChannel | null) {
    this.name = name
    this.webMessageChannel = webMessageChannel
  }

  /// 抛异常，暂未完善
  public setWebMessageCallback(callback: ValueCallback<void>): void{
    if (this.isClosed || this.isTransferred) {
      throw new Error("Port is already closed or transferred");
    }
    this.isStarted = true;
    let webView: InAppWebViewInterface | null = this.webMessageChannel != null && this.webMessageChannel.webView != null ? this.webMessageChannel.webView : null
    if (webView != null) {
      let index: number = this.name?.includes("port1") ? 0 : 1;
      webView.evaluateJavascript("(function() {" +
              "  var webMessageChannel = " + JavaScriptBridgeJS.WEB_MESSAGE_CHANNELS_VARIABLE_NAME + "['" + this.webMessageChannel?.id + "'];" +
              "  if (webMessageChannel != null) {" +
              "      webMessageChannel." + this.name + ".onmessage = function (event) {" +
              "          window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler('onWebMessagePortMessageReceived', {" +
              "              'webMessageChannelId': '" + this.webMessageChannel?.id + "'," +
              "              'index': " + index + "," +
              "              'message': event.data" +
              "          });" +
              "      }" +
              "  }" +
              "})();",
        null,
        {
          onReceiveValue(value: string | null): void {
            if (callback != null) {
              callback.onReceiveValue(null);
            }
          }
        }
      );
    } else {
      if (callback != null) {
        callback.onReceiveValue(null);
      }
    }
  }

  /// 抛异常，暂未完善
  public postMessage(message: WebMessage, callback: ValueCallback<void>): void {
    if (this.isClosed || this.isTransferred) {
      throw new Error("Port is already closed or transferred");
    }
    let webView: InAppWebViewInterface | null = this.webMessageChannel != null && this.webMessageChannel.webView != null ? this.webMessageChannel.webView : null;
    if (webView != null) {
      let portsString: string = "null";
      let ports: List<WebMessagePort> | null = message.ports;
      if (ports != null) {
        let portArrayString: List<string> = new List<string>();
        for (let port of ports) {
          if (port == this) {
            throw new Error("Source port cannot be transferred");
          }
          if (port.isStarted) {
            throw new Error("Port is already started");
          }
          if (port.isClosed || port.isTransferred) {
            throw new Error("Port is already closed or transferred");
          }
          port.isTransferred = true;
          portArrayString.add(JavaScriptBridgeJS.WEB_MESSAGE_CHANNELS_VARIABLE_NAME + "['" + this.webMessageChannel?.id + "']." + port.name);
        }
        /// android.text.TextUtils未找对应的，未完善
        // portsString = "[" + TextUtils.join(", ", portArrayString) + "]";
      }
      let data: string = message.data != null ? Util.replaceAll(message.data, "\'", "\\'") : "null";
      let source: string = "(function() {" +
              "  var webMessageChannel = " + JavaScriptBridgeJS.WEB_MESSAGE_CHANNELS_VARIABLE_NAME + "['" + this.webMessageChannel?.id + "'];" +
              "  if (webMessageChannel != null) {" +
              "      webMessageChannel." + this.name + ".postMessage('" + data + "', " + portsString + ");" +
              "  }" +
              "})();";
      webView.evaluateJavascript(source, null, {
          onReceiveValue(value: string | null): void {
            callback.onReceiveValue(null);
          }
        }
      );
    } else {
      callback.onReceiveValue(null);
    }
    message.dispose();
  }

  public close(callback: ValueCallback<void>): void{
    if (this.isTransferred) {
      // throw new Exception("Port is already transferred");
      console.error("Port is already transferred");
      return
    }
    this.isClosed = true;
    let webView: InAppWebViewInterface | null = this.webMessageChannel != null && this.webMessageChannel.webView != null ? this.webMessageChannel.webView : null;
    if (webView != null) {
      let source: string = "(function() {" +
        "  var webMessageChannel = " + JavaScriptBridgeJS.WEB_MESSAGE_CHANNELS_VARIABLE_NAME + "['" + this.webMessageChannel?.id + "'];" +
        "  if (webMessageChannel != null) {" +
        "      webMessageChannel." + this.name + ".close();" +
        "  }" +
        "})();";
      webView.evaluateJavascript(source, null, {
          onReceiveValue(value: string | null): void {
           callback.onReceiveValue(null);
          }
        }
      );
    } else {
      callback.onReceiveValue(null);
    }
  }

  public dispose(): void {
    this.isClosed = true;
    this.webMessageChannel = null;
  }
}