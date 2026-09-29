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

import ChannelResultUtil from './types/ChannelResultUtil';
import ChannelDelegateImpl from './types/ChannelDelegateImpl';
import web_webview from '@ohos.web.webview';
import InAppWebViewFlutterPlugin from './InAppWebViewFlutterPlugin';
import { Any, MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import business_error from '@ohos.base'
import Intl from '@ohos.intl';
import { List } from '@kit.ArkTS';
import systemDateTime from '@ohos.systemDateTime';

const LOG_TAG = "MyCookieManager"
const METHOD_CHANNEL_NAME = "com.pichillilorenzo/flutter_inappwebview_cookiemanager"

/**
 * OHOS CookieManager (SEC-006): setCookie validates parameters per RFC 6265 before writing.
 * Android/iOS do not apply the same checks; identical Dart calls may return false on OHOS only.
 * Consider adding shared validation in Dart or on Android/iOS for cross-platform consistency.
 */
export default class MyCookieManager extends ChannelDelegateImpl {
  public plugin: InAppWebViewFlutterPlugin | null

  constructor(plugin: InAppWebViewFlutterPlugin) {
    if (plugin.messenger == null) {
      throw new Error('MyCookieManager: plugin.messenger is null');
    }
    super(new MethodChannel(plugin.messenger, METHOD_CHANNEL_NAME))
    this.plugin = plugin
  }


  public async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      switch (call.method) {
        case "setCookie":
          {
            let url: string = call.argument("url") as string;
            let name: string = call.argument("name") as string;
            let value: string = call.argument("value") as string;
            let domain: string = call.argument("domain") as string;
            let path: string = call.argument("path") as string;
            let expiresDateString: string = call.argument("expiresDate") as string;
            let expiresDate: number | null = (expiresDateString != null ?
  new Number(expiresDateString).valueOf() : null);
            let maxAge: number = call.argument("maxAge") as number;
            let isSecure: boolean = call.argument("isSecure") as boolean;
            let isHttpOnly: boolean = call.argument("isHttpOnly") as boolean;
            let sameSite: string = call.argument("sameSite") as string;
            await this.setCookie(url,
                    name,
                    value,
                    domain,
                    path,
                    expiresDate,
                    maxAge,
                    isSecure,
                    isHttpOnly,
                    sameSite,
                    result);
          }
          break;
        case "getCookies":
          result.success(await this.getCookies(call.argument("url") as string));
          break;
        case "deleteCookie":
          {
            let url: string = call.argument("url") as string;
            let name: string = call.argument("name") as string;
            let domain: string = call.argument("domain") as string;
            let path: string = call.argument("path") as string;
            await this.deleteCookie(url, name, domain, path, result);
          }
          break;
        case "deleteCookies":
          {
            let url: string = call.argument("url") as string;
            let domain: string = call.argument("domain") as string;
            let path: string = call.argument("path") as string;
            await this.deleteCookies(url, domain, path, result);
          }
          break;
        case "deleteAllCookies":
          this.deleteAllCookies(result);
          break;
        case "removeSessionCookies":
          this.removeSessionCookies(result);
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      let err: Error = e as Error;
      ChannelResultUtil.reportError(LOG_TAG, call.method, result, err as Object);
    }
  }

  public async setCookie(url: string, name: string, value: string, domain: string, path: string,
                   expiresDate: number | null, maxAge: number, isSecure: boolean, isHttpOnly: boolean, sameSite: string, result: MethodResult): Promise<void> {

    if (!web_webview.WebCookieManager.isCookieAllowed()) {
      result.success(false);
      return;
    }

    let setCookieFailedChecks: string[] = [];
    if (!MyCookieManager.isValidCookieName(name)) setCookieFailedChecks.push('name');
    if (!MyCookieManager.isValidCookieValue(value)) setCookieFailedChecks.push('value');
    if (!MyCookieManager.isValidCookieDomain(domain)) setCookieFailedChecks.push('domain');
    if (path == null || path.length == 0) {
      path = "/";
    }
    if (!MyCookieManager.isValidCookiePath(path)) setCookieFailedChecks.push('path');
    if (!MyCookieManager.isValidSameSite(sameSite)) setCookieFailedChecks.push('sameSite');
    if (!isSecure && sameSite === "None") setCookieFailedChecks.push('sameSite-secure');
    if (setCookieFailedChecks.length > 0) {
      MyCookieManager.failCookieValidation('setCookie', result, setCookieFailedChecks);
      return;
    }

    try {
      let cookieValue = name + "=" + value + "; Path=" + path;

      if (MyCookieManager.hasCookieDomain(domain)) {
        cookieValue += "; Domain=" + domain;
      }
      if (expiresDate != null) {
        cookieValue += "; Expires=" + this.getCookieExpirationDate(expiresDate);
      }
      if (maxAge != null) {
        cookieValue += "; Max-Age=" + maxAge.toString();
      }
      if (isSecure) {
        cookieValue += "; Secure";
      }
      if (isHttpOnly) {
        cookieValue += "; HttpOnly";
      }
      if (sameSite != null) {
        cookieValue += "; SameSite=" + sameSite;
      }
      // OHOS configCookie resolves void; true means the API call succeeded, not that WebView accepted the cookie.
      await web_webview.WebCookieManager.configCookie(url, cookieValue)
      result.success(true)
    } catch (error) {
      ChannelResultUtil.reportError(LOG_TAG, 'setCookie', result, error as Object);
    }

  }

  public async getCookies(url: string): Promise<List<Map<string, Any>>> {
    let cookieListMap: List<Map<string, Any>> = new List<Map<string, Any>>()

    // fetchCookieSync may throw BusinessError; callers must catch (onMethodCall does).
    let cookiesString: string = web_webview.WebCookieManager.fetchCookieSync(url)
    if (cookiesString == null || cookiesString == "") return cookieListMap

    /// Android中同样只获取了setCookies中“name=value”这一段，因此目前先这样写着
    let cookies: string[] = cookiesString.split(";")

    for (let cookie of cookies) {
      let eqIndex: number = cookie.indexOf("=");
      if (eqIndex < 0) {
        continue;
      }
      let name: string = cookie.substring(0, eqIndex).trim();
      let value: string = cookie.substring(eqIndex + 1).trim();
      let cookieMap: Map<string, Any> = new Map<string, Any>()
      cookieMap.set("name", name);
      cookieMap.set("value", value);
      cookieMap.set("expiresDate", null);
      cookieMap.set("isSessionOnly", null);
      cookieMap.set("domain", null);
      cookieMap.set("sameSite", null);
      cookieMap.set("isSecure", null);
      cookieMap.set("isHttpOnly", null);
      cookieMap.set("path", null);
      cookieListMap.add(cookieMap)
    }

    return cookieListMap
  }

  public async deleteCookie(url: string, name: string, domain: string, path: string, result: MethodResult): Promise<void> {
    if (!web_webview.WebCookieManager.isCookieAllowed()) {
      result.success(false);
      return;
    }
    if (name == null || name.length == 0) {
      console.warn(LOG_TAG, 'deleteCookie: name is null or empty');
      result.success(false);
      return;
    }
    // Unlike setCookie, do not reject non-RFC names: cookies may already exist in the WebView store.
    if (!MyCookieManager.isValidCookieName(name)) {
      console.warn(LOG_TAG, 'deleteCookie: cookie name contains RFC 6265 token characters');
    }
    let deleteCookieFailedChecks: string[] = [];
    if (!MyCookieManager.isValidCookieDomain(domain)) deleteCookieFailedChecks.push('domain');
    if (path == null || path.length == 0) {
      path = "/";
    }
    if (!MyCookieManager.isValidCookiePath(path)) deleteCookieFailedChecks.push('path');
    if (deleteCookieFailedChecks.length > 0) {
      MyCookieManager.failCookieValidation('deleteCookie', result, deleteCookieFailedChecks);
      return;
    }
    try {
      let cookieValue = name + "=; Path=" + path + "; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0";
      if (MyCookieManager.hasCookieDomain(domain))
        cookieValue += "; Domain=" + domain;
      // API 14+ requires includeHttpOnly=true to replace an HttpOnly cookie.
      web_webview.WebCookieManager.configCookieSync(url, cookieValue, false, true);
      await web_webview.WebCookieManager.saveCookieAsync();
      result.success(true)
    } catch (error) {
      ChannelResultUtil.reportError(LOG_TAG, 'deleteCookie', result, error as Object);
    }
  }

  public async deleteCookies(url: string, domain: string, path: string, result: MethodResult): Promise<void> {
    if (!web_webview.WebCookieManager.isCookieAllowed()) {
      result.success(false);
      return;
    }
    let deleteCookiesFailedChecks: string[] = [];
    if (!MyCookieManager.isValidCookieDomain(domain)) deleteCookiesFailedChecks.push('domain');
    if (path == null || path.length == 0) {
      path = "/";
    }
    if (!MyCookieManager.isValidCookiePath(path)) deleteCookiesFailedChecks.push('path');
    if (deleteCookiesFailedChecks.length > 0) {
      MyCookieManager.failCookieValidation('deleteCookies', result, deleteCookiesFailedChecks);
      return;
    }
    try {
      let cookiesString: string = web_webview.WebCookieManager.fetchCookieSync(url)
      if (cookiesString != null) {
        for (let cookiesValue of cookiesString.split(";")) {
          let eqIndex: number = cookiesValue.indexOf("=");
          if (eqIndex < 0) {
            continue;
          }
          let name: string = cookiesValue.substring(0, eqIndex).trim()
          let cookieValue = name + "=; Path=" + path + "; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0";
          if (MyCookieManager.hasCookieDomain(domain))
            cookieValue += "; Domain=" + domain;
          try {
            web_webview.WebCookieManager.configCookieSync(url, cookieValue, false, true)
          } catch (e) {
            console.warn(LOG_TAG, 'deleteCookies: failed to delete a cookie')
          }
        }
      }
      await web_webview.WebCookieManager.saveCookieAsync();
      result.success(true);
    } catch (error) {
      ChannelResultUtil.reportError(LOG_TAG, 'deleteCookies', result, error as Object);
    }
  }

  public deleteAllCookies(result: MethodResult): void {
    if (!web_webview.WebCookieManager.isCookieAllowed()) {
      result.success(false);
      return;
    }

    try {
      web_webview.WebCookieManager.clearAllCookiesSync()
      result.success(true)
    } catch (e) {
      ChannelResultUtil.reportError(LOG_TAG, 'deleteAllCookies', result, e as Object);
    }
  }

  public removeSessionCookies(result: MethodResult): void {
    if (!web_webview.WebCookieManager.isCookieAllowed()) {
      result.success(false);
      return;
    }

    try {
      web_webview.WebCookieManager.clearSessionCookieSync()
      result.success(true)
    } catch (e) {
      ChannelResultUtil.reportError(LOG_TAG, 'removeSessionCookies', result, e as Object);
    }
  }

  /** RFC 6265 cookie-token separator characters (name/domain). */
  private static readonly COOKIE_TOKEN_SEPARATORS: string = '()<>@,;:\\"/[]?={} \t';

  /** Returns true if value contains control chars or cookie-token separators. */
  private static containsInvalidCookieTokenChars(value: string): boolean {
    for (let i = 0; i < value.length; i++) {
      let code = value.charCodeAt(i);
      if (code < 0x20 || code === 0x7F) {
        return true;
      }
      if (MyCookieManager.COOKIE_TOKEN_SEPARATORS.indexOf(value.charAt(i)) >= 0) {
        return true;
      }
    }
    return false;
  }

  /** Validates cookie name per RFC 6265 token rules (setCookie only; delete is lenient). */
  private static isValidCookieName(name: string): boolean {
    return name != null && name.length > 0 && !MyCookieManager.containsInvalidCookieTokenChars(name);
  }

  /** Rejects control chars and ; " \ , ; allows UTF-8 (broader than strict RFC, matches browser/Android). */
  private static isValidCookieValue(value: string): boolean {
    if (value == null) {
      return false;
    }
    for (let i = 0; i < value.length; i++) {
      let code = value.charCodeAt(i);
      if (code < 0x20 || code === 0x7F || code === 0x22 || code === 0x2C || code === 0x3B || code === 0x5C) {
        return false;
      }
    }
    return true;
  }

  /** True when Domain= attribute should be appended (non-null, non-empty). */
  private static hasCookieDomain(domain: string | null): boolean {
    return domain != null && domain.length > 0;
  }

  /** Empty/null domain is valid; non-empty must pass token rules. */
  private static isValidCookieDomain(domain: string | null): boolean {
    if (domain == null || domain.length == 0) {
      return true;
    }
    return !MyCookieManager.containsInvalidCookieTokenChars(domain);
  }

  /** Logs failed field keys only (no user cookie values) and returns false. */
  private static failCookieValidation(operation: string, result: MethodResult, failedChecks: string[]): void {
    console.warn(LOG_TAG, `${operation}: cookie validation failed (${failedChecks.join(', ')})`);
    result.success(false);
  }

  /** Path must start with / and must not contain control chars or semicolon. */
  private static isValidCookiePath(path: string): boolean {
    if (path == null || path.length == 0 || path.charAt(0) != '/') {
      return false;
    }
    for (let i = 0; i < path.length; i++) {
      let code = path.charCodeAt(i);
      if (code < 0x20 || code === 0x7F || code === 0x3B) {
        return false;
      }
    }
    return true;
  }

  /** SameSite must be Strict, Lax, None, or null. None requires Secure in setCookie. */
  private static isValidSameSite(sameSite: string | null): boolean {
    if (sameSite == null) {
      return true;
    }
    return sameSite === "Strict" || sameSite === "Lax" || sameSite === "None";
  }

  public getCookieExpirationDate(timestamp: number): string {
    let dateFormat = new Intl.DateTimeFormat("en-US", {weekday: 'short', day: '2-digit',
      month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit', timeZone: 'GMT'})
    return dateFormat.format(new Date(timestamp))
  }

  public dispose(): void {
    super.dispose();
    this.plugin = null;
  }
}
