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

import { Any, MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import ChannelDelegateImpl from '../../types/ChannelDelegateImpl';
import ChannelResultUtil from '../../types/ChannelResultUtil';
import WebMessageCompatExt from '../../types/WebMessageCompatExt';
import InAppWebView from '../in_app_webview/InAppWebView';
import WebMessageListener from './WebMessageListener';

const LOG_TAG = 'WebMessageListenerChannelDelegate'

export default class WebMessageListenerChannelDelegate extends ChannelDelegateImpl {
  private webMessageListener: WebMessageListener | null

  constructor(webMessageListener: WebMessageListener, channel: MethodChannel) {
    super(channel);
    this.webMessageListener = webMessageListener;
  }

  public onMethodCall(call: MethodCall, result: MethodResult) {
    try {
      switch (call.method) {
        case "postMessage":
          if (this.webMessageListener != null && this.webMessageListener.webView instanceof InAppWebView) {
            let message: WebMessageCompatExt | null = null;
            let messageMap: Map<string, Any> | null = call.argument("message") as Map<string, Any>;
            if (messageMap != null) {
              message = WebMessageCompatExt.fromMap(messageMap);
            } else {
              let data: string | ArrayBuffer | number[] | null = call.argument("data");
              let type: number = Number(call.argument("type"));
              if (isNaN(type)) {
                type = 0;
              }
              if (type == 0 && data != null && typeof data !== 'string') {
                type = 1;
              }
              message = new WebMessageCompatExt(data, type, null);
            }
            this.webMessageListener.postMessageForInAppWebView(message, result);
          } else {
            result.success(false);
          }
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      let err: Error = e as Error;
      ChannelResultUtil.reportError(LOG_TAG, call.method, result, err as Object);
    }
  }

  public onPostMessage(message: WebMessageCompatExt, sourceOrigin: string, isMainFrame: boolean): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set("message", message != null ? message.toMap() : null);
    obj.set("sourceOrigin", sourceOrigin);
    obj.set("isMainFrame", isMainFrame);
    channel.invokeMethod("onPostMessage", obj);
  }

  public dispose(): void {
    super.dispose();
    this.webMessageListener = null;
  }
}