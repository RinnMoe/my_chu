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

import { MethodCall, MethodChannel, Log } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import ChannelDelegateImpl from './types/ChannelDelegateImpl';
import InAppWebViewFlutterPlugin from './InAppWebViewFlutterPlugin';

const LOG_TAG = 'WebViewFeatureManager';
const METHOD_CHANNEL_NAME = 'com.pichillilorenzo/flutter_inappwebview_webviewfeature';

/**
 * OHOS counterpart of Android WebViewFeatureManager.
 * ArkWeb does not expose AndroidX WebViewFeature startup APIs; startup queries return false.
 */
export default class WebViewFeatureManager extends ChannelDelegateImpl {
  private static readonly SUPPORTED_FEATURES: Set<string> = new Set<string>([
    'WEB_MESSAGE_LISTENER',
    'DOCUMENT_START_SCRIPT',
    'PROXY_OVERRIDE',
    'MULTI_PROCESS',
    'WEBVIEW_MEDIA_INTEGRITY_API_STATUS',
  ]);

  constructor(_plugin: InAppWebViewFlutterPlugin) {
    super(new MethodChannel(_plugin.messenger!, METHOD_CHANNEL_NAME));
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'isFeatureSupported': {
        let feature: string = call.argument('feature') as string;
        result.success(WebViewFeatureManager.isFeatureSupported(feature));
        break;
      }
      case 'isStartupFeatureSupported': {
        let startupFeature: string = call.argument('startupFeature') as string;
        result.success(WebViewFeatureManager.isStartupFeatureSupported(startupFeature));
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }

  static isFeatureSupported(feature: string | null): boolean {
    if (feature == null || feature.length === 0) {
      return false;
    }
    return WebViewFeatureManager.SUPPORTED_FEATURES.has(feature);
  }

  static isStartupFeatureSupported(startupFeature: string | null): boolean {
    if (startupFeature == null || startupFeature.length === 0) {
      return false;
    }
    Log.d(LOG_TAG, `isStartupFeatureSupported(${startupFeature}) => false (not supported on OHOS)`);
    return false;
  }
}
