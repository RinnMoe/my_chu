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

import { Log } from '@ohos/flutter_ohos';
import JavaScriptBridgeJS from '../plugin_scripts_js/JavaScriptBridgeJS';
import OnZoomScaleChangedJS from '../plugin_scripts_js/OnZoomScaleChangedJS';
import OnJsBeforeUnloadJS from '../plugin_scripts_js/OnJsBeforeUnloadJS';
import PrintJobSettings from '../print_job/PrintJobSettings';
import InAppWebView from './in_app_webview/InAppWebView';
import Util from '../Util';
import { uri } from '@kit.ArkTS';
import { CallJsHandlerCallback, PrintRequestCallback } from './WebViewChannelDelegate';
import {
  WebMessageListenerPostMessagePayload,
  webMessageCompatFromJsMessage
} from './web_message/WebMessageListenerTypes';
import WebMessageCompatExt from '../types/WebMessageCompatExt';

const LOG_TAG = "JSBridgeInterface";

interface CallAsyncJavaScriptPayload {
  resultUuid: string;
}

interface EvaluateJavaScriptWithContentWorldPayload {
  resultUuid: string;
  value?: Object;
}

interface ZoomScaleChangedJsPayload {
  oldScale: number;
  newScale: number;
}

export default class JavaScriptBridgeInterface {
  private inAppWebView: InAppWebView | null;

  constructor(inAppWebView: InAppWebView) {
    this.inAppWebView = inAppWebView;
  }

  private getWebMessageListenerSourceOrigin(): string | null {
    if (this.inAppWebView == null) {
      return null;
    }
    let url: string | null = this.inAppWebView.getUrl();
    if (url == null || url.length === 0) {
      return null;
    }
    try {
      let parsed: uri.URI = new uri.URI(url);
      let origin: string = parsed.scheme + '://' + parsed.host;
      if (parsed.port != null && parsed.port !== '' && parsed.port !== '-1') {
        origin += ':' + parsed.port;
      }
      return origin;
    } catch (e) {
      return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    }
  }

  _hideContextMenu(): void {
    if (this.inAppWebView == null) {
      return;
    }
    this.inAppWebView.hideContextMenu()
  }

