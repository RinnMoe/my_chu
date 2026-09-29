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
import { webview } from '@kit.ArkWeb';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { InAppWebViewManager } from '../webview/InAppWebViewManager';
import ProxySettings from './ProxySettings';
import ProxyRuleExt from './ProxyRuleExt';

const LOG_TAG = 'ProxyManager';
const METHOD_CHANNEL_NAME = 'com.pichillilorenzo/flutter_inappwebview_proxycontroller';

export default class ProxyManager extends ChannelDelegateImpl {
  private plugin: InAppWebViewFlutterPlugin | null;

  constructor(plugin: InAppWebViewFlutterPlugin) {
    if (plugin.messenger == null) {
      throw new Error('ProxyManager: plugin.messenger is null');
    }
    super(new MethodChannel(plugin.messenger, METHOD_CHANNEL_NAME));
    this.plugin = plugin;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'setProxyOverride':
        this.handleSetProxyOverride(call, result);
        break;
      case 'clearProxyOverride':
        this.handleClearProxyOverride(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private handleSetProxyOverride(call: MethodCall, result: MethodResult): void {
    try {
      InAppWebViewManager.ensureArkWebEngineInitialized();
      let settingsArg: Object | null = call.argument('settings') as Object | null;
      let settings = new ProxySettings();
      if (settingsArg != null) {
        settings.parse(settingsArg);
      }
      let proxyConfig = new webview.ProxyConfig();
      ProxyManager.applySettings(proxyConfig, settings);
      webview.ProxyController.applyProxyOverride(proxyConfig, () => {
        result.success(true);
      });
    } catch (e) {
      let message = e instanceof Error ? e.message : String(e);
      Log.e(LOG_TAG, `setProxyOverride failed: ${message}`);
      result.error(LOG_TAG, message, null);
    }
  }

  private handleClearProxyOverride(result: MethodResult): void {
    try {
      InAppWebViewManager.ensureArkWebEngineInitialized();
      webview.ProxyController.removeProxyOverride(() => {
        result.success(true);
      });
    } catch (e) {
      let message = e instanceof Error ? e.message : String(e);
      Log.e(LOG_TAG, `clearProxyOverride failed: ${message}`);
      result.error(LOG_TAG, message, null);
    }
  }

  private static applySettings(proxyConfig: webview.ProxyConfig, settings: ProxySettings): void {
    for (let i = 0; i < settings.bypassRules.length; i++) {
      proxyConfig.insertBypassRule(settings.bypassRules[i]);
    }
    for (let i = 0; i < settings.directs.length; i++) {
      proxyConfig.insertDirectRule(ProxyManager.toSchemeFilter(settings.directs[i]));
    }
    for (let i = 0; i < settings.proxyRules.length; i++) {
      let rule: ProxyRuleExt = settings.proxyRules[i];
      proxyConfig.insertProxyRule(
        ProxyManager.normalizeProxyUrl(rule.url),
        ProxyManager.toSchemeFilter(rule.schemeFilter));
    }
    if (settings.bypassSimpleHostnames === true) {
      proxyConfig.bypassHostnamesWithoutPeriod();
    }
    if (settings.removeImplicitRules === true) {
      proxyConfig.clearImplicitRules();
    }
    if (settings.reverseBypassEnabled) {
      proxyConfig.enableReverseBypass(true);
    }
  }

  private static normalizeProxyUrl(url: string): string {
    let trimmed = url.trim();
    if (trimmed.length === 0) {
      return trimmed;
    }
    let lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') ||
      lower.startsWith('socks://') || lower.startsWith('socks5://')) {
      return trimmed;
    }
    return `http://${trimmed}`;
  }

  private static toSchemeFilter(filter: string | null): webview.ProxySchemeFilter {
    if (filter == null || filter.length === 0 || filter === '*') {
      return webview.ProxySchemeFilter.MATCH_ALL_SCHEMES;
    }
    if (filter === 'http') {
      return webview.ProxySchemeFilter.MATCH_HTTP;
    }
    if (filter === 'https') {
      return webview.ProxySchemeFilter.MATCH_HTTPS;
    }
    return webview.ProxySchemeFilter.MATCH_ALL_SCHEMES;
  }

  dispose(): void {
    try {
      InAppWebViewManager.ensureArkWebEngineInitialized();
      webview.ProxyController.removeProxyOverride(() => {
        Log.d(LOG_TAG, 'dispose: proxy override removed');
      });
    } catch (e) {
      Log.e(LOG_TAG, 'dispose removeProxyOverride failed: ' + JSON.stringify(e));
    }
    this.plugin = null;
    super.dispose();
  }
}
