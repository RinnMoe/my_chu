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
import { Any } from '@ohos/flutter_ohos';
import { Context } from '@kit.AbilityKit';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import ChannelResultUtil from '../types/ChannelResultUtil';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { FlutterWebView } from '../webview/in_app_webview/FlutterWebView';
import { HeadlessInAppWebView } from './HeadlessInAppWebView';

const LOG_TAG: string = 'HeadlessInAppWebViewManager';
const METHOD_CHANNEL_NAME: string = 'com.pichillilorenzo/flutter_headless_inappwebview';

export class HeadlessInAppWebViewManager extends ChannelDelegateImpl {
  public webViews: Map<string, HeadlessInAppWebView> = new Map<string, HeadlessInAppWebView>();
  public plugin: InAppWebViewFlutterPlugin | null = null;

  constructor(plugin: InAppWebViewFlutterPlugin) {
    if (plugin.messenger == null) {
      throw new Error('HeadlessInAppWebViewManager: plugin.messenger is null');
    }
    super(new MethodChannel(plugin.messenger, METHOD_CHANNEL_NAME));
    this.plugin = plugin;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      let id: string = call.argument('id') as string;

      switch (call.method) {
        case 'run':
          {
            let params: Map<string, Any> = call.argument('params') as Map<string, Any>;
            this.run(id, params);
            result.success(true);
          }
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      let err: Error = e as Error;
      ChannelResultUtil.reportError(LOG_TAG, call.method, result, err as Object);
    }
  }

  run(id: string, params: Map<string, Any>): void {
    if (this.plugin == null || (this.plugin.uiAbility == null && this.plugin.applicationContext == null)) {
      return;
    }
    let existing = this.webViews.get(id);
    if (existing != null) {
      existing.dispose();
    }
    this.plugin.inAppWebViewManager?.ensureArkWebEngineInitialized();
    let context: Context = this.plugin.uiAbility != null ? this.plugin.uiAbility!.context :
      (this.plugin.applicationContext != null ? this.plugin.applicationContext! : this.plugin.uiAbility!.context);
    let flutterWebView = new FlutterWebView(this.plugin, context, id, params);
    let headlessInAppWebView = new HeadlessInAppWebView(this.plugin, id, flutterWebView);
    this.webViews.set(id, headlessInAppWebView);

    headlessInAppWebView.prepare(params);
  }

  dispose(): void {
    super.dispose();
    let headlessInAppWebViews = this.webViews.values();
    for (let headlessInAppWebView of headlessInAppWebViews) {
      if (headlessInAppWebView != null) {
        try {
          headlessInAppWebView.dispose();
        } catch (e) {
          Log.e(LOG_TAG, 'dispose: headlessInAppWebView dispose failed: ' + JSON.stringify(e));
        }
      }
    }
    this.webViews.clear();
    this.plugin = null;
  }
}
