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

import { Any, MethodCall, MethodChannel } from '@ohos/flutter_ohos'
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel'
import ChannelDelegateImpl from '../../types/ChannelDelegateImpl'
import ChannelResultUtil from '../../types/ChannelResultUtil'
import WebMessageCompatExt from '../../types/WebMessageCompatExt'
import InAppWebView from '../in_app_webview/InAppWebView'
import { WebMessageChannel } from './WebMessageChannel'

const LOG_TAG = 'WebMessageChannelChannelDelegate'

export class WebMessageChannelChannelDelegate extends ChannelDelegateImpl {
  private webMessageChannel: WebMessageChannel | null = null

  constructor(webMessageChannel: WebMessageChannel, channel: MethodChannel) {
    super(channel)
    this.webMessageChannel = webMessageChannel
  }

  public onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case "setWebMessageCallback":
          if (this.webMessageChannel != null && this.webMessageChannel.webView instanceof InAppWebView) {
            let index: number = call.argument("index") as number;
            let message: WebMessageCompatExt | null = WebMessageCompatExt.fromMap(call.argument("message") as Map<string, Any>);
            this.webMessageChannel.setWebMessageCallbackForInAppWebView(index, message, result);
          } else {
            result.success(false);
          }
          break;
        case "postMessage":
          if (this.webMessageChannel != null && this.webMessageChannel.webView instanceof InAppWebView) {
            let index: number = call.argument("index") as number;
            let message: WebMessageCompatExt | null = WebMessageCompatExt.fromMap(call.argument("message") as Map<string, Any>);
            this.webMessageChannel.postMessageForInAppWebView(index, message!, result);
          } else {
            result.success(false);
          }
          break;
        case "close":
          if (this.webMessageChannel != null && this.webMessageChannel.webView instanceof InAppWebView) {
            let index: number = call.argument("index") as number;
            this.webMessageChannel.closeForInAppWebView(index, result);
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

  public onMessage(index: number, message: WebMessageCompatExt | null): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set("index", index);
    obj.set("message", message != null ? message.toMap() : null);
    channel.invokeMethod("onMessage", obj);
  }

  public dispose(): void {
    super.dispose();
    this.webMessageChannel = null;
  }
}