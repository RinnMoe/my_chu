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

import fs from '@ohos.file.fs';
import uri from '@ohos.uri'
import buffer from '@ohos.buffer';
import util from '@ohos.util';
import { Log } from '@ohos/flutter_ohos';
import MimeUtil from './MimeUtil';

const TAG = "WebViewAssetLoader";

export interface PathHandler {
  handle(path: string): WebResourceResponse;
}

function buildAllowedOrigin(domain: string, scheme: string): string {
  return `${scheme}://${domain}`;
}

function buildCorsHeaders(allowedOrigin: string): Array<Header> {
  return [
    { headerKey: "Access-Control-Allow-Origin", headerValue: allowedOrigin },
    { headerKey: "Access-Control-Allow-Methods", headerValue: "GET, OPTIONS" },
    { headerKey: "Access-Control-Allow-Headers", headerValue: "*" },
  ];
}

function applyCorsHeaders(response: WebResourceResponse, domain: string, scheme: string): void {
  response.setResponseHeader(buildCorsHeaders(buildAllowedOrigin(domain, scheme)));
}

function isTextLikeMime(mimeType: string): boolean {
  return mimeType.startsWith("text/") ||
    mimeType.includes("javascript") ||
    mimeType.includes("json") ||
    mimeType.includes("xml") ||
    mimeType.includes("svg");
}

function normalizeUriPath(path: string | undefined | null): string {
  if (path === null || path === undefined || path.length === 0) {
    return "/";
  }
  return path.startsWith("/") ? path : ("/" + path);
}

/**
 * Loads a file from rawfile synchronously and builds a ready WebResourceResponse.
 * Vite/Vue bundles use `crossorigin` on module scripts, so CORS headers are required.
 */
export function createRawFileWebResponse(context: Context, rawPath: string): WebResourceResponse {
  let webResponse = new WebResourceResponse();
  try {
    let contentData = context.resourceManager.getRawFileContentSync(rawPath);
    let mimeType = MimeUtil.guessMimeType(rawPath);
    if (isTextLikeMime(mimeType)) {
      webResponse.setResponseData(util.TextDecoder.create('utf-8').decodeToString(contentData));
      webResponse.setResponseEncoding('utf-8');
    } else {
      webResponse.setResponseData(contentData.buffer);
    }
    webResponse.setResponseMimeType(mimeType);
    webResponse.setResponseCode(200);
    webResponse.setResponseIsReady(true);
    Log.d(TAG, "Loaded rawfile: " + rawPath + " (" + mimeType + ")");
  } catch (e) {
    Log.e(TAG, "Error opening asset path: " + rawPath + ", " + e);
    webResponse.setResponseCode(404);
    webResponse.setResponseIsReady(true);
  }
  return webResponse;
}

//读取rawfile目录文件
export class AssetsPathHandler implements PathHandler {
  private context: Context

  constructor(context: Context) {
    this.context = context;
  }

  handle(path: string): WebResourceResponse {
    return createRawFileWebResponse(this.context, path);
  }
}

//读取安卓下面有res/raw的资源文件 OHOS没有 OHOS也读取rawfile
export class ResourcesPathHandler implements PathHandler {
  private context: Context

  constructor(context: Context) {
    this.context = context;
  }

  handle(path: string): WebResourceResponse {
    return createRawFileWebResponse(this.context, path);
  }
}

export class InternalStoragePathHandler implements PathHandler {
  private static FORBIDDEN_DATA_DIRS = ["app_webview/", "databases/", "lib/", "preferences/", "code_cache/"];
  private context: Context;
  private directory: string;

  constructor(context: Context, directory: string) {
    this.context = context;
    this.directory = directory.endsWith("/") ? directory : (directory + "/");
  }

  handle(path: string): WebResourceResponse {
    let webResponse = new WebResourceResponse();
    try {
      let stream = fs.createStreamSync(this.directory + path, "r+")
      let arrayBuffer = new ArrayBuffer(4096);
      let readLen = stream.readSync(arrayBuffer);
      let contentData = buffer.from(arrayBuffer, 0, readLen).buffer
      webResponse.setResponseData(contentData);
      webResponse.setResponseMimeType(MimeUtil.guessMimeType(path));
      webResponse.setResponseCode(200);
      webResponse.setResponseIsReady(true);
    } catch (e) {
      Log.e(TAG, "Error opening asset path: " + path, e);
      webResponse.setResponseCode(404);
      webResponse.setResponseIsReady(true);
    }
    return webResponse;
  }
}

export class PathMatcher {
  static HTTP_SCHEME = "http";
  static HTTPS_SCHEME = "https";
  mHttpEnabled: boolean = false;
  mAuthority: string | null = null;
  mPath: string | null = null;
  mHandler: PathHandler | null = null;

  constructor(authority: string, path: string, httpEnabled: boolean, handler: PathHandler) {
    if (path == '' || path.charAt(0) != '/') {
      throw Error("Path should start with a slash '/'.");
    }
    if (!path.endsWith("/")) {
      throw Error("Path should end with a slash '/'");
    }
    this.mAuthority = authority;
    this.mPath = path;
    this.mHttpEnabled = httpEnabled;
    this.mHandler = handler;
  }

  match(uriObj: uri.URI): PathHandler | null {
    // Only match HTTP_SCHEME if caller enabled HTTP matches.
    if (uriObj.scheme == PathMatcher.HTTP_SCHEME && !this.mHttpEnabled) {
      return null;
    }
    // Don't match non-HTTP(S) schemes.
    if (!(uriObj.scheme == PathMatcher.HTTP_SCHEME) && !(uriObj.scheme == PathMatcher.HTTPS_SCHEME)) {
      return null;
    }
    if (!(uriObj.authority == this.mAuthority)) {
      return null;
    }
    let path = normalizeUriPath(uriObj.path);
    if (!(path.startsWith(this.mPath!!))) {
      return null;
    }
    return this.mHandler;
  }

  getSuffixPath(path: string): string {
    let normalizedPath = normalizeUriPath(path);
    let pattern = new RegExp(this.mPath!!)
    return normalizedPath.replace(pattern, "");
  }

  getAuthority(): string {
    return this.mAuthority!!;
  }
}

export default class WebViewAssetLoader {
  public static DEFAULT_DOMAIN = "appassets.androidplatform.net";
  private mMatchers: Array<PathMatcher>;

  constructor(pathMatchers: Array<PathMatcher>) {
    this.mMatchers = pathMatchers;
  }

  shouldInterceptRequest(url: uri.URI) {
    for (let matcher of this.mMatchers) {
      let handler = matcher.match(url);
      // The requested URL doesn't match the URL where this handler has been registered.
      if (handler == null) {
        continue;
      }
      let suffixPath = matcher.getSuffixPath(url.path);
      let response = handler.handle(suffixPath);
      // Handler doesn't want to intercept this request, try next handler.
      if (response == null) {
        continue;
      }
      // CORS headers are only needed for rawfile-based Flutter assets (Vite/Vue ES modules).
      if (handler instanceof AssetsPathHandler || handler instanceof ResourcesPathHandler) {
        applyCorsHeaders(response, matcher.getAuthority(),
          url.scheme === PathMatcher.HTTP_SCHEME ? "http" : "https");
      }
      return response;
    }
    return null;
  }
}

interface Pair {
  path: string;
  handler: PathHandler;
}

export class WebViewAssetLoaderBuilder {
  private mHttpAllowed: boolean = false;
  private mDomain = WebViewAssetLoader.DEFAULT_DOMAIN;
  private mHandlerList = new Array<Pair>();

  setDomain(domain: string): WebViewAssetLoaderBuilder {
    this.mDomain = domain;
    return this;
  }

  setHttpAllowed(httpAllowed: boolean): WebViewAssetLoaderBuilder {
    this.mHttpAllowed = httpAllowed;
    return this;
  }

  addPathHandler(path: string, handler: PathHandler) {
    this.mHandlerList.push({ path: path, handler: handler });
    return this;
  }

  build(): WebViewAssetLoader {
    let pathMatcherList = new Array<PathMatcher>();
    for (let el of this.mHandlerList) {
      pathMatcherList.push(new PathMatcher(this.mDomain, el.path, this.mHttpAllowed, el.handler));
    }
    return new WebViewAssetLoader(pathMatcherList);
  }
}