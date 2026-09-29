/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     `http://www.apache.org/licenses/LICENSE-2.0`
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';
import { Any } from '@ohos/flutter_ohos';
import web_webview from '@ohos.web.webview';
import { WebNetErrorList } from '@ohos.web.netErrorList';
import WebResourceResponseExt from './WebResourceResponseExt';

export default class WebResourceResponseHelper {
  private static readonly TRANSFER_ENCODING_HEADERS: string[] = [
    'content-encoding',
    'content-length',
    'transfer-encoding',
  ];

  static extractCharsetFromContentType(contentType: string): string {
    if (contentType.length === 0) {
      return 'utf-8';
    }
    const match = contentType.match(/charset\s*=\s*["']?([^"';\s]+)/i);
    if (match != null && match.length > 1) {
      return match[1].toLowerCase();
    }
    return 'utf-8';
  }

  static extractMimeTypeFromContentType(contentType: string): string {
    if (contentType.length === 0) {
      return '';
    }
    return contentType.split(';')[0].trim();
  }

  /**
   * HTTP Content-Encoding / Content-Transfer-Encoding 值，不是字符集。
   * setResponseEncoding 只接受 charset（如 utf-8、gbk）。
   */
  static isHttpContentEncoding(encoding: string): boolean {
    const lower = encoding.toLowerCase().trim();
    return lower === 'gzip' || lower === 'deflate' || lower === 'br' || lower === 'compress' ||
      lower === 'identity' || lower === '7bit' || lower === '8bit' || lower === 'binary' ||
      lower === 'quoted-printable' || lower === 'base64';
  }

  /**
   * 从 content-type 中提取字符集。
   * contentEncoding 参数保留以备将来使用，但目前不参与字符集解析。
   */
  static resolveCharset(contentType: string, contentEncoding: string): string {
    return WebResourceResponseHelper.extractCharsetFromContentType(contentType);
  }

  static headerValueToString(value: Object | null | undefined): string {
    if (value == null || value === undefined) {
      return '';
    }
    if (typeof value === 'string') {
      return value;
    }
    if (Array.isArray(value)) {
      return value.map((item: Object) => WebResourceResponseHelper.headerValueToString(item)).join(', ');
    }
    return String(value);
  }

  static buildSanitizedResponseHeaders(headers: Record<string, Any>): Array<Header> {
    let headerArray: Array<Header> = [];
    for (let key of Object.keys(headers)) {
      const lowerKey = key.toLowerCase();
      if (WebResourceResponseHelper.TRANSFER_ENCODING_HEADERS.includes(lowerKey)) {
        continue;
      }
      headerArray.push({
        headerKey: key,
        headerValue: WebResourceResponseHelper.headerValueToString(headers[key])
      });
    }
    return headerArray;
  }

  static appendCorsHeaders(headerArray: Array<Header>): Array<Header> {
    let hasAllowOrigin = false;
    for (let header of headerArray) {
      if (header.headerKey.toLowerCase() === 'access-control-allow-origin') {
        hasAllowOrigin = true;
        break;
      }
    }
    if (hasAllowOrigin) {
      return headerArray;
    }
    let corsHeaders: Header[] = [
      { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' },
      { headerKey: 'Access-Control-Allow-Methods', headerValue: 'GET, POST, PUT, DELETE, OPTIONS, PATCH' },
      { headerKey: 'Access-Control-Allow-Headers', headerValue: 'Content-Type, Authorization, X-Requested-With' },
    ];
    return corsHeaders.concat(headerArray);
  }

  static buildCorsPreflightResponse(): WebResourceResponse {
    let response = new WebResourceResponse();
    response.setResponseCode(204);
    response.setResponseIsReady(true);
    response.setResponseHeader(WebResourceResponseHelper.appendCorsHeaders([
      { headerKey: 'Access-Control-Max-Age', headerValue: '86400' },
    ]));
    return response;
  }

  static serveCorsPreflightForSchemeHandler(resourceHandler: web_webview.WebResourceHandler): void {
    let schemeResponse = new web_webview.WebSchemeHandlerResponse();
    schemeResponse.setNetErrorCode(WebNetErrorList.NET_OK);
    schemeResponse.setStatus(204);
    schemeResponse.setStatusText('No Content');
    schemeResponse.setHeaderByName('Access-Control-Allow-Origin', '*', false);
    schemeResponse.setHeaderByName('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PATCH', false);
    schemeResponse.setHeaderByName('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With', false);
    schemeResponse.setHeaderByName('Access-Control-Max-Age', '86400', false);
    resourceHandler.didReceiveResponse(schemeResponse);
    resourceHandler.didFinish();
  }

  /**
   * @ohos.net.http 会自动解压 gzip/deflate 响应体。
   * WebResourceResponse.setResponseEncoding 表示字符集（如 utf-8），不是传输编码（如 gzip）。
   * 若继续透传 content-encoding: gzip，Web 组件可能对已解压内容再次解压，导致中文乱码。
   */
  static applyHttpResponseToWebResourceResponse(
    webResourceResponse: WebResourceResponse,
    resp: http.HttpResponse
  ): void {
    if (resp.result != null) {
      if (resp.result instanceof ArrayBuffer) {
        let data = new Uint8Array(resp.result);
        let contentType = '';
        if (resp.header) {
          let headers = resp.header as Record<string, string>;
          contentType = headers['content-type'] || headers['Content-Type'] || '';
        }
        const lowerCT = contentType.toLowerCase();
        if (lowerCT.includes('text/') || lowerCT.includes('json') ||
          lowerCT.includes('javascript') || lowerCT.includes('xml') ||
          lowerCT.includes('css') || lowerCT.includes('html')) {
          let str = util.TextDecoder.create(
            WebResourceResponseHelper.extractCharsetFromContentType(contentType)
          ).decodeToString(data);
          webResourceResponse.setResponseData(str);
        } else {
          webResourceResponse.setResponseData(resp.result);
        }
      } else if (typeof resp.result === 'string') {
        webResourceResponse.setResponseData(resp.result);
      }
    }
    webResourceResponse.setResponseCode(resp.responseCode);
    if (resp.header) {
      let headers = resp.header as Record<string, string>;
      let contentType = headers['content-type'] || headers['Content-Type'] || '';
      if (contentType.length > 0) {
        webResourceResponse.setResponseMimeType(
          WebResourceResponseHelper.extractMimeTypeFromContentType(contentType)
        );
        webResourceResponse.setResponseEncoding(
          WebResourceResponseHelper.extractCharsetFromContentType(contentType)
        );
      }
      let headerArray = WebResourceResponseHelper.buildSanitizedResponseHeaders(headers);
      webResourceResponse.setResponseHeader(
        WebResourceResponseHelper.appendCorsHeaders(headerArray)
      );
    } else {
      webResourceResponse.setResponseHeader(
        WebResourceResponseHelper.appendCorsHeaders([])
      );
    }
  }

  static applyBytesToWebResourceResponse(
    webResourceResponse: WebResourceResponse,
    data: Uint8Array | null | undefined,
    contentType: string,
    contentEncoding: string
  ): void {
    if (data != null && data.byteLength > 0) {
      const lowerCT = contentType.toLowerCase();
      if (lowerCT.includes('text/') || lowerCT.includes('json') ||
        lowerCT.includes('javascript') || lowerCT.includes('xml') ||
        lowerCT.includes('css') || lowerCT.includes('html')) {
        let charset = WebResourceResponseHelper.resolveCharset(contentType, contentEncoding);
        let str = util.TextDecoder.create(charset).decodeToString(data);
        webResourceResponse.setResponseData(str);
      } else {
        webResourceResponse.setResponseData(
          data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)
        );
      }
    }
    if (contentType.length > 0) {
      webResourceResponse.setResponseMimeType(
        WebResourceResponseHelper.extractMimeTypeFromContentType(contentType)
      );
    }
    webResourceResponse.setResponseEncoding(
      WebResourceResponseHelper.resolveCharset(contentType, contentEncoding)
    );
  }

  static applyExtToResourceHandler(
    resourceHandler: web_webview.WebResourceHandler,
    result: WebResourceResponseExt
  ): void {
    let schemeResponse = new web_webview.WebSchemeHandlerResponse();
    schemeResponse.setNetErrorCode(WebNetErrorList.NET_OK);
    schemeResponse.setStatus(result.getStatusCode() ?? 200);
    if (result.getReasonPhrase()) {
      schemeResponse.setStatusText(result.getReasonPhrase()!);
    }
    const contentType = result.getContentType() ?? '';
    const contentEncoding = result.getContentEncoding() ?? '';
    if (contentType.length > 0) {
      schemeResponse.setMimeType(
        WebResourceResponseHelper.extractMimeTypeFromContentType(contentType)
      );
      schemeResponse.setEncoding(
        WebResourceResponseHelper.resolveCharset(contentType, contentEncoding)
      );
    }
    let headerArray = result.getHeaderArray();
    headerArray = WebResourceResponseHelper.appendCorsHeaders(headerArray);
    for (let header of headerArray) {
      schemeResponse.setHeaderByName(
        header.headerKey,
        WebResourceResponseHelper.headerValueToString(header.headerValue),
        false
      );
    }
    resourceHandler.didReceiveResponse(schemeResponse);

    let data = result.getData();
    if (data != null && data.byteLength > 0) {
      const lowerCT = contentType.toLowerCase();
      if (lowerCT.includes('text/') || lowerCT.includes('json') ||
        lowerCT.includes('javascript') || lowerCT.includes('xml') ||
        lowerCT.includes('css') || lowerCT.includes('html')) {
        let charset = WebResourceResponseHelper.resolveCharset(contentType, contentEncoding);
        let str = util.TextDecoder.create(charset).decodeToString(data);
        let encoded = new util.TextEncoder().encodeInto(str);
        resourceHandler.didReceiveResponseBody(
          encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.byteLength) as ArrayBuffer
        );
      } else {
        resourceHandler.didReceiveResponseBody(
          data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer
        );
      }
    }
    resourceHandler.didFinish();
  }

  static applyHttpResponseToResourceHandler(
    resourceHandler: web_webview.WebResourceHandler,
    resp: http.HttpResponse
  ): void {
    let schemeResponse = new web_webview.WebSchemeHandlerResponse();
    schemeResponse.setNetErrorCode(WebNetErrorList.NET_OK);
    schemeResponse.setStatus(resp.responseCode);
    schemeResponse.setStatusText(resp.responseCode >= 200 && resp.responseCode < 300 ? 'OK' : 'Error');
    let headers: Record<string, Any> = resp.header ? resp.header as Record<string, Any> : {};
    let contentType = WebResourceResponseHelper.headerValueToString(
      headers['content-type'] ?? headers['Content-Type'] ?? 'application/json'
    );
    schemeResponse.setMimeType(
      WebResourceResponseHelper.extractMimeTypeFromContentType(contentType)
    );
    schemeResponse.setEncoding(
      WebResourceResponseHelper.extractCharsetFromContentType(contentType)
    );
    let headerArray = WebResourceResponseHelper.buildSanitizedResponseHeaders(headers);
    headerArray = WebResourceResponseHelper.appendCorsHeaders(headerArray);
    for (let header of headerArray) {
      schemeResponse.setHeaderByName(header.headerKey, header.headerValue, false);
    }
    resourceHandler.didReceiveResponse(schemeResponse);

    if (resp.result != null) {
      if (resp.result instanceof ArrayBuffer) {
        let data = new Uint8Array(resp.result);
        const lowerCT = contentType.toLowerCase();
        if (lowerCT.includes('text/') || lowerCT.includes('json') ||
          lowerCT.includes('javascript') || lowerCT.includes('xml') ||
          lowerCT.includes('css') || lowerCT.includes('html')) {
          let str = util.TextDecoder.create(
            WebResourceResponseHelper.extractCharsetFromContentType(contentType)
          ).decodeToString(data);
          let encoded = new util.TextEncoder().encodeInto(str);
          resourceHandler.didReceiveResponseBody(
            encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.byteLength) as ArrayBuffer
          );
        } else {
          resourceHandler.didReceiveResponseBody(resp.result);
        }
      } else if (typeof resp.result === 'string') {
        let encoded = new util.TextEncoder().encodeInto(resp.result);
        resourceHandler.didReceiveResponseBody(
          encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.byteLength) as ArrayBuffer
        );
      }
    }
    resourceHandler.didFinish();
  }

  static failResourceHandler(resourceHandler: web_webview.WebResourceHandler): void {
    resourceHandler.didFail(WebNetErrorList.ERR_FAILED, true);
  }
}
