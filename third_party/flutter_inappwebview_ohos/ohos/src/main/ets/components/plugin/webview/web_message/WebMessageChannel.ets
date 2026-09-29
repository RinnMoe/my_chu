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

import { Any, MethodChannel } from '@ohos/flutter_ohos';
import { Disposable } from '../../types/Disposable';
import WebMessagePort from '../../types/WebMessagePort';
import InAppWebViewInterface from '../InAppWebViewInterface';
import InAppWebView from '../in_app_webview/InAppWebView';
import { WebMessageChannelChannelDelegate } from './WebMessageChannelChannelDelegate';
import { ArrayList, List } from '@kit.ArkTS';
import { ValueCallback } from '../../types/ValueCallback';
import JavaScriptBridgeJS from '../../plugin_scripts_js/JavaScriptBridgeJS';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import WebMessageCompatExt from '../../types/WebMessageCompatExt';
import web_webview from '@ohos.web.webview';
import WebMessagePortCompatExt from '../../types/WebMessagePortCompatExt';

const LOG_TAG = "WebMessageChannel"
const METHOD_CHANNEL_NAME_PREFIX = "com.pichillilorenzo/flutter_inappwebview_web_message_channel_"
// Dart端WebMessageType的nativeValue与鸿蒙WebMessageType枚举值相反，这里用Dart端期望的值
const DART_WEB_MESSAGE_TYPE_STRING = 0
const DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER = 1

/**
 * WebMessageChannel - OHOS原生实现
 *
 * 端口分配（对齐鸿蒙官方文档 createWebMessagePorts 的用法）:
 *   compatPorts[0] (port2) - 传给 JS 端（通过 postWebMessage）
 *   compatPorts[1] (port1) - 留在 Native 端，用于接收JS消息和发送消息到JS
 *
 * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-app-page-data-channel
 */
export class WebMessageChannel implements Disposable {
  public id: string

  public channelDelegate: WebMessageChannelChannelDelegate | null
  private disposed: boolean = false;

  /**
   * compatPorts[0] -> 传给 JS (对应 Dart port2, index=1)
   * compatPorts[1] -> 留在 Native (对应 Dart port1, index=0)
   */
  public compatPorts: web_webview.WebMessagePort[]

  public ports: List<WebMessagePort>

  /**
   * 端口状态追踪（对齐 Android 的 isClosed/isTransferred/isStarted）
   * [port1Closed, port1Transferred, port2Closed, port2Transferred]
   */
  public portState: boolean[] = [false, false, false, false]

  public webView: InAppWebViewInterface | null

  constructor(id: string, webView: InAppWebViewInterface) {
    this.id = id;
    let channel: MethodChannel = new MethodChannel(webView.getPlugin().messenger!, METHOD_CHANNEL_NAME_PREFIX + id)
    this.channelDelegate = new WebMessageChannelChannelDelegate(this, channel)
    if (webView instanceof InAppWebView) {
      this.compatPorts = webView.getController().createWebMessagePorts();
      this.ports = new List<WebMessagePort>()
    } else {
      this.ports = new List<WebMessagePort>()
      this.ports.set(0, new WebMessagePort("port1", this))
      this.ports.set(1, new WebMessagePort("port2", this))
      this.compatPorts = webView.getController().createWebMessagePorts()
    }
    this.webView = webView
    // 初始化端口状态
    this.portState = [false, false, false, false];
  }

  private checkPortState(dartIndex: number): void {
    let closedIdx: number = dartIndex == 0 ? 0 : 2;
    let transferredIdx: number = dartIndex == 0 ? 1 : 3;
    if (this.portState[closedIdx]) {
      throw new Error("Port is already closed");
    }
    if (this.portState[transferredIdx]) {
      throw new Error("Port is already transferred");
    }
  }

  public initJsInstance(webView: InAppWebViewInterface, callback: ValueCallback<WebMessageChannel>) {
    if (webView != null) {
      let webMessageChannel: WebMessageChannel = this;
      webView.evaluateJavascript("(function() {" +
      JavaScriptBridgeJS.WEB_MESSAGE_CHANNELS_VARIABLE_NAME + "['" + webMessageChannel.id + "'] = new MessageChannel();" +
        "})();", null, {
        onReceiveValue(value: string | null): void {
          callback.onReceiveValue(webMessageChannel);
        }
      }
      );
    } else {
      callback.onReceiveValue(this);
    }
  }

  /**
   * Dart port1 (index=0) 对应 Native compatPorts[1]
   * 在 compatPorts[1] 上注册 onMessageEvent，监听 JS 端发来的消息
   */
  public setWebMessageCallbackForInAppWebView(index: number, message: WebMessageCompatExt | null, result: MethodResult): void {
    // index=0 (Dart port1) -> compatPorts[1], index=1 (Dart port2) -> compatPorts[0]
    let nativeIndex: number = index == 0 ? 1 : 0;
    if (this.webView != null && this.compatPorts != null && this.compatPorts.length > nativeIndex) {
      try {
        this.checkPortState(index);
        let webMessagePort: web_webview.WebMessagePort = this.compatPorts[nativeIndex];
        webMessagePort.onMessageEvent((msg: web_webview.WebMessage) => {
          if (this.disposed) {
            return;
          }
          let compatExt: WebMessageCompatExt;
          if (typeof msg === 'string') {
            compatExt = new WebMessageCompatExt(msg, DART_WEB_MESSAGE_TYPE_STRING, null);
          } else {
            compatExt = new WebMessageCompatExt(msg, DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER, null);
          }
          this.onMessage(index, compatExt);
        })
        result.success(true);
      } catch (e) {
        result.error(LOG_TAG, "setWebMessageCallback error: " + (e.message ?? JSON.stringify(e)), null);
      }
    } else {
      result.success(true);
    }
  }

  /**
   * Dart port1 (index=0) 对应 Native compatPorts[1]
   * 在 compatPorts[1] 上调用 postMessageEvent，消息通过配对端口到达 JS 端
   */
  public postMessageForInAppWebView(index: number, message: WebMessageCompatExt, result: MethodResult): void {
    // index=0 (Dart port1) -> compatPorts[1], index=1 (Dart port2) -> compatPorts[0]
    let nativeIndex: number = index == 0 ? 1 : 0;
    if (this.webView != null && this.compatPorts != null && this.compatPorts.length > nativeIndex) {
      try {
        this.checkPortState(index);
        let port: web_webview.WebMessagePort = this.compatPorts[nativeIndex];
        let data: string | ArrayBuffer | number[] | null = message.getData();
        if (data != null && message.getType() == DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER) {
          let buffer: ArrayBuffer;
          if (data instanceof ArrayBuffer) {
            buffer = data as ArrayBuffer;
          } else {
            let bytes = data as Array<number>;
            buffer = new ArrayBuffer(bytes.length);
            let view = new Uint8Array(buffer);
            for (let i = 0; i < bytes.length; i++) {
              view[i] = bytes[i];
            }
          }
          port.postMessageEvent(buffer);
        } else {
          port.postMessageEvent(data != null ? (data as string) : "");
        }
        result.success(true);
      } catch (e) {
        result.error(LOG_TAG, "postMessage error: " + (e.message ?? JSON.stringify(e)), null);
      }
    } else {
      result.success(true);
    }
  }

  /**
   * Dart port 的 close
   * index=0 -> compatPorts[1], index=1 -> compatPorts[0]
   * 对齐 Android: isTransferred 时抛异常
   */
  public closeForInAppWebView(index: number, result: MethodResult): void {
    let nativeIndex: number = index == 0 ? 1 : 0;
    if (this.webView != null && this.compatPorts != null && this.compatPorts.length > nativeIndex) {
      try {
        let transferredIdx: number = index == 0 ? 1 : 3;
        if (this.portState[transferredIdx]) {
          throw new Error("Port is already transferred");
        }
        let port: web_webview.WebMessagePort = this.compatPorts[nativeIndex];
        port.close();
        let closedIdx: number = index == 0 ? 0 : 2;
        this.portState[closedIdx] = true;
        result.success(true);
      } catch (e) {
        result.error(LOG_TAG, "close error: " + (e.message ?? JSON.stringify(e)), null);
      }
    } else {
      result.success(true);
    }
  }

  public onMessage(index: number, message: WebMessageCompatExt | null): void {
    if (this.channelDelegate != null) {
      this.channelDelegate.onMessage(index, message);
    }
  }

  public toMap(): Map<string, Any> {
    let webMessageChannelMap: Map<string, Any> = new Map<string, Any>()
    webMessageChannelMap.set("id", this.id);
    return webMessageChannelMap;
  }

  public dispose(): void {
    this.disposed = true;
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    this.compatPorts.forEach(item => item.close())
    this.compatPorts = []
    this.webView = null;
  }
}