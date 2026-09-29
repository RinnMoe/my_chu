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
import http from '@ohos.net.http';

const TAG = "ContentBlockerHttpUtil";
const HEAD_CONNECT_TIMEOUT_MS = 15000;
const HEAD_READ_TIMEOUT_MS = 15000;
const MAX_CONTENT_TYPE_CACHE_SIZE = 256;

export default class ContentBlockerHttpUtil {
  private static readonly REQUEST_METHOD_MAP: Map<string, http.RequestMethod> = new Map([
    ['GET', http.RequestMethod.GET],
    ['POST', http.RequestMethod.POST],
    ['PUT', http.RequestMethod.PUT],
    ['DELETE', http.RequestMethod.DELETE],
    ['HEAD', http.RequestMethod.HEAD],
    ['OPTIONS', http.RequestMethod.OPTIONS],
  ]);

  private static contentTypeCache: Map<string, string> = new Map();
  private static pendingHeadUrls: Set<string> = new Set();

  static resolveRequestMethod(method: string): http.RequestMethod {
    let resolved = ContentBlockerHttpUtil.REQUEST_METHOD_MAP.get(method.toUpperCase());
    if (resolved != null) {
      return resolved;
    }
    return http.RequestMethod.GET;
  }

  static buildHeaderRecord(headers: Map<string, string>): Record<string, string> {
    let headerObj: Record<string, string> = {};
    headers.forEach((value: string, key: string) => {
      headerObj[key] = value;
    });
    return headerObj;
  }

  static getCachedContentType(url: string): string {
    let cached = ContentBlockerHttpUtil.contentTypeCache.get(url);
    return cached != null ? cached : '';
  }

  static scheduleHeadCacheUpdate(url: string, headers: Map<string, string>): void {
    if (ContentBlockerHttpUtil.contentTypeCache.has(url) ||
      ContentBlockerHttpUtil.pendingHeadUrls.has(url)) {
      return;
    }
    ContentBlockerHttpUtil.pendingHeadUrls.add(url);
    let httpRequest = http.createHttp();
    let headerObj = ContentBlockerHttpUtil.buildHeaderRecord(headers);
    httpRequest.request(url, {
      method: http.RequestMethod.HEAD,
      header: headerObj,
      connectTimeout: HEAD_CONNECT_TIMEOUT_MS,
      readTimeout: HEAD_READ_TIMEOUT_MS,
    }).then((resp: http.HttpResponse) => {
      try {
        if (resp.header) {
          let headerMap = resp.header as Record<string, string>;
          let contentType = headerMap['content-type'] ?? headerMap['Content-Type'] ?? '';
          if (contentType.length > 0) {
            ContentBlockerHttpUtil.putContentTypeCache(url, contentType.split(';')[0].trim());
          }
        }
      } catch (e) {
        Log.e(TAG, "scheduleHeadCacheUpdate parse failed: " + e);
      }
    }).catch((e: Error) => {
      Log.e(TAG, "scheduleHeadCacheUpdate failed: " + (e ? e.message : 'unknown'));
    }).finally(() => {
      ContentBlockerHttpUtil.pendingHeadUrls.delete(url);
      httpRequest.destroy();
    });
  }

  private static putContentTypeCache(url: string, contentType: string): void {
    if (ContentBlockerHttpUtil.contentTypeCache.size >= MAX_CONTENT_TYPE_CACHE_SIZE) {
      let firstKey: string | undefined = ContentBlockerHttpUtil.contentTypeCache.keys().next().value;
      if (firstKey != null) {
        ContentBlockerHttpUtil.contentTypeCache.delete(firstKey);
      }
    }
    ContentBlockerHttpUtil.contentTypeCache.set(url, contentType);
  }

  static clearCache(): void {
    ContentBlockerHttpUtil.contentTypeCache.clear();
    ContentBlockerHttpUtil.pendingHeadUrls.clear();
    Log.d(TAG, 'clearCache: contentTypeCache and pendingHeadUrls cleared');
  }
}
