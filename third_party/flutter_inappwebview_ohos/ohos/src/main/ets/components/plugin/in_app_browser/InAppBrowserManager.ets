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

import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import { util } from '@kit.ArkTS';
import { Any, Log, MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import InAppBrowserSession from './InAppBrowserSession';
import ChannelResultUtil from '../types/ChannelResultUtil';

const LOG_TAG = 'InAppBrowserManager';
const METHOD_CHANNEL_NAME = 'com.pichillilorenzo/flutter_inappbrowser';

export default class InAppBrowserManager extends ChannelDelegateImpl {

  public plugin: InAppWebViewFlutterPlugin | null;
  public id: string;
  public browsers: Map<string, InAppBrowserSession> = new Map<string, InAppBrowserSession>();

  public static shared: Map<string, InAppBrowserManager> = new Map<string, InAppBrowserManager>();

  constructor(plugin: InAppWebViewFlutterPlugin) {
    if (plugin.messenger == null) {
      throw new Error('InAppBrowserManager: plugin.messenger is null');
    }
    super(new MethodChannel(plugin.messenger, METHOD_CHANNEL_NAME));
    this.id = util.generateRandomUUID(true);
    this.plugin = plugin;
    InAppBrowserManager.shared.set(this.id, this);
  }

  public onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'open':
          if (this.plugin != null) {
            this.open(call.args as Map<string, Any> | Record<string, Any>);
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case 'openWithSystemBrowser':
          if (this.plugin != null && this.plugin.uiAbility != null) {
            let url: string = call.argument('url') as string;
            this.openWithSystemBrowser(this.plugin.uiAbility, url, result);
          } else {
            result.success(false);
          }
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      ChannelResultUtil.reportError(LOG_TAG, call.method, result, e as Object);
    }
  }

  public open(args: Map<string, Any> | Record<string, Any>): void {
    let browserId = InAppBrowserManager.getArg(args, 'id') as string;
    if (browserId == null || browserId.length === 0 || this.plugin == null) {
      Log.e(LOG_TAG, 'open: invalid args or plugin');
      return;
    }

    let existing = this.browsers.get(browserId);
    if (existing != null) {
      existing.dispose();
    }

    let session = new InAppBrowserSession(this);
    this.browsers.set(browserId, session);
    session.start(this.plugin, args);
  }

  public removeBrowser(browserId: string): void {
    this.browsers.delete(browserId);
  }

  public static getArg(args: Map<string, Any> | Record<string, Any> | null | undefined, key: string): Any {
    if (args == null || args == undefined) {
      return null;
    }
    if (args instanceof Map) {
      return args.get(key);
    }
    return (args as Record<string, Any>)[key];
  }

  public static asMap(value: Map<string, Any> | Record<string, Any>): Map<string, Any> {
    if (value instanceof Map) {
      return value;
    }
    let map: Map<string, Any> = new Map<string, Any>();
    let obj = value as Record<string, Any>;
    let keys: string[] = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      map.set(keys[i], obj[keys[i]]);
    }
    return map;
  }

  public static buildWebViewParams(args: Map<string, Any> | Record<string, Any>): Map<string, Any> {
    let params: Map<string, Any> = new Map<string, Any>();
    let settings: Map<string, Any> | Record<string, Any> | null = InAppBrowserManager.getArg(args, 'settings');
    let initialSettings: Map<string, Any> = new Map<string, Any>();
    if (settings != null) {
      let settingsMap: Map<string, Any> = InAppBrowserManager.asMap(settings as Record<string, Any>);
      let webViewSettings: Map<string, Any> | Record<string, Any> | null = settingsMap.get('webViewSettings');
      if (webViewSettings != null) {
        initialSettings = InAppBrowserManager.asMap(webViewSettings as Record<string, Any>);
      } else {
        initialSettings = settingsMap;
      }
    }
    params.set('initialSettings', initialSettings);
    params.set('contextMenu', InAppBrowserManager.getArg(args, 'contextMenu'));
    params.set('windowId', InAppBrowserManager.getArg(args, 'windowId'));
    params.set('initialUserScripts', InAppBrowserManager.getArg(args, 'initialUserScripts'));
    params.set('pullToRefreshSettings', InAppBrowserManager.getArg(args, 'pullToRefreshSettings'));
    return params;
  }

  public static buildLoadParams(args: Map<string, Any> | Record<string, Any>): Map<string, Any> {
    let loadParams: Map<string, Any> = new Map<string, Any>();
    loadParams.set('windowId', InAppBrowserManager.getArg(args, 'windowId'));

    let urlRequest: Map<string, Any> | Record<string, Any> | null = InAppBrowserManager.getArg(args, 'urlRequest');
    if (urlRequest != null) {
      loadParams.set('initialUrlRequest', urlRequest);
    }

    let assetFilePath = InAppBrowserManager.getArg(args, 'assetFilePath') as string;
    if (assetFilePath != null && assetFilePath.length > 0) {
      loadParams.set('initialFile', assetFilePath);
    }

    let data = InAppBrowserManager.getArg(args, 'data') as string;
    if (data != null) {
      let initialData: Map<string, Any> = new Map<string, Any>();
      initialData.set('data', data);
      initialData.set('mimeType', InAppBrowserManager.getArg(args, 'mimeType'));
      initialData.set('encoding', InAppBrowserManager.getArg(args, 'encoding'));
      initialData.set('baseUrl', InAppBrowserManager.getArg(args, 'baseUrl'));
      initialData.set('historyUrl', InAppBrowserManager.getArg(args, 'historyUrl'));
      loadParams.set('initialData', initialData);
    }

    return loadParams;
  }

  public openWithSystemBrowser(uiAbility: UIAbility, url: string, result: MethodResult): void {
    try {
      let want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      };

      uiAbility.context.startAbility(want, (err: BusinessError) => {
        if (err.code) {
          Log.e(LOG_TAG, `Failed to startAbility. Code: ${err.code}, message: ${err.message}`);
          result.error(`Code: ${err.code}`, err.message, null);
        } else {
          result.success(true);
        }
      });
    } catch (e) {
      Log.d(LOG_TAG, url + ' cannot be opened: ' + e.toString());
      result.error(LOG_TAG, url + ' cannot be opened!', null);
    }
  }

  public dispose(): void {
    let sessions = this.browsers.values();
    for (let session of sessions) {
      try {
        session.dispose();
      } catch (e) {
        Log.d(LOG_TAG, 'dispose: browser session dispose failed: ' + e.toString());
      }
    }
    this.browsers.clear();
    super.dispose();
    InAppBrowserManager.shared.delete(this.id);
    this.plugin = null;
  }
}