  _callHandler(handlerName: string, callHandlerID: string, args: string): void {
    if (this.inAppWebView == null) {
      return;
    }
    if (handlerName == "__onPopupWindowClose") {
      // Popup opened via about:blank may not be engine-bound (setWebController(null)
      // to avoid renderer stall). Bridge window.close() to onCloseWindow.
      if (this.inAppWebView.channelDelegate != null) {
        this.inAppWebView.channelDelegate.onCloseWindow();
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    }
    if (handlerName == "__windowOpenAboutBlank") {
      // loadData pages may miss document-start hooks; HTML-embedded hook calls
      // the native proxy directly when ArkWeb skips onWindowNew for about:blank.
      if (this.inAppWebView.inAppWebViewClient != null) {
        this.inAppWebView.inAppWebViewClient.synthesizeAboutBlankCreateWindow();
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    }
    if (handlerName == "onPrintRequest") {
      let settings = new PrintJobSettings();
      settings.handledByClient = true;
      let printJobId = this.inAppWebView.printCurrentPage(settings);
      if (printJobId != null && this.inAppWebView != null && this.inAppWebView.channelDelegate != null) {
        this.inAppWebView.channelDelegate.onPrintRequest(this.inAppWebView.getUrl(), printJobId, new InnerPrintRequestCallback(this.inAppWebView, printJobId));
      }
      return;
    } else if (handlerName == "callAsyncJavaScript") {
      try {
        let jsonArray: CallAsyncJavaScriptPayload[] = JSON.parse(args) as CallAsyncJavaScriptPayload[];
        let jsonObject: CallAsyncJavaScriptPayload = jsonArray[0];
        let resultUuid: string = jsonObject.resultUuid;
        if (!resultUuid) {
          Log.e(LOG_TAG, "callAsyncJavaScript: Failed to extract resultUuid from args: " + args);
          return;
        }
        let callAsyncJavaScriptCallback = this.inAppWebView.callAsyncJavaScriptCallbacks.get(resultUuid);
        if (callAsyncJavaScriptCallback != null) {
          callAsyncJavaScriptCallback.onReceiveValue(JSON.stringify(jsonObject));
          this.inAppWebView.callAsyncJavaScriptCallbacks.delete(resultUuid);
        } else {
          Log.w(LOG_TAG, "callAsyncJavaScript: No callback found for resultUuid: " + resultUuid);
        }
      } catch (e) {
        Log.e(LOG_TAG, "callAsyncJavaScript error", e);
      }
      return;
    } else if (handlerName == "evaluateJavaScriptWithContentWorld") {
      try {
        let jsonArray: EvaluateJavaScriptWithContentWorldPayload[] =
          JSON.parse(args) as EvaluateJavaScriptWithContentWorldPayload[];
        let jsonObject: EvaluateJavaScriptWithContentWorldPayload = jsonArray[0];
        let resultUuid: string = jsonObject.resultUuid;
        if (!resultUuid) {
          Log.e(LOG_TAG, "evaluateJavaScriptWithContentWorld: Failed to extract resultUuid from args: " + args);
          return;
        }
        let evaluateJavaScriptCallback = this.inAppWebView.evaluateJavaScriptContentWorldCallbacks.get(resultUuid);
        if (evaluateJavaScriptCallback != null) {
          let value: Object | undefined = jsonObject.value;
          evaluateJavaScriptCallback.onReceiveValue(value != null ? value.toString() : "null");
          this.inAppWebView.evaluateJavaScriptContentWorldCallbacks.delete(resultUuid);
        } else {
          Log.w(LOG_TAG, "evaluateJavaScriptWithContentWorld: No callback found for resultUuid: " + resultUuid);
        }
      } catch (e) {
        Log.e(LOG_TAG, "evaluateJavaScriptWithContentWorld error", e);
      }
      return;
    } else if (handlerName == "onWebMessageListenerPostMessageReceived") {
      try {
        let jsonArray: WebMessageListenerPostMessagePayload[] =
          JSON.parse(args) as WebMessageListenerPostMessagePayload[];
        let payload: WebMessageListenerPostMessagePayload = jsonArray[0];
        let jsObjectName: string = payload.jsObjectName;
        let message: WebMessageCompatExt = webMessageCompatFromJsMessage(payload.message);
        let sourceOrigin: string | null = this.getWebMessageListenerSourceOrigin();
        this.inAppWebView.dispatchWebMessageListenerPostMessage(
          jsObjectName, message, sourceOrigin, true);
      } catch (e) {
        Log.e(LOG_TAG, "onWebMessageListenerPostMessageReceived error", e);
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    } else if (handlerName == OnJsBeforeUnloadJS.HANDLER_NAME) {
      if (this.inAppWebView != null) {
        this.inAppWebView.hasBeforeUnloadHandler = true;
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    } else if (handlerName == OnZoomScaleChangedJS.HANDLER_NAME) {
      try {
        let jsonArray: ZoomScaleChangedJsPayload[] = JSON.parse(args) as ZoomScaleChangedJsPayload[];
        let event: ZoomScaleChangedJsPayload = jsonArray[0];
        let oldScale = Number(event.oldScale);
        let newScale = Number(event.newScale);
        if (!Number.isNaN(oldScale) && !Number.isNaN(newScale)) {
          let normalizedNewScale = newScale / Util.getPixelDensity();
          if (Math.abs(this.inAppWebView.zoomScale - normalizedNewScale) >= 0.01 &&
            this.inAppWebView.channelDelegate != null) {
            this.inAppWebView.zoomScale = normalizedNewScale;
            this.inAppWebView.channelDelegate.onZoomScaleChanged(oldScale, newScale);
          }
        }
      } catch (e) {
        Log.e(LOG_TAG, "", e);
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    }
    if (this.inAppWebView.channelDelegate != null) {
      this.inAppWebView.channelDelegate.onCallJsHandler(handlerName, args, new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID));
    }
  }

  getMethodList(): Array<string> {
    return ["_hideContextMenu", "_callHandler"];
  }

  dispose() {
    this.inAppWebView = null;
  }
}

class InnerPrintRequestCallback extends PrintRequestCallback {
  private inAppWebView: InAppWebView;
  private printJobId: string;

  constructor(inAppWebView: InAppWebView, printJobId: string) {
    super();
    this.inAppWebView = inAppWebView;
    this.printJobId = printJobId;
  }

  nonNullSuccess(handledByClient: boolean): boolean {
    return !handledByClient;
  }

  defaultBehaviour(handledByClient: boolean | null) {
    // Keep the PrintJobController channel alive until Dart calls dispose().
    // Integration tests capture the controller in onPrintRequest and invoke
    // getInfo/cancel/restart even when returning false.
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null) {
    Log.e(LOG_TAG, errorCode + ", " + ((errorMessage != null) ? errorMessage : ""));
    this.defaultBehaviour(null);
  }
}

class InnerCallJsHandlerCallback extends CallJsHandlerCallback {
  private inAppWebView: InAppWebView;
  private _callHandlerID: string;

  constructor(inAppWebView: InAppWebView, _callHandlerID: string) {
    super();
    this.inAppWebView = inAppWebView;
    this._callHandlerID = _callHandlerID;
  }

  defaultBehaviour(json: Object | null) {
    if (this.inAppWebView == null) {
      // The webview has already been disposed, ignore.
      return;
    }
    const handlerIdNum = Number(this._callHandlerID);
    if (isNaN(handlerIdNum)) {
      Log.w(LOG_TAG, "Invalid callHandlerID, expected numeric value: " + this._callHandlerID);
      return;
    }

    const handlerId = JSON.stringify(this._callHandlerID);
    // json 参数已经是 Dart 侧通过 jsonEncode 编码后的 JSON 字符串
    // 不要再调用 JSON.stringify，否则会导致双重序列化
    // 这与 Android 实现一致，直接拼接 json 字符串到 JS 代码
    let jsonPayload: string = (json != null) ? String(json) : 'null';
    let sourceCode = "if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "] != null) { " +
      "window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "].resolve(" + jsonPayload + "); " +
      "delete window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "]; " +
      "}";
    this.inAppWebView.getController().runJavaScriptExt(sourceCode);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null) {
    let message = errorCode + ((errorMessage != null) ? ", " + errorMessage : "");
    Log.e(LOG_TAG, message);

    if (this.inAppWebView == null) {
      // The webview has already been disposed, ignore.
      return;
    }
    const handlerIdNum = Number(this._callHandlerID);
    if (isNaN(handlerIdNum)) {
      Log.w(LOG_TAG, "Invalid callHandlerID, expected numeric value: " + this._callHandlerID);
      return;
    }

    const handlerId = JSON.stringify(this._callHandlerID);
    let sourceCode = "if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "] != null) { " +
      "window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "].reject(new Error(" + JSON.stringify(message) + ")); " +
      "delete window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "]; " +
      "}";
    this.inAppWebView.getController().runJavaScriptExt(sourceCode);
  }
}