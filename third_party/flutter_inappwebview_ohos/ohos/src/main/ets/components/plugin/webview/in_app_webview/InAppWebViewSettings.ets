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

import { Any, Log } from '@ohos/flutter_ohos';
import ISettings from '../../ISettings';
import InAppWebViewInterface from '../InAppWebViewInterface';

const LOG_TAG = "InAppWebViewSettings";

export default class InAppWebViewSettings implements ISettings<InAppWebViewInterface> {
  public domStorageAccess: boolean = true;
  public fileAccess: boolean = true;
  public allowFileAccessFromFileURLs: boolean = false;
  public allowUniversalAccessFromFileURLs: boolean = false;
  public imageAccess: boolean = true;
  public javaScriptAccess: boolean = true;
  public overScrollMode: OverScrollMode = OverScrollMode.NEVER;
  public mixedMode: MixedMode = MixedMode.None;
  public onlineImageAccess: boolean = true;
  public zoomAccess: boolean = true;
  public overviewModeAccess: boolean = true;
  public databaseAccess: boolean = false;
  public geolocationAccess: boolean = true;
  public mediaPlayGestureAccess: boolean = true;
  public multiWindowAccess: boolean = true;
  public horizontalScrollBarAccess: boolean = true;
  public verticalScrollBarAccess: boolean = true;
  public cacheMode: CacheMode = CacheMode.Default;
  public textZoomRatio: number = 100;
  public initialScale: number = 100;
  public blockNetwork: boolean = false;
  public defaultFixedFontSize: number = 13;
  public defaultFontSize: number = 16;
  public minFontSize: number = 8;
  public minLogicalFontSize: number = 8;
  public webFixedFont: string = "monospace";
  public webSansSerifFont: string = "sans-serif";
  public webSerifFont: string = "serif";
  public webStandardFont: string = "sans-serif";
  public webFantasyFont: string = "fantasy";
  public webCursiveFont: string = "cursive";
  public darkMode: WebDarkMode = WebDarkMode.Off;
  public forceDarkAccess: boolean = false;
  public pinchSmooth: boolean = false;
  public allowWindowOpenMethod: boolean = false;
  public layoutMode: WebLayoutMode = WebLayoutMode.NONE;
  public enableNativeEmbedMode: boolean = false;
  public userAgent: string = ""
  public useHybridComposition: boolean = true;
  public useOnLoadResource: boolean = false;
  public useOnDownloadStart: boolean = false;
  public useShouldInterceptAjaxRequest: boolean = false;
  public interceptOnlyAsyncAjaxRequests: boolean = true;
  public useShouldInterceptFetchRequest: boolean = false;
  public useShouldInterceptRequest: boolean = false;
  public resourceCustomSchemes: Array<string> | null = new Array<string>();
  public webViewAssetLoader: Map<string, Any> | null = null;
  public contentBlockers: Array<Map<string, Map<string, Any>>> = new Array<Map<string, Map<string, Any>>>();
  public useShouldOverrideUrlLoading: boolean = false;
  public useOnNavigationResponse: boolean = false;
  public regexToCancelSubFramesLoading: string | null = null;
  public disableDefaultErrorPage: boolean = false;
  public useOnRenderProcessGone: boolean = false;
  public thirdPartyCookiesEnabled: boolean = true;
  public applicationNameForUserAgent: string | null = "";
  public transparentBackground: boolean = false;
  public incognito: boolean = false;
  public cacheEnabled: boolean = true;

  parse(settings: Map<string, Any>): ISettings<InAppWebViewInterface> {
    let keys = settings.keys();
    for (let key of keys) {
      let value: Object = settings.get(key) as Object;
      if (value == null) {
        continue;
      }
      switch (key) {
        case "domStorageEnabled":
          this.domStorageAccess = value as boolean;
          break;
        case "allowFileAccess":
          this.fileAccess = value as boolean;
          break;
        case "allowFileAccessFromFileURLs":
          this.allowFileAccessFromFileURLs = value as boolean;
          break;
        case "allowUniversalAccessFromFileURLs":
          this.allowUniversalAccessFromFileURLs = value as boolean;
          break;

        case "loadsImagesAutomatically":
          this.imageAccess = value as boolean;
          break;
        case "javaScriptEnabled":
          this.javaScriptAccess = value as boolean;
          break;
        case "overScrollMode":
          let overMode = value as number;
          if (overMode == 0 || overMode == 1) {
            this.overScrollMode = OverScrollMode.ALWAYS
          } else if (overMode == 2) {
            this.overScrollMode = OverScrollMode.NEVER;
          }
          break;
        case "mixedContentMode":
          let mixedContentMode = value as number;
          if (mixedContentMode == 0) {
            this.mixedMode = MixedMode.All;
          } else if (mixedContentMode == 1) {
            this.mixedMode = MixedMode.None;
          } else if (mixedContentMode == 2) {
            this.mixedMode = MixedMode.Compatible;
          }
          break;
        case "blockNetworkImage":
          this.onlineImageAccess = !(value as boolean)
          break;
        case "supportZoom":
          this.zoomAccess = value as boolean
          break;
        case "loadWithOverviewMode":
          this.overviewModeAccess = value as boolean
          break;
        case "databaseEnabled":
          this.databaseAccess = value as boolean
          break;
        case "geolocationEnabled":
          this.geolocationAccess = value as boolean
          break;
        case "mediaPlaybackRequiresUserGesture":
          this.mediaPlayGestureAccess = value as boolean
          break;
        case "supportMultipleWindows":
          this.multiWindowAccess = value as boolean
          break;
        case "horizontalScrollBarEnabled":
          this.horizontalScrollBarAccess = value as boolean
          break;
        case "verticalScrollBarEnabled":
          this.verticalScrollBarAccess = value as boolean
          break;
        case "cacheMode":
          let cacheModeValue = value as number;
          if (cacheModeValue == -1) {
            this.cacheMode = CacheMode.Default;
          } else if (cacheModeValue == 1) {
            this.cacheMode = CacheMode.None;
          } else if (cacheModeValue == 2) {
            this.cacheMode = CacheMode.Online;
          } else if (cacheModeValue == 3) {
            this.cacheMode = CacheMode.Only;
          }
          break;
        case "textZoom":
          this.textZoomRatio = value as number;
          break;
        case "initialScale":
          this.initialScale = value as number;
          break;
        case "blockNetworkLoads":
          this.blockNetwork = value as boolean;
          break;
        case "defaultFixedFontSize":
          this.defaultFixedFontSize = value as number;
          break;
        case "defaultFontSize":
          this.defaultFontSize = value as number;
          break;
        case "minimumFontSize":
          this.minFontSize = value as number;
          break;
        case "minimumLogicalFontSize":
          this.minLogicalFontSize = value as number;
          break;
        case "fixedFontFamily":
          this.webFixedFont = value as string;
          break;
        case "sansSerifFontFamily":
          this.webSansSerifFont = value as string;
          break;
        case "serifFontFamily":
          this.webSerifFont = value as string;
          break;
        case "standardFontFamily":
          this.webStandardFont = value as string;
          break;
        case "fantasyFontFamily":
          this.webFantasyFont = value as string;
          break;
        case "cursiveFontFamily":
          this.webCursiveFont = value as string;
          break;
        case "forceDark":
          let darkModeValue = value as number;
          if (darkModeValue == 0) {
            this.darkMode = WebDarkMode.Off;
          } else if (darkModeValue == 1) {
            this.darkMode = WebDarkMode.Auto;
          } else if (darkModeValue == 2) {
            this.darkMode = WebDarkMode.On;
          }
          break;
        case "forceDarkAccess":
          this.forceDarkAccess = value as boolean;
          break;
        case "pinchSmooth":
          this.pinchSmooth = value as boolean;
          break;
        case "javaScriptCanOpenWindowsAutomatically":
          this.allowWindowOpenMethod = value as boolean;
          break;
        case "layoutMode":
          let modeValue = value as number;
          if (modeValue == 0) {
            this.layoutMode = WebLayoutMode.NONE;
          } else if (modeValue == 1) {
            this.layoutMode = WebLayoutMode.FIT_CONTENT;
          }
          break;
        case "enableNativeEmbedMode":
          this.enableNativeEmbedMode = value as boolean;
          break;
        case "userAgent":
          this.userAgent = value as string;
          break;
        case "useHybridComposition":
          this.useHybridComposition = value as boolean;
          break;
        case "useOnLoadResource":
          this.useOnLoadResource = value as boolean;
          break;
        case "useOnDownloadStart":
          this.useOnDownloadStart = value as boolean;
          break;
        case "useShouldInterceptAjaxRequest":
          this.useShouldInterceptAjaxRequest = value as boolean;
          break;
        case "interceptOnlyAsyncAjaxRequests":
          this.interceptOnlyAsyncAjaxRequests = value as boolean;
          break;
        case "useShouldInterceptFetchRequest":
          this.useShouldInterceptFetchRequest = value as boolean;
          break;
        case "useShouldInterceptRequest":
          this.useShouldInterceptRequest = value as boolean;
          break;
        case "webViewAssetLoader":
          this.webViewAssetLoader = value as Map<string, Any> | null;
          break;
        case "resourceCustomSchemes":
          this.resourceCustomSchemes = value as Array<string> | null;
          break;
        case "contentBlockers":
          this.contentBlockers = value as Array<Map<string, Map<string, Any>>>;
          break;
        case "useShouldOverrideUrlLoading":
          this.useShouldOverrideUrlLoading = value as boolean;
          break;
        case "useOnNavigationResponse":
          this.useOnNavigationResponse = value as boolean;
          break;
        case "regexToCancelSubFramesLoading":
          this.regexToCancelSubFramesLoading = value as string | null;
          break;
        case "disableDefaultErrorPage":
          this.disableDefaultErrorPage = value as boolean;
          break;
        case "useOnRenderProcessGone":
          this.useOnRenderProcessGone = value as boolean;
          break;
        case "thirdPartyCookiesEnabled":
          this.thirdPartyCookiesEnabled = value as boolean;
          break;
        case "applicationNameForUserAgent":
          this.applicationNameForUserAgent = value as string | null;
          break;
        case "transparentBackground":
          this.transparentBackground = value as boolean;
          break;
        case "incognito":
          this.incognito = value as boolean;
          break;
        case "cacheEnabled":
          this.cacheEnabled = value as boolean;
          break;
      }
    }
    return this;
  }

  toMap(): Map<string, Any> {
    let settings: Map<string, Any> = new Map<string, Any>();
    settings.set("domStorageEnabled", this.domStorageAccess);
    settings.set("allowFileAccess", this.fileAccess);
    settings.set("allowFileAccessFromFileURLs", this.allowFileAccessFromFileURLs);
    settings.set("allowUniversalAccessFromFileURLs", this.allowUniversalAccessFromFileURLs);
    settings.set("loadsImagesAutomatically", this.imageAccess);
    settings.set("javaScriptEnabled", this.javaScriptAccess);
    settings.set("overScrollMode", this.convertOverScrollModeToDart(this.overScrollMode));
    settings.set("mixedContentMode", this.convertMixedModeToDart(this.mixedMode));
    settings.set("blockNetworkImage",!this.onlineImageAccess);
    settings.set("supportZoom", this.zoomAccess);
    settings.set("loadWithOverviewMode", this.overviewModeAccess);
    settings.set("databaseEnabled", this.databaseAccess);
    settings.set("geolocationEnabled", this.geolocationAccess);
    settings.set("mediaPlaybackRequiresUserGesture", this.mediaPlayGestureAccess);
    settings.set("supportMultipleWindows", this.multiWindowAccess);
    settings.set("horizontalScrollBarEnabled", this.horizontalScrollBarAccess);
    settings.set("verticalScrollBarEnabled", this.verticalScrollBarAccess);
    settings.set("cacheMode", this.convertCacheModeToDart(this.cacheMode));
    settings.set("textZoom", this.textZoomRatio);
    settings.set("initialScale", this.initialScale);
    settings.set("blockNetworkLoads", this.blockNetwork);
    settings.set("defaultFixedFontSize", this.defaultFixedFontSize);
    settings.set("defaultFontSize", this.defaultFontSize);
    settings.set("minimumFontSize", this.minFontSize);
    settings.set("minimumLogicalFontSize", this.minLogicalFontSize);
    settings.set("fixedFontFamily", this.webFixedFont);
    settings.set("sansSerifFontFamily", this.webSansSerifFont);
    settings.set("serifFontFamily", this.webSerifFont);
    settings.set("standardFontFamily", this.webStandardFont);
    settings.set("fantasyFontFamily", this.webFantasyFont);
    settings.set("cursiveFontFamily", this.webCursiveFont);
    settings.set("forceDark", this.convertDartModeToDart(this.darkMode));
    settings.set("forceDarkAccess", this.forceDarkAccess);
    settings.set("pinchSmooth", this.pinchSmooth);
    settings.set("javaScriptCanOpenWindowsAutomatically", this.allowWindowOpenMethod);
    settings.set("layoutMode", this.convertLayoutModeToDart(this.layoutMode));
    settings.set("enableNativeEmbedMode", this.enableNativeEmbedMode);
    settings.set("userAgent", this.userAgent);
    settings.set("useHybridComposition", this.useHybridComposition);
    settings.set("useOnLoadResource", this.useOnLoadResource);
    settings.set("useOnDownloadStart", this.useOnDownloadStart);
    settings.set("useShouldInterceptAjaxRequest", this.useShouldInterceptAjaxRequest);
    settings.set("interceptOnlyAsyncAjaxRequests", this.interceptOnlyAsyncAjaxRequests);
    settings.set("useShouldInterceptFetchRequest", this.useShouldInterceptFetchRequest);
    settings.set("useShouldInterceptRequest", this.useShouldInterceptRequest);
    settings.set("resourceCustomSchemes", this.resourceCustomSchemes);
    settings.set("contentBlockers", this.contentBlockers);
    settings.set("useShouldOverrideUrlLoading", this.useShouldOverrideUrlLoading);
    settings.set("useOnNavigationResponse", this.useOnNavigationResponse);
    settings.set("regexToCancelSubFramesLoading", this.regexToCancelSubFramesLoading);
    settings.set("disableDefaultErrorPage", this.disableDefaultErrorPage);
    settings.set("useOnRenderProcessGone", this.useOnRenderProcessGone);
    settings.set("thirdPartyCookiesEnabled", this.thirdPartyCookiesEnabled);
    settings.set("applicationNameForUserAgent", this.applicationNameForUserAgent);
    settings.set("transparentBackground", this.transparentBackground);
    settings.set("incognito", this.incognito);
    settings.set("cacheEnabled", this.cacheEnabled);
    return settings;
  }

  getRealSettings(inAppWebView: InAppWebViewInterface): Map<string, Any> {
    let realSettings: Map<string, Any> = this.toMap();
    realSettings.set("userAgent", inAppWebView.getSafeCustomUserAgent());
    return realSettings;
  }

  private convertOverScrollModeToDart(mode: OverScrollMode): number {
    if (mode == OverScrollMode.ALWAYS) {
      return 0;
    } else if (mode == OverScrollMode.NEVER) {
      return 2;
    }
    return 2;
  }

  private convertMixedModeToDart(mode: MixedMode): number {
    if (mode == MixedMode.All) {
      return 0;
    } else if (mode == MixedMode.None) {
      return 1;
    } else if (mode == MixedMode.Compatible) {
      return 2
    }
    return 1;
  }

  private convertCacheModeToDart(mode: CacheMode): number {
    if (mode == CacheMode.Default) {
      return -1;
    } else if (mode == CacheMode.None) {
      return 1;
    } else if (mode == CacheMode.Online) {
      return 2
    } else if (mode == CacheMode.Only) {
      return 3
    }
    return -1;
  }

  private convertDartModeToDart(mode: WebDarkMode): number {
    if (mode == WebDarkMode.Off) {
      return 0;
    } else if (mode == WebDarkMode.Auto) {
      return 1;
    } else if (mode == WebDarkMode.On) {
      return 2
    }
    return 0;
  }

  private convertLayoutModeToDart(mode: WebLayoutMode): number {
    if (mode == WebLayoutMode.NONE) {
      return 0;
    } else if (mode == WebLayoutMode.FIT_CONTENT) {
      return 1;
    }
    return 0;
  }
}