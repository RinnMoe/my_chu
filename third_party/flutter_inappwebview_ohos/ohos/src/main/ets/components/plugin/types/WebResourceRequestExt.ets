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

import { Any } from '@ohos/flutter_ohos'
import web_webview from '@ohos.web.webview';

export default class WebResourceRequestExt {
  private url: string
  private headers: Map<string, string>
  private isRedirect: boolean
  private hasGesture: boolean
  private isForMainFrame: boolean
  private method: string

  constructor(url: string, headers: Map<string, string>, isRedirect: boolean, hasGesture: boolean, isForMainFrame: boolean, method: string) {
    this.url = url
    this.headers = headers
    this.isRedirect = isRedirect
    this.hasGesture = hasGesture
    this.isForMainFrame = isForMainFrame
    this.method = method
  }

  public static fromWebResourceRequest(request: WebResourceRequest): WebResourceRequestExt {
    let headers = new Map<string, string>()
    for (let header of request.getRequestHeader()) {
      headers.set(header.headerKey, header.headerValue)
    }
    return new WebResourceRequestExt(request.getRequestUrl(),
      headers,
      request.isRedirect(),
      request.isRequestGesture(),
      request.isMainFrame(),
      request.getRequestMethod()
    );
  }

  public static fromSchemeHandlerRequest(
    request: web_webview.WebSchemeHandlerRequest
  ): WebResourceRequestExt {
    let headers = new Map<string, string>();
    for (let header of request.getHeader()) {
      headers.set(header.headerKey, header.headerValue);
    }
    return new WebResourceRequestExt(
      request.getRequestUrl(),
      headers,
      false,
      request.hasGesture(),
      request.isMainFrame(),
      request.getRequestMethod()
    );
  }

  public toMap(): Map<string, Any> {
    let webResourceRequestMap: Map<string, Any> = new Map<string, Any>();
    webResourceRequestMap.set('url', this.url);
    webResourceRequestMap.set('headers', this.headers);
    webResourceRequestMap.set('isRedirect', this.isRedirect);
    webResourceRequestMap.set('hasGesture', this.hasGesture);
    webResourceRequestMap.set('isForMainFrame', this.isForMainFrame);
    webResourceRequestMap.set('method', this.method);
    return webResourceRequestMap;
  }

  public getUrl(): string {
    return this.url;
  }

  public setUrl(url: string): void {
    this.url = url;
  }

  public getHeaders(): Map<string, string> {
    return this.headers;
  }

  public setHeaders(headers: Map<string, string>): void {
    this.headers = headers;
  }

  public getRedirect(): boolean {
    return this.isRedirect;
  }

  public setRedirect(redirect: boolean): void {
    this.isRedirect = redirect;
  }

  public isHasGesture(): boolean {
    return this.hasGesture;
  }

  public setHasGesture(hasGesture: boolean): void {
    this.hasGesture = hasGesture;
  }

  public getForMainFrame(): boolean {
    return this.isForMainFrame;
  }

  public setForMainFrame(forMainFrame: boolean): void {
    this.isForMainFrame = forMainFrame;
  }

  public getMethod(): string {
    return this.method;
  }

  public setMethod(method: string): void {
    this.method = method;
  }

  public toString(): string {
    return 'WebResourceRequestExt{' +
      'url=' + this.url +
      ', headers=' + this.headers +
      ', isRedirect=' + this.isRedirect +
      ', hasGesture=' + this.hasGesture +
      ', isForMainFrame=' + this.isForMainFrame +
      ', method=\'' + this.method + '\'' +
      '}';
  }
}