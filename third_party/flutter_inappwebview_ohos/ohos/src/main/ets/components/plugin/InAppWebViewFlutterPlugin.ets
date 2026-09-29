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

import { AbilityAware, AbilityPluginBinding, BinaryMessenger, Log } from '@ohos/flutter_ohos';
import {
  FlutterAssets,
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { HeadlessInAppWebViewManager } from './headless_in_webview/HeadlessInAppWebViewManager';
import MyCookieManager from './MyCookieManager';
import MyWebStorage from './MyWebStorage';
import PrintJobManager from './print_job/PrintJobManager';
import FlutterWebViewFactory from './webview/FlutterWebViewFactory';
import { InAppWebViewManager } from './webview/InAppWebViewManager';
import InAppBrowserManager from './in_app_browser/InAppBrowserManager';
import CredentialDatabase from './credential_database/CredentialDatabase';
import CredentialDatabaseHandler from './credential_database/CredentialDatabaseHandler';
import WebViewFeatureManager from './WebViewFeatureManager';
import ProcessGlobalConfigManager from './process_global_config/ProcessGlobalConfigManager';
import ProxyManager from './proxy/ProxyManager';
import ContentBlockerHttpUtil from './content_blocker/ContentBlockerHttpUtil';
import common from '@ohos.app.ability.common';
import { UIAbility } from '@kit.AbilityKit';

const TAG = 'InAppWebViewFlutterPlugin';

export default class InAppWebViewFlutterPlugin implements FlutterPlugin, AbilityAware {
  public flutterAssets: FlutterAssets | null = null;
  public flutterWebViewFactory: FlutterWebViewFactory | null = null
  public messenger: BinaryMessenger | null = null
  public printJobManager: PrintJobManager | null = null;
  public myCookieManager: MyCookieManager | null = null
  public myWebStorage: MyWebStorage | null = null
  public headlessInAppWebViewManager: HeadlessInAppWebViewManager | null = null;
  public inAppWebViewManager: InAppWebViewManager | null = null;
  public inAppBrowserManager: InAppBrowserManager | null = null;
  public credentialDatabaseHandler: CredentialDatabaseHandler | null = null;
  public webViewFeatureManager: WebViewFeatureManager | null = null;
  public processGlobalConfigManager: ProcessGlobalConfigManager | null = null;
  public proxyManager: ProxyManager | null = null;
  public applicationContext: common.Context | null = null
  public uiAbility: UIAbility | null = null;

  constructor() {
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.uiAbility = binding.getAbility()
  }

  onDetachedFromAbility(): void {
    // Defensive: clear Ability-level reference. Any operations requiring
    // UIAbility context (e.g. openWithSystemBrowser) will safely fail
    // with a null check after this point.
    this.uiAbility = null;
    this.applicationContext = null;
  }

  getUniqueClassName(): string {
    return 'InAppWebViewFlutterPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    Log.d(TAG, 'onAttachedToEngine')
    this.messenger = binding.getBinaryMessenger()
    this.flutterAssets = binding.getFlutterAssets();
    this.inAppWebViewManager = new InAppWebViewManager( this );
    this.inAppBrowserManager = new InAppBrowserManager(this);
    this.flutterWebViewFactory = new FlutterWebViewFactory(this);
    this.messenger = binding.getBinaryMessenger();
    this.applicationContext = binding.getApplicationContext()
    binding.getPlatformViewRegistry()
      .registerViewFactory(FlutterWebViewFactory.VIEW_TYPE_ID, this.flutterWebViewFactory);

    this.headlessInAppWebViewManager = new HeadlessInAppWebViewManager(this);
    this.myCookieManager = new MyCookieManager(this)
    this.myWebStorage = new MyWebStorage(this);
    this.printJobManager = new PrintJobManager(this);
    this.credentialDatabaseHandler = new CredentialDatabaseHandler(this);
    this.webViewFeatureManager = new WebViewFeatureManager(this);
    this.processGlobalConfigManager = new ProcessGlobalConfigManager(this);
    this.proxyManager = new ProxyManager(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.printJobManager != null) {
      try {
        this.printJobManager.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: printJobManager dispose failed: ' + JSON.stringify(e));
      }
      this.printJobManager = null;
    }
    if (this.inAppWebViewManager != null) {
      try {
        this.inAppWebViewManager.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: inAppWebViewManager dispose failed: ' + JSON.stringify(e));
      }
      this.inAppWebViewManager = null;
    }
    if (this.inAppBrowserManager != null) {
      try {
        this.inAppBrowserManager.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: inAppBrowserManager dispose failed: ' + JSON.stringify(e));
      }
      this.inAppBrowserManager = null;
    }
    if (this.myCookieManager != null) {
      try {
        this.myCookieManager.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: myCookieManager dispose failed: ' + JSON.stringify(e));
      }
      this.myCookieManager = null;
    }
    if (this.myWebStorage != null) {
      try {
        this.myWebStorage.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: myWebStorage dispose failed: ' + JSON.stringify(e));
      }
      this.myWebStorage = null;
    }
    if (this.credentialDatabaseHandler != null) {
      try {
        this.credentialDatabaseHandler.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: credentialDatabaseHandler dispose failed: ' + JSON.stringify(e));
      }
      this.credentialDatabaseHandler = null;
    }
    if (this.webViewFeatureManager != null) {
      try {
        this.webViewFeatureManager.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: webViewFeatureManager dispose failed: ' + JSON.stringify(e));
      }
      this.webViewFeatureManager = null;
    }
    if (this.processGlobalConfigManager != null) {
      try {
        this.processGlobalConfigManager.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: processGlobalConfigManager dispose failed: ' + JSON.stringify(e));
      }
      this.processGlobalConfigManager = null;
    }
    if (this.proxyManager != null) {
      try {
        this.proxyManager.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: proxyManager dispose failed: ' + JSON.stringify(e));
      }
      this.proxyManager = null;
    }
    if (this.headlessInAppWebViewManager != null) {
      try {
        this.headlessInAppWebViewManager.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: headlessInAppWebViewManager dispose failed: ' + JSON.stringify(e));
      }
      this.headlessInAppWebViewManager = null;
    }
    if (this.flutterWebViewFactory != null) {
      try {
        this.flutterWebViewFactory.dispose();
      } catch (e) {
        Log.e(TAG, 'onDetachedFromEngine: flutterWebViewFactory dispose failed: ' + JSON.stringify(e));
      }
      this.flutterWebViewFactory = null;
    }
    this.messenger = null;
    this.flutterAssets = null;
    this.applicationContext = null;
    InAppBrowserManager.shared.clear();
    CredentialDatabase.resetInstance();
    ContentBlockerHttpUtil.clearCache();
  }
}