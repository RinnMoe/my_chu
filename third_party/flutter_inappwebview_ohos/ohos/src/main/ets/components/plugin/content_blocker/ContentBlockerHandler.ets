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
import uri from '@ohos.uri';
import http from '@ohos.net.http';
import { ArrayList } from '@kit.ArkTS';
import ContentBlocker from './ContentBlocker';
import ContentBlockerTrigger from './ContentBlockerTrigger';
import ContentBlockerAction from './ContentBlockerAction';
import InAppWebView from '../webview/in_app_webview/InAppWebView';
import WebResourceRequestExt from '../types/WebResourceRequestExt';
import { ContentBlockerTriggerResourceType } from './ContentBlockerTriggerResourceType';
import { ContentBlockerActionType } from './ContentBlockerActionType';
import ContentBlockerHttpUtil from './ContentBlockerHttpUtil';
import JavaScriptBridgeJS from '../plugin_scripts_js/JavaScriptBridgeJS';
import WebResourceResponseHelper from '../types/WebResourceResponseHelper';

const TAG = "ContentBlockerHandler";

export default class ContentBlockerHandler {
  protected ruleList = new ArrayList<ContentBlocker>();

  constructor(ruleList?: ArrayList<ContentBlocker>) {
    if (ruleList) {
      this.ruleList = ruleList;
    }
  }

  getRuleList(): ArrayList<ContentBlocker> {
    return this.ruleList;
  }

  setRuleList(newRuleList: ArrayList<ContentBlocker>) {
    this.ruleList = newRuleList;
  }

  checkUrl(webView: InAppWebView, request: WebResourceRequestExt, contentType?: string): WebResourceResponse | null {
    let responseResourceType = contentType != null && contentType.length > 0
      ? this.getResourceTypeFromContentType(contentType)
      : this.getResourceTypeFromUrl(request);
    return this.checkUrlWithResourceType(webView, request, responseResourceType);
  }

  getResourceTypeFromUrl(request: WebResourceRequestExt): ContentBlockerTriggerResourceType {
    let url: string = request.getUrl();
    // 所有 URL 先按路径扩展名推断（本地 rawfile / file:// 的 .png 依赖此逻辑）
    let fromExtension: ContentBlockerTriggerResourceType = this.getResourceTypeFromUrlExtension(url);
    if (fromExtension !== ContentBlockerTriggerResourceType.RAW) {
      return fromExtension;
    }
    // http(s) 且无扩展名时，对齐 Android：HEAD Content-Type（异步缓存）
    if (url.startsWith('http://') || url.startsWith('https://')) {
      let cachedContentType: string = ContentBlockerHttpUtil.getCachedContentType(url);
      if (cachedContentType.length > 0) {
        return this.getResourceTypeFromContentType(cachedContentType);
      }
      ContentBlockerHttpUtil.scheduleHeadCacheUpdate(url, request.getHeaders());
    }
    return ContentBlockerTriggerResourceType.RAW;
  }

  private getResourceTypeFromUrlExtension(url: string): ContentBlockerTriggerResourceType {
    let path: string = url.toLowerCase();
    try {
      path = new uri.URI(url).path.toLowerCase();
    } catch (e) {
      let pathStart = url.indexOf('://');
      if (pathStart >= 0) {
        path = url.substring(pathStart + 3);
        let slash = path.indexOf('/');
        if (slash >= 0) {
          path = path.substring(slash);
        }
      }
    }

    let queryIndex = path.indexOf('?');
    if (queryIndex >= 0) {
      path = path.substring(0, queryIndex);
    }

    if (path.endsWith('.css')) {
      return ContentBlockerTriggerResourceType.STYLE_SHEET;
    }
    if (path.endsWith('.svg')) {
      return ContentBlockerTriggerResourceType.SVG_DOCUMENT;
    }
    if (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg') ||
      path.endsWith('.gif') || path.endsWith('.webp') || path.endsWith('.ico') ||
      path.endsWith('.bmp') || path.endsWith('.avif')) {
      return ContentBlockerTriggerResourceType.IMAGE;
    }
    if (path.endsWith('.js') || path.endsWith('.mjs')) {
      return ContentBlockerTriggerResourceType.SCRIPT;
    }
    if (path.endsWith('.woff') || path.endsWith('.woff2') || path.endsWith('.ttf') ||
      path.endsWith('.otf') || path.endsWith('.eot')) {
      return ContentBlockerTriggerResourceType.FONT;
    }
    if (path.endsWith('.html') || path.endsWith('.htm')) {
      return ContentBlockerTriggerResourceType.DOCUMENT;
    }
    if (path.endsWith('.mp4') || path.endsWith('.webm') || path.endsWith('.mp3') ||
      path.endsWith('.ogg') || path.endsWith('.wav')) {
      return ContentBlockerTriggerResourceType.MEDIA;
    }

    return ContentBlockerTriggerResourceType.RAW;
  }

  private parseUriPort(portStr: string): number {
    if (portStr == null || portStr.length === 0) {
      return -1;
    }
    let parsed: number = Number.parseInt(portStr);
    if (Number.isNaN(parsed)) {
      return -1;
    }
    return parsed;
  }

  private copyResourceTypes(source: ContentBlockerTriggerResourceType[]): ContentBlockerTriggerResourceType[] {
    let copy: ContentBlockerTriggerResourceType[] = [];
    for (let i = 0; i < source.length; i++) {
      copy.push(source[i]);
    }
    return copy;
  }

  private resourceTypeListIncludes(
    list: ContentBlockerTriggerResourceType[],
    type: ContentBlockerTriggerResourceType
  ): boolean {
    for (let i = 0; i < list.length; i++) {
      if (list[i] === type) {
        return true;
      }
    }
    return false;
  }

  checkUrlWithResourceType(
    webView: InAppWebView,
    request: WebResourceRequestExt,
    responseResourceType: ContentBlockerTriggerResourceType
  ): WebResourceResponse | null {
    if (this.ruleList.length === 0) {
      return null;
    }

    let url: string = request.getUrl();
    let host: string = '';
    let port: number = -1;
    let scheme: string = '';

    try {
      let parsedUri = new uri.URI(url);
      host = parsedUri.host;
      port = this.parseUriPort(parsedUri.port);
      scheme = parsedUri.scheme;
    } catch (e) {
      try {
        let urlSplit: string[] = url.split(":");
        scheme = urlSplit[0];
        let tempUrl: string = url.replace(scheme, "https");
        let parsedUri = new uri.URI(tempUrl);
        host = parsedUri.host;
        port = this.parseUriPort(parsedUri.port);
        scheme = urlSplit[0];
      } catch (err) {
        Log.e(TAG, "Failed to parse URL: " + url);
        return null;
      }
    }

    let rules: ContentBlocker[] = this.ruleList.convertToArray();
    for (let i = 0; i < rules.length; i++) {
      let contentBlocker: ContentBlocker = rules[i];
      let trigger: ContentBlockerTrigger = contentBlocker.getTrigger();
      let resourceTypes: ContentBlockerTriggerResourceType[] = this.copyResourceTypes(trigger.getResourceType());
      if (this.resourceTypeListIncludes(resourceTypes, ContentBlockerTriggerResourceType.IMAGE) &&
        !this.resourceTypeListIncludes(resourceTypes, ContentBlockerTriggerResourceType.SVG_DOCUMENT)) {
        resourceTypes.push(ContentBlockerTriggerResourceType.SVG_DOCUMENT);
      }

      let action: ContentBlockerAction = contentBlocker.getAction();
      if (!trigger.getUrlFilterPatternCompiled().test(url)) {
        continue;
      }

      if (resourceTypes.length > 0 &&
        !this.resourceTypeListIncludes(resourceTypes, responseResourceType)) {
        continue;
      }

      let ifDomains: string[] = trigger.getIfDomain();
      if (ifDomains.length > 0) {
        let matchFound = false;
        for (let d = 0; d < ifDomains.length; d++) {
          let domain: string = ifDomains[d];
          if ((domain.startsWith("*") && host.endsWith(domain.replace("*", ""))) || domain === host) {
            matchFound = true;
            break;
          }
        }
        if (!matchFound) {
          continue;
        }
      }

      let unlessDomains: string[] = trigger.getUnlessDomain();
      if (unlessDomains.length > 0) {
        let unlessDomainMatched = false;
        for (let d = 0; d < unlessDomains.length; d++) {
          let domain: string = unlessDomains[d];
          if ((domain.startsWith("*") && host.endsWith(domain.replace("*", ""))) || domain === host) {
            unlessDomainMatched = true;
            break;
          }
        }
        if (unlessDomainMatched) {
          continue;
        }
      }

      let webViewUrl: string | null = null;
      if (trigger.getLoadType().length > 0 || trigger.getIfTopUrl().length > 0 ||
        trigger.getUnlessTopUrl().length > 0) {
        webViewUrl = webView.getUrl();
      }

      if (webViewUrl != null && webViewUrl.length > 0) {
        if (trigger.getLoadType().length > 0) {
          try {
            let cUri = new uri.URI(webViewUrl);
            let cHost: string = cUri.host;
            let cPort: number = this.parseUriPort(cUri.port);
            let cScheme: string = cUri.scheme;

            if ((trigger.getLoadType().includes("first-party") && cHost.length > 0 &&
              !(cScheme === scheme && cHost === host && cPort === port)) ||
              (trigger.getLoadType().includes("third-party") && cHost.length > 0 && cHost === host)) {
              continue;
            }
          } catch (e) {
            Log.e(TAG, "Failed to parse top URL: " + webViewUrl);
          }
        }

        let ifTopUrls: string[] = trigger.getIfTopUrl();
        if (ifTopUrls.length > 0) {
          let matchFound = false;
          for (let t = 0; t < ifTopUrls.length; t++) {
            let topUrl: string = ifTopUrls[t];
            if (webViewUrl.startsWith(topUrl)) {
              matchFound = true;
              break;
            }
          }
          if (!matchFound) {
            continue;
          }
        }

        let unlessTopUrls: string[] = trigger.getUnlessTopUrl();
        if (unlessTopUrls.length > 0) {
          let unlessTopUrlMatched = false;
          for (let t = 0; t < unlessTopUrls.length; t++) {
            let topUrl: string = unlessTopUrls[t];
            if (webViewUrl.startsWith(topUrl)) {
              unlessTopUrlMatched = true;
              break;
            }
          }
          if (unlessTopUrlMatched) {
            continue;
          }
        }
      }

      switch (action.getType()) {
        case ContentBlockerActionType.BLOCK:
          Log.d(TAG, "BLOCK matched: " + url);
          return this.createBlockedResponse();

        case ContentBlockerActionType.CSS_DISPLAY_NONE:
          this.applyCssDisplayNone(webView, action.getSelector(), 800);
          break;

        case ContentBlockerActionType.MAKE_HTTPS:
          if (scheme === "http" && (port === -1 || port === 80)) {
            Log.d(TAG, "MAKE_HTTPS matched: " + url);
            return this.createMakeHttpsResponse(url, request);
          }
          break;
      }
    }

    return null;
  }

  private createBlockedResponse(): WebResourceResponse {
    let response = new WebResourceResponse();
    response.setResponseMimeType('');
    response.setResponseEncoding('');
    response.setResponseData(new ArrayBuffer(0));
    response.setResponseIsReady(true);
    return response;
  }

  applyCssDisplayNoneRulesOnPageLoad(webView: InAppWebView): void {
    if (this.ruleList.length === 0) {
      return;
    }
    let rules: ContentBlocker[] = this.ruleList.convertToArray();
    for (let i = 0; i < rules.length; i++) {
      let action: ContentBlockerAction = rules[i].getAction();
      if (action.getType() === ContentBlockerActionType.CSS_DISPLAY_NONE) {
        this.applyCssDisplayNone(webView, action.getSelector(), 100);
      }
    }
  }

  private applyCssDisplayNone(webView: InAppWebView, selector: string | null, delayMs: number = 800): void {
    if (selector == null || selector.length === 0) {
      return;
    }
    let escapedSelector: string = selector.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
    let jsScript: string = "(function(d) { " +
      "   function hide () { " +
      "       if (d.body != null && !d.getElementById('" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "-css-display-none-style')) { " +
      "           var c = d.createElement('style'); " +
      "           c.id = '" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "-css-display-none-style'; " +
      "           c.innerHTML = '" + escapedSelector + " { display: none !important; }'; " +
      "           d.body.appendChild(c); " +
      "       }" +
      "       d.querySelectorAll('" + escapedSelector + "').forEach(function (item, index) { " +
      "           item.setAttribute('style', 'display: none !important;'); " +
      "       }); " +
      "   }; " +
      "   hide(); " +
      "   d.addEventListener('DOMContentLoaded', function(event) { hide(); }); " +
      "})(document);";

    setTimeout(() => {
      try {
        webView.getController().runJavaScript(jsScript);
      } catch (e) {
        Log.e(TAG, "applyCssDisplayNone failed: " + e);
      }
    }, delayMs);
  }

  /**
   * MAKE_HTTPS: fetch the https URL and return its body (same as Android WebView).
   * 302 Location does not reliably upgrade image sub-resources on ArkWeb.
   */
  private createMakeHttpsResponse(url: string, request: WebResourceRequestExt): WebResourceResponse {
    let urlHttps: string = url.replace("http://", "https://");
    let response = new WebResourceResponse();
    response.setResponseIsReady(false);
    Log.d(TAG, "MAKE_HTTPS fetch: " + url + " -> " + urlHttps);

    let httpRequest: http.HttpRequest | null = null;
    try {
      httpRequest = http.createHttp();
      let headerObj: Record<string, string> =
        ContentBlockerHttpUtil.buildHeaderRecord(request.getHeaders());
      let httpMethod: http.RequestMethod =
        ContentBlockerHttpUtil.resolveRequestMethod(request.getMethod());

      httpRequest.request(urlHttps, {
        method: httpMethod,
        header: headerObj,
        connectTimeout: 15000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      }).then((resp: http.HttpResponse) => {
        try {
          WebResourceResponseHelper.applyHttpResponseToWebResourceResponse(response, resp);
          if (resp.responseCode >= 400) {
            response.setReasonMessage('Error');
          }
          let contentType = '';
          if (resp.header) {
            let headers = resp.header as Record<string, string>;
            contentType = headers['content-type'] || headers['Content-Type'] || '';
          }
          if (contentType.length === 0) {
            response.setResponseMimeType(this.guessMimeTypeFromUrl(urlHttps));
          }
          Log.d(TAG, "MAKE_HTTPS fetch ok: " + urlHttps + " code=" + resp.responseCode);
        } catch (e) {
          Log.e(TAG, "MAKE_HTTPS fetch set response failed: " + e);
          response.setResponseCode(502);
          response.setResponseData(new ArrayBuffer(0));
        }
        response.setResponseIsReady(true);
        httpRequest!.destroy();
      }).catch((err: Error) => {
        Log.e(TAG, "MAKE_HTTPS fetch failed: " + (err ? err.message : 'unknown') + " url=" + urlHttps);
        response.setResponseCode(502);
        response.setResponseData(new ArrayBuffer(0));
        response.setResponseIsReady(true);
        httpRequest!.destroy();
      });
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, "MAKE_HTTPS fetch start failed: " + err);
      if (httpRequest != null) {
        try {
          httpRequest.destroy();
        } catch (destroyErr) {
          let destroyError: Error = destroyErr as Error;
          Log.e(TAG, "MAKE_HTTPS httpRequest.destroy failed: " + destroyError);
        }
      }
      response.setResponseCode(502);
      response.setResponseData(new ArrayBuffer(0));
      response.setResponseIsReady(true);
    }

    return response;
  }

  private guessMimeTypeFromUrl(url: string): string {
    let path = url.toLowerCase();
    let queryIndex = path.indexOf('?');
    if (queryIndex >= 0) {
      path = path.substring(0, queryIndex);
    }
    if (path.endsWith('.png')) {
      return 'image/png';
    }
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (path.endsWith('.gif')) {
      return 'image/gif';
    }
    if (path.endsWith('.webp')) {
      return 'image/webp';
    }
    if (path.endsWith('.ico')) {
      return 'image/x-icon';
    }
    if (path.endsWith('.svg')) {
      return 'image/svg+xml';
    }
    if (path.endsWith('.css')) {
      return 'text/css';
    }
    if (path.endsWith('.js')) {
      return 'application/javascript';
    }
    return 'application/octet-stream';
  }

  getResourceTypeFromContentType(contentType: string): ContentBlockerTriggerResourceType {
    let responseResourceType = ContentBlockerTriggerResourceType.RAW;
    if (contentType === "text/css") {
      responseResourceType = ContentBlockerTriggerResourceType.STYLE_SHEET;
    } else if (contentType === "image/svg+xml") {
      responseResourceType = ContentBlockerTriggerResourceType.SVG_DOCUMENT;
    } else if (contentType.startsWith("image/")) {
      responseResourceType = ContentBlockerTriggerResourceType.IMAGE;
    } else if (contentType.startsWith("font/")) {
      responseResourceType = ContentBlockerTriggerResourceType.FONT;
    } else if (contentType.startsWith("audio/") || contentType.startsWith("video/") ||
      contentType === "application/ogg") {
      responseResourceType = ContentBlockerTriggerResourceType.MEDIA;
    } else if (contentType.endsWith("javascript")) {
      responseResourceType = ContentBlockerTriggerResourceType.SCRIPT;
    } else if (contentType.startsWith("text/")) {
      responseResourceType = ContentBlockerTriggerResourceType.DOCUMENT;
    }
    return responseResourceType;
  }
}
