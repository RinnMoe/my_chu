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
import { FlutterWebView } from './webview/in_app_webview/FlutterWebView';
import InAppWebView from './webview/in_app_webview/InAppWebView';
import { uri } from '@kit.ArkTS';
import { Any, MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import business_error from '@ohos.base';

const LOG_TAG = 'MyWebStorage';
const METHOD_CHANNEL_NAME = 'com.pichillilorenzo/flutter_inappwebview_webstoragemanager';
const LOCAL_STORAGE_INFO_TIMEOUT_MS = 3000;
const LOCAL_STORAGE_INFO_SCRIPT =
  "(function(){try{var o=window.location.origin||'';var l=window.localStorage.length;" +
  "return JSON.stringify({origin:o,length:l});}catch(e){return JSON.stringify({origin:'',length:0});}})()";

interface LocalStorageInfo {
  origin: string;
  length: number;
}

interface LocalStorageInfoJson {
  origin?: string;
  length?: number;
}

export default class MyWebStorage extends ChannelDelegateImpl {
  public plugin: InAppWebViewFlutterPlugin | null;

  constructor(plugin: InAppWebViewFlutterPlugin) {
    if (plugin.messenger == null) {
      throw new Error('MyWebStorage: plugin.messenger is null');
    }
    super(new MethodChannel(plugin.messenger, METHOD_CHANNEL_NAME));
    this.plugin = plugin;
  }

  public async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      switch (call.method) {
        case 'getOrigins':
          await this.getOrigins(result);
          break;
        case 'deleteAllData':
          try {
            web_webview.WebStorage.deleteAllData();
            result.success(true);
          } catch (error) {
            ChannelResultUtil.reportError(LOG_TAG, 'deleteAllData', result, error);
          }
          break;
        case 'deleteOrigin':
          try {
            let origin: string = call.argument('origin') as string;
            web_webview.WebStorage.deleteOrigin(origin);
            result.success(true);
          } catch (error) {
            ChannelResultUtil.reportError(LOG_TAG, 'deleteOrigin', result, error);
          }
          break;
        case 'getQuotaForOrigin':
          await this.getQuotaForOrigin(call.argument('origin') as string, result);
          break;
        case 'getUsageForOrigin':
          await this.getUsageForOrigin(call.argument('origin') as string, result);
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      ChannelResultUtil.reportError(LOG_TAG, call.method, result, e as Object);
    }
  }

  private async getOrigins(result: MethodResult): Promise<void> {
    try {
      let origins: web_webview.WebStorageOrigin[] = await web_webview.WebStorage.getOrigins();
      let originsList: Map<string, Any>[] = this.toOriginMapList(origins);
      await this.mergeWebViewLocalStorageOrigins(originsList);
      result.success(originsList);
    } catch (error) {
      let code = (error as business_error.BusinessError)?.code;
      if (code === 17100012) {
        let originsList: Map<string, Any>[] = [];
        await this.mergeWebViewLocalStorageOrigins(originsList);
        result.success(originsList);
        return;
      }
      ChannelResultUtil.reportError(LOG_TAG, 'getOrigins', result, error);
    }
  }

  private toOriginMapList(origins: web_webview.WebStorageOrigin[]): Map<string, Any>[] {
    let originsList: Map<string, Any>[] = [];
    for (let origin of origins) {
      // Match Android semantics: origins with zero usage are treated as absent.
      if (origin.usage <= 0) {
        continue;
      }
      let originInfo: Map<string, Any> = new Map<string, Any>();
      originInfo.set('origin', origin.origin);
      originInfo.set('quota', origin.quota);
      originInfo.set('usage', origin.usage);
      originsList.push(originInfo);
    }
    return originsList;
  }

  private collectActiveWebViews(): InAppWebView[] {
    let webViews: InAppWebView[] = [];
    if (this.plugin == null || this.plugin.inAppWebViewManager == null) {
      return webViews;
    }
    let manager = this.plugin.inAppWebViewManager;
    manager.platformWebViews.forEach((flutterWebView: FlutterWebView) => {
      let webView: InAppWebView | null = flutterWebView.getWebView();
      if (webView != null) {
        webViews.push(webView);
      }
    });
    manager.keepAliveWebViews.forEach((flutterWebView: FlutterWebView | undefined) => {
      if (flutterWebView != null) {
        let webView: InAppWebView | null = flutterWebView.getWebView();
        if (webView != null) {
          webViews.push(webView);
        }
      }
    });
    return webViews;
  }

  private originFromUrl(url: string): string | null {
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

  private normalizeOriginKey(origin: string): string {
    return origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
  }

  private hasOrigin(originsList: Map<string, Any>[], origin: string): boolean {
    let key = this.normalizeOriginKey(origin);
    for (let i = 0; i < originsList.length; i++) {
      let originInfo: Map<string, Any> = originsList[i];
      let existing: string = originInfo.get('origin') as string;
      if (this.normalizeOriginKey(existing) === key) {
        return true;
      }
    }
    return false;
  }

  private getLocalStorageInfo(inAppWebView: InAppWebView): Promise<LocalStorageInfo> {
    let emptyInfo: LocalStorageInfo = { origin: '', length: 0 };
    return new Promise<LocalStorageInfo>((resolve) => {
      let resolved = false;
      let finish = (value: LocalStorageInfo): void => {
        if (!resolved) {
          resolved = true;
          resolve(value);
        }
      };
      setTimeout(() => finish(emptyInfo), LOCAL_STORAGE_INFO_TIMEOUT_MS);
      try {
        inAppWebView.getController().runJavaScript(LOCAL_STORAGE_INFO_SCRIPT).then((res: string) => {
          finish(this.parseLocalStorageInfo(res));
        }).catch(() => finish(emptyInfo));
      } catch (e) {
        finish(emptyInfo);
      }
    });
  }

  private parseLocalStorageInfo(res: string | null | undefined): LocalStorageInfo {
    let emptyInfo: LocalStorageInfo = { origin: '', length: 0 };
    if (res == null || res.length === 0 || res === '') {
      return emptyInfo;
    }
    let jsonText = res;
    if (jsonText.startsWith('"') && jsonText.endsWith('"')) {
      try {
        jsonText = JSON.parse(jsonText) as string;
      } catch (e) {
        return emptyInfo;
      }
    }
    try {
      let parsed = JSON.parse(jsonText) as LocalStorageInfoJson;
      let origin = parsed.origin != null ? parsed.origin : '';
      let length = parsed.length != null ? parsed.length : 0;
      return { origin: origin, length: length };
    } catch (e) {
      return emptyInfo;
    }
  }

  private async mergeWebViewLocalStorageOrigins(originsList: Map<string, Any>[]): Promise<void> {
    let webViews: InAppWebView[] = this.collectActiveWebViews();
    for (let i = 0; i < webViews.length; i++) {
      let webView: InAppWebView = webViews[i];
      if (webView.isDisposed()) {
        continue;
      }
      let storageInfo: LocalStorageInfo = await this.getLocalStorageInfo(webView);
      let origin: string | null = storageInfo.origin.length > 0 ?
        storageInfo.origin : this.originFromUrl(webView.getUrl());
      if (origin == null || origin.length === 0 || origin === 'null') {
        continue;
      }
      if (this.hasOrigin(originsList, origin)) {
        continue;
      }
      if (storageInfo.length <= 0) {
        continue;
      }
      let usage = 0;
      let quota = 0;
      try {
        usage = await web_webview.WebStorage.getOriginUsage(origin);
        quota = await web_webview.WebStorage.getOriginQuota(origin);
      } catch (e) {
        usage = 0;
        quota = 0;
      }
      if (usage <= 0) {
        usage = storageInfo.length;
      }
      let originInfo: Map<string, Any> = new Map<string, Any>();
      originInfo.set('origin', origin);
      originInfo.set('quota', quota);
      originInfo.set('usage', usage);
      originsList.push(originInfo);
    }
  }

  private async getQuotaForOrigin(origin: string, result: MethodResult): Promise<void> {
    try {
      let quota: number = await web_webview.WebStorage.getOriginQuota(origin);
      result.success(quota);
    } catch (error) {
      ChannelResultUtil.reportError(LOG_TAG, 'getQuotaForOrigin', result, error);
    }
  }

  private async getUsageForOrigin(origin: string, result: MethodResult): Promise<void> {
    try {
      let usage: number = await web_webview.WebStorage.getOriginUsage(origin);
      result.success(usage);
    } catch (error) {
      ChannelResultUtil.reportError(LOG_TAG, 'getUsageForOrigin', result, error);
    }
  }

  public dispose(): void {
    super.dispose();
    this.plugin = null;
  }
}
