/*
* Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the 'License');
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an 'AS IS' BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import { MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import ProcessGlobalConfigSettings from './ProcessGlobalConfigSettings';

const LOG_TAG = 'ProcessGlobalConfigManager';
const METHOD_CHANNEL_NAME = 'com.pichillilorenzo/flutter_inappwebview_processglobalconfig';

export default class ProcessGlobalConfigManager extends ChannelDelegateImpl {
  private plugin: InAppWebViewFlutterPlugin | null;

  constructor(plugin: InAppWebViewFlutterPlugin) {
    if (plugin.messenger == null) {
      throw new Error('ProcessGlobalConfigManager: plugin.messenger is null');
    }
    super(new MethodChannel(plugin.messenger, METHOD_CHANNEL_NAME));
    this.plugin = plugin;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'apply':
        this.handleApply(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private handleApply(call: MethodCall, result: MethodResult): void {
    if (this.plugin == null || this.plugin.applicationContext == null) {
      result.success(false);
      return;
    }

    try {
      let settingsArg: Object | null = call.argument('settings') as Object | null;
      let settings = new ProcessGlobalConfigSettings();
      if (settingsArg != null) {
        settings.parse(settingsArg);
      }
      settings.apply(this.plugin.applicationContext);
      result.success(true);
    } catch (e) {
      let message = e instanceof Error ? e.message : String(e);
      result.error(LOG_TAG, message, null);
    }
  }

  dispose(): void {
    this.plugin = null;
    super.dispose();
  }
}
