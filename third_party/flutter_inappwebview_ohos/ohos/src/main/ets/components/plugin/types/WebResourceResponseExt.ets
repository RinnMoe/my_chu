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

import { Any } from '@ohos/flutter_ohos';
import { buffer, util } from '@kit.ArkTS';

export default class WebResourceResponseExt {
  private contentType: string;
  private contentEncoding: string;
  private statusCode: number
  private reasonPhrase: string;
  private headers: Map<string, string>;
  private data: Uint8Array;

  constructor(contentType: string, contentEncoding: string, statusCode: number, reasonPhrase: string, headers: Map<string, string>, data: Uint8Array) {
    this.contentType = contentType;
    this.contentEncoding = contentEncoding;
    this.statusCode = statusCode;
    this.reasonPhrase = reasonPhrase;
    this.headers = headers;
    this.data = data;
  }

  static fromWebResourceResponse(response: WebResourceResponse): WebResourceResponseExt {
    let headers = new Map<string, string>()
    let responseHeaders = response.getResponseHeader();
    if (responseHeaders != null) {
      for (let header of responseHeaders) {
        headers.set(header.headerKey, header.headerValue)
      }
    }
    let data: Uint8Array = new Uint8Array(0);
    let responseData = response.getResponseData();
    if (responseData != null && responseData.length > 0) {
      try {
        data = new Uint8Array(buffer.from(responseData, 'utf-8').buffer);
      } catch (e) {
        console.error(`WebResourceResponseExt.fromWebResourceResponse data error: ${e}`);
      }
    }
    return new WebResourceResponseExt(
      response.getResponseMimeType() ?? '',
      response.getResponseEncoding() ?? 'utf-8',
      response.getResponseCode(),
      response.getReasonMessage() ?? '',
      headers,
      data
    );
  }

  static fromMap(map: Map<string, Any>): WebResourceResponseExt | null {
    if (map == null) {
      return null;
    }
    let contentType: string = map.get("contentType");
    let contentEncoding: string = map.get("contentEncoding");
    let statusCode: number = map.get("statusCode");
    let reasonPhrase: string = map.get("reasonPhrase");
    let headers: Map<string, string> = map.get("headers");
    let data: Uint8Array = map.get("data");
    return new WebResourceResponseExt(contentType, contentEncoding, statusCode, reasonPhrase, headers, data);
  }

  toMap(): Map<string, Object> {
    let webResourceResponseMap: Map<string, Any> = new Map<string, Any>();
    webResourceResponseMap.set("contentType", this.contentType);
    webResourceResponseMap.set("contentEncoding", this.contentEncoding);
    webResourceResponseMap.set("statusCode", this.statusCode);
    webResourceResponseMap.set("reasonPhrase", this.reasonPhrase);
    webResourceResponseMap.set("headers", this.headers);
    webResourceResponseMap.set("data", this.data);
    return webResourceResponseMap;
  }


  getContentType(): string {
    return this.contentType;
  }

  setContentType(contentType: string) {
    this.contentType = contentType;
  }

  getContentEncoding(): string {
    return this.contentEncoding;
  }

  setContentEncoding(contentEncoding: string) {
    this.contentEncoding = contentEncoding;
  }

  getStatusCode(): number {
    return this.statusCode;
  }

  setStatusCode(statusCode: number) {
    this.statusCode = statusCode;
  }

  getReasonPhrase(): string {
    return this.reasonPhrase;
  }

  setReasonPhrase(reasonPhrase: string) {
    this.reasonPhrase = reasonPhrase;
  }

  getHeaders(): Map<string, string> {
    return this.headers;
  }

  setHeaders(headers: Map<string, string>) {
    this.headers = headers;
  }

  getData(): Uint8Array {
    return this.data;
  }

  setData(data: Uint8Array) {
    this.data = data;
  }

  getHeaderArray(): Array<Header> {
    let arrayHeaders = Array<Header>()
    // Dart 侧 WebResourceResponse 未传 headers 时为 null（合法场景），
    // 防御性判空，避免 applyExtToResourceHandler 中 forEach 崩溃。
    if (this.headers != null) {
      this.headers.forEach((value: string, key: string) => {
        arrayHeaders.push({headerKey : key, headerValue: value})
      })
    }
    return arrayHeaders;
  }

  public toString(): string {
    return "WebResourceResponseExt{" +
      "contentType='" + this.contentType + '\'' +
      ", contentEncoding='" + this.contentEncoding + '\'' +
      ", statusCode=" + this.statusCode +
      ", reasonPhrase='" + this.reasonPhrase + '\'' +
      ", headers=" + this.headers +
      ", data=" + this.data.toString() +
      '}';
  }
}