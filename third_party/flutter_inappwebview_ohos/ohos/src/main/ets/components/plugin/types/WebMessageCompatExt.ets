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

import WebMessagePortCompatExt from './WebMessagePortCompatExt'
import { List } from '@kit.ArkTS'
import { Any } from '@ohos/flutter_ohos'
import web_webview from '@ohos.web.webview';

const DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER = 1;

export default class WebMessageCompatExt {
  private data: string | ArrayBuffer | number[] | null

  private type: number

  private ports: List<WebMessagePortCompatExt> | null

  constructor(data: string | ArrayBuffer | number[] | null, type: number, ports: List<WebMessagePortCompatExt> | null) {
    this.data = data;
    this.type = type;
    this.ports = ports;
  }

  public static fromMapWebMessageCompat(message: web_webview.WebMessageExt): WebMessageCompatExt {
    let data: string | ArrayBuffer | number[] | null
    if(message.getType() == web_webview.WebMessageType.ARRAY_BUFFER) {
      data = message.getArrayBuffer()
    } else {
      data = message.getString()
    }
    return new WebMessageCompatExt(data, message.getType(), null);
  }

  public static fromMap(map: Map<string, Any> | null): WebMessageCompatExt | null {
    if (map == null) {
      return null;
    }
    let data: string | ArrayBuffer | number[] | null = map.get("data")
    let type: number = Number(map.get("type"))
    if (isNaN(type)) {
      type = 0;
    }
    // MethodChannel may drop nested "type" for byte payloads; infer from data shape.
    if (type == 0 && data != null && typeof data !== 'string') {
      type = DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER;
    }
    let portMapList: List<Map<string, Any>> = map.get("ports") as List<Map<string, Any>>
    let ports: List<WebMessagePortCompatExt> | null = null;
    if (portMapList != null && !portMapList.isEmpty()) {
      ports = new List<WebMessagePortCompatExt>();
      for (let i = 0; i < portMapList.length; i++) {
        ports.add(WebMessagePortCompatExt.fromMap(portMapList[i]));
      }
    }
    return new WebMessageCompatExt(data, type, ports);
  }

  public toMap(): Map<string, Any> {
    let proxyRuleMap: Map<string, Any> = new Map<string, Any>()
    let serializedData: string | number[] | null = null;
    // MethodChannel cannot carry ArrayBuffer; use byte list for Dart Uint8List.
    if (this.type == DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER) {
      serializedData = this.getByteArray();
    } else if (typeof this.data === 'string') {
      serializedData = this.data;
    } else if (Array.isArray(this.data)) {
      serializedData = this.data as number[];
    }
    proxyRuleMap.set("data", serializedData);
    proxyRuleMap.set("type", this.type);
    return proxyRuleMap;
  }

  /** JSON literal embedded in evaluateJavascript for WebMessageListener replies. */
  public toJsPayloadLiteral(): string {
    if (this.type == DART_WEB_MESSAGE_TYPE_ARRAY_BUFFER || this.isBytePayload()) {
      let bytes: number[] = this.getByteArray();
      let str: string = '';
      for (let i = 0; i < bytes.length; i++) {
        str += String.fromCharCode(bytes[i]);
      }
      // OHOS WebView does not reliably deliver synthetic MessageEvent ArrayBuffer
      // payloads from evaluateJavascript; use a binary-safe string instead.
      return JSON.stringify(str);
    }
    return JSON.stringify(this.data != null ? this.data.toString() : null);
  }

  private isBytePayload(): boolean {
    if (this.data == null || typeof this.data === 'string') {
      return false;
    }
    if (this.data instanceof ArrayBuffer || Array.isArray(this.data)) {
      return true;
    }
    try {
      (this.data as List<number>).convertToArray();
      return true;
    } catch (e) {
      return false;
    }
  }

  private getByteArray(): number[] {
    if (this.data instanceof ArrayBuffer) {
      return Array.from(new Uint8Array(this.data as ArrayBuffer));
    }
    if (Array.isArray(this.data)) {
      return this.data as number[];
    }
    if (this.data != null && typeof this.data !== 'string') {
      try {
        return (this.data as List<number>).convertToArray();
      } catch (e) {
      }
    }
    return [];
  }

  public getData(): string | ArrayBuffer | number[] | null {
    return this.data;
  }

  public setData(data: string | ArrayBuffer | number[] | null): void {
    this.data = data;
  }

  public getType(): number {
    return this.type;
  }

  public setType(type: number): void {
    this.type = type;
  }

  public getPorts(): List<WebMessagePortCompatExt> {
    return this.ports!;
  }

  public setPorts(ports: List<WebMessagePortCompatExt>): void {
    this.ports = ports;
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;

    let that: WebMessageCompatExt = o as WebMessageCompatExt;

    if (this.type != that.type) return false;
    // if (!this.Objects.equals(this.data, that.data)) return false;
    // return Objects.equals(ports, that.ports);
    return true
  }

  public toString(): string {
    return "WebMessageCompatExt{" +
      "data=" + this.data +
      ", type=" + this.type +
      ", ports=" + this.ports +
      '}';
  }
}