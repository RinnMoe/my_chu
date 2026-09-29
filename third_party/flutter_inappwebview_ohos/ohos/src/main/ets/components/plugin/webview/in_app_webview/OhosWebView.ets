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

import web_webview from '@ohos.web.webview'
import common from '@ohos.app.ability.common';
import { Log } from '@ohos/flutter_ohos'
import PullToRefreshSettings from '../../pull_to_refresh/PullToRefreshSettings';
import  PlatformView from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { FlutterWebView } from './FlutterWebView'
import InAppWebView from './InAppWebView'
import InAppWebViewClient from './InAppWebViewClient'
import EventConstant from '../../EventConstant'
import { JSON, List } from '@kit.ArkTS';
import { commonEventManager } from '@kit.BasicServicesKit';
import { WebNodeController, WebBuilderParams } from './WebNodeController'
import { BuilderNodeManager } from './BuilderNodeManager'

const TAG = "OhosWebView"
const REFRESH_INDICATOR_SIZE_DEFAULT = 32;
const REFRESH_INDICATOR_SIZE_LARGE = 48;

@Observed
export declare class Params {
  direction: Direction
  platformView: PlatformView
}

@Component
export struct OhosWebView {
  @ObjectLink params: Params;
  controller: web_webview.WebviewController | null = null
  schemeHandler: web_webview.WebSchemeHandler | null = new web_webview.WebSchemeHandler();
  shouldInterceptSchemeHandler: web_webview.WebSchemeHandler | null = new web_webview.WebSchemeHandler();
  static readonly schemeArray = [
    'snssdk1128',
    'sinaweibo',
    'xhsdiscover',
    'bilibili',
    'kwai',
    'weixin',
    'mqqapi',
    'alipays',
    'upwallet',
    'openapp.jdmobile',
    'imeituan',
    'pinduoduo',
    'tbopen',
    'amapuri',
    'wemeet'
  ];
  inAppWebView: InAppWebView | null = null
  @State isRefreshing: boolean = false
  @State isEnableRefresh: boolean = false
  @State refreshBackgroundColor: string = '#FFFFFF'
  @State refreshOffset: number = 64
  @State refreshIndicatorSize: number = REFRESH_INDICATOR_SIZE_DEFAULT
  @State refreshIndicatorColor: string = '#007AFF'
  @State startScripts: Array<ScriptItem> = [];
  @State cacheEnabled: boolean = true
  @State transparentBackground: boolean = false
  lastExecTime = 0;
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;
  private controllerAttached: boolean = false;
  private webNodeController: WebNodeController = new WebNodeController();
  private webComponentMounted: boolean = true;
  private keepAliveId: string | null = null;
  private isKeepAlive: boolean = false;

  /** Same references for on/off so listeners are removed and other WebViews' handlers stay registered. */
  private onEventHubPullRefreshing = (refreshing: boolean): void => {
    this.isRefreshing = refreshing;
  }
  private onEventHubPullAppearance = (settings: PullToRefreshSettings): void => {
    if (settings == null) {
      return;
    }
    if (settings.color != null && settings.color.length > 0) {
      this.refreshIndicatorColor = settings.color;
    }
    if (settings.backgroundColor != null && settings.backgroundColor.length > 0) {
      this.refreshBackgroundColor = settings.backgroundColor;
    }
    if (settings.distanceToTriggerSync != null && settings.distanceToTriggerSync > 0) {
      this.refreshOffset = settings.distanceToTriggerSync;
    }
    if (settings.size != null) {
      // PullToRefreshSize: 0=LARGE, 1=DEFAULT; mapped to indicator pixel size
      this.refreshIndicatorSize = settings.size === 0 ?
        REFRESH_INDICATOR_SIZE_LARGE : REFRESH_INDICATOR_SIZE_DEFAULT;
    }
  }
  private onEventHubUpdateStartScripts = (scripts: Array<ScriptItem>): void => {
    this.startScripts = scripts;
    this.updateWebNodeControllerParams();
  }
  private onEventHubUpdateCacheEnable = (enable: boolean): void => {
    this.cacheEnabled = enable;
    this.updateWebNodeControllerParams();
  }
  private onEventHubUpdateTransparentBackground = (enable: boolean): void => {
    this.transparentBackground = enable;
    this.updateWebNodeControllerParams();
  }

  private onEventHubUnmountWebComponent = (viewId: number): void => {
    if (this.inAppWebView != null && this.inAppWebView.id === viewId.toString()) {
      this.webComponentMounted = false;
      this.webNodeController.unmountWebComponent();
      if (this.isKeepAlive && this.keepAliveId != null &&
       this.inAppWebView.plugin?.inAppWebViewManager?.builderNodeManager != null) {
        this.inAppWebView.plugin.inAppWebViewManager.builderNodeManager.detachWebView(this.keepAliveId);
      }
    }
  }

  private onEventHubMountWebComponent = (viewId: number): void => {
    if (this.inAppWebView != null && this.inAppWebView.id === viewId.toString()) {
      this.webComponentMounted = true;
      this.webNodeController.mountWebComponent();
      if (this.isKeepAlive && this.keepAliveId != null &&
       this.inAppWebView.plugin?.inAppWebViewManager?.builderNodeManager != null) {
        this.inAppWebView.plugin.inAppWebViewManager.builderNodeManager.attachWebView(this.keepAliveId);
      }
    }
  }

  private getAliveClient(): InAppWebViewClient | null {
    if (this.inAppWebView == null || this.inAppWebView.isDisposed()) {
      return null;
    }
    return this.inAppWebView.inAppWebViewClient;
  }

  private updateWebNodeControllerParams(): void {
    if (this.inAppWebView == null || this.controller == null) {
      return;
    }
    this.webNodeController.updateParams(new WebBuilderParams(
      this.controller!,
      this.inAppWebView!,
      this.cacheEnabled,
      this.transparentBackground,
      this.startScripts,
      () => {
        this.controllerAttached = true;
        if (this.inAppWebView == null) {
          return;
        }
        this.setPathAllowingUniversalAccess();
        this.inAppWebView.onControllerAttached();
        this.setWebSchemeHandler();
      },
      (oldValue: Area, newValue: Area) => {
        if (this.inAppWebView != null && !this.inAppWebView.isDisposed() &&
         this.controllerAttached && this.controller != null) {
          this.inAppWebView.onAreaChange(oldValue, newValue);
        }
      },
      () => {
        return this.getAliveClient();
      },
      () => {
        this.setPathAllowingUniversalAccess();
      },
      () => {
        this.setWebSchemeHandler();
      }
    ));
  }

  aboutToAppear(): void {
    const flutterWebView = this.params.platformView as FlutterWebView;
    this.keepAliveId = flutterWebView != null ? flutterWebView.keepAliveId : null;
    this.isKeepAlive = this.keepAliveId != null;

    let builderNodeManager: BuilderNodeManager | null = null;
    if (this.inAppWebView != null && this.inAppWebView.plugin != null &&
     this.inAppWebView.plugin.inAppWebViewManager != null) {
      builderNodeManager = this.inAppWebView.plugin.inAppWebViewManager.builderNodeManager;
    }

    if (this.isKeepAlive && builderNodeManager != null) {
      let existingController = builderNodeManager.getWebNodeController(this.keepAliveId!);
      if (existingController != null) {
        this.webNodeController = existingController;
      }
    }

    this.isEnableRefresh = this.inAppWebView!.getPullToRefreshLayout().settings.enabled;
    this.applyPullToRefreshAppearance(this.inAppWebView!.getPullToRefreshLayout().settings);
    this.cacheEnabled = this.inAppWebView!.customSettings.cacheEnabled;
    this.transparentBackground = this.inAppWebView!.customSettings.transparentBackground;
    this.startScripts = this.inAppWebView!.getUserContentController()!.getStartScripts()
    this.webNodeController.initParams(new WebBuilderParams(
      this.controller!,
      this.inAppWebView!,
      this.cacheEnabled,
      this.transparentBackground,
      this.startScripts,
      () => {
        this.controllerAttached = true;
        if (this.inAppWebView == null) {
          return;
        }
        this.setPathAllowingUniversalAccess();
        this.inAppWebView.onControllerAttached();
        this.setWebSchemeHandler();
      },
      (oldValue: Area, newValue: Area) => {
        if (this.inAppWebView != null && !this.inAppWebView.isDisposed() &&
         this.controllerAttached && this.controller != null) {
          this.inAppWebView.onAreaChange(oldValue, newValue);
        }
      },
      () => {
        return this.getAliveClient();
      },
      () => {
        this.setPathAllowingUniversalAccess();
      },
      () => {
        this.setWebSchemeHandler();
      }
    ));

    if (this.isKeepAlive && builderNodeManager != null && !builderNodeManager.containsKey(this.keepAliveId!)) {
      builderNodeManager.register(
        this.keepAliveId!,
        this.webNodeController,
        this.controller!,
        this.inAppWebView!
      );
    }

    let context = getContext() as common.UIAbilityContext;
    context.eventHub.on(EventConstant.EVENT_PULL_SETREFRESHING, this.onEventHubPullRefreshing);
    context.eventHub.on(EventConstant.EVENT_PULL_UPDATE_APPEARANCE, this.onEventHubPullAppearance);
    context.eventHub.on(EventConstant.EVENT_UPDATE_STARTSCRIPTS, this.onEventHubUpdateStartScripts);
    context.eventHub.on(EventConstant.EVENT_UPDATE_CACHEENABLE, this.onEventHubUpdateCacheEnable);
    context.eventHub.on(EventConstant.EVENT_UPDATE_TRANSPARENT_BACKGROUND, this.onEventHubUpdateTransparentBackground);
    context.eventHub.on(EventConstant.EVENT_UNMOUNT_WEB_COMPONENT, this.onEventHubUnmountWebComponent);
    context.eventHub.on(EventConstant.EVENT_MOUNT_WEB_COMPONENT, this.onEventHubMountWebComponent);

    commonEventManager.createSubscriber(
      { events: ["usual.event.CLICK_STATUSBAR"] }, (err, subscriber) => {
      this.subscriber = subscriber
      if(subscriber !== null) {
        commonEventManager.subscribe(subscriber, (err, data) => {
          this.throttle(() => {
            if (this.webComponentMounted && this.controllerAttached && this.controller != null) {
              try {
                this.controller!.scrollTo(0, 0, 1000);
              } catch (e) {
                Log.e(TAG, "scrollTo error (controller may be detached): " + JSON.stringify(e));
                this.controllerAttached = false;
              }
            }
          }, 1000)
        })
      }
    });

    web_webview.WebviewController.setWebDebuggingAccess(this.inAppWebView!.isDebuggingEnabled());
  }

  throttle(func: Function, delay: number) {
    const currentTime = Date.now();
    if (currentTime - this.lastExecTime >= delay) {
      func();
      this.lastExecTime = currentTime;
    }
  }

  private releaseWebComponent(): void {
    if (this.controller != null) {
      try {
        this.controller!.clearWebSchemeHandler();
      } catch (e) {
        Log.e(TAG, "clearWebSchemeHandler error: " + JSON.stringify(e));
      }
    }
    if (this.inAppWebView != null && !this.inAppWebView.isDisposed()) {
      this.inAppWebView.releaseWebComponentResources();
      this.inAppWebView.dispose();
    }
  }

  aboutToDisappear(): void {
    let context = getContext() as common.UIAbilityContext;
    context.eventHub.off(EventConstant.EVENT_PULL_SETREFRESHING, this.onEventHubPullRefreshing);
    context.eventHub.off(EventConstant.EVENT_PULL_UPDATE_APPEARANCE, this.onEventHubPullAppearance);
    context.eventHub.off(EventConstant.EVENT_UPDATE_STARTSCRIPTS, this.onEventHubUpdateStartScripts);
    context.eventHub.off(EventConstant.EVENT_UPDATE_CACHEENABLE, this.onEventHubUpdateCacheEnable);
    context.eventHub.off(EventConstant.EVENT_UPDATE_TRANSPARENT_BACKGROUND, this.onEventHubUpdateTransparentBackground);
    context.eventHub.off(EventConstant.EVENT_UNMOUNT_WEB_COMPONENT, this.onEventHubUnmountWebComponent);
    context.eventHub.off(EventConstant.EVENT_MOUNT_WEB_COMPONENT, this.onEventHubMountWebComponent);
    this.webComponentMounted = false;
    this.controllerAttached = false;
    commonEventManager.unsubscribe(this.subscriber);
    this.subscriber = null;

    if (this.isKeepAlive) {
      this.webNodeController.unmountWebComponent();
    } else {
      this.webNodeController.dispose();
      this.releaseWebComponent();
    }

    this.startScripts = [];
    this.inAppWebView = null;
    this.controller = null;
    this.schemeHandler = null;
    this.shouldInterceptSchemeHandler = null;
  }

  private applyPullToRefreshAppearance(settings: PullToRefreshSettings): void {
    this.onEventHubPullAppearance(settings);
  }

  @Builder
  refreshLoadingBuilder() {
    Stack() {
      Row() {
        LoadingProgress()
          .color(this.refreshIndicatorColor)
          .width(this.refreshIndicatorSize)
          .height(this.refreshIndicatorSize)
      }
      .alignItems(VerticalAlign.Center)
    }
    .align(Alignment.Center)
    .clip(true)
    .constraintSize({ minHeight: 32 })
    .width('100%')
    .backgroundColor(this.refreshBackgroundColor)
  }

  build() {
    Column() {
      if (this.isEnableRefresh) {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.refreshLoadingBuilder() }) {
          NodeContainer(this.webNodeController)
        }
        .onStateChange((refreshStatus: RefreshStatus) => {
          Log.d(TAG, "Refresh onStatueChange state is " + refreshStatus)
        })
        .onRefreshing(() => {
          if (this.inAppWebView != null) {
            this.inAppWebView.getPullToRefreshLayout().onRefresh()
          }
        })
        .backgroundColor(this.refreshBackgroundColor)
        .refreshOffset(this.refreshOffset)
      } else {
        NodeContainer(this.webNodeController)
      }
    }
    .backgroundColor(this.transparentBackground ? Color.Transparent : Color.White)
  }

  /**
   * OHOS uses a path-whitelist via setPathAllowingUniversalAccess rather than
   * Android's three independent WebSettings APIs (fileAccess,
   * allowFileAccessFromFileURLs, allowUniversalAccessFromFileURLs). Any of
   * those flags being true enables the whitelist — a pragmatic OHOS adaptation.
   */
  private shouldAllowUniversalFileAccess(): boolean {
    const settings = this.inAppWebView!.customSettings;
    return settings.fileAccess ||
      settings.allowFileAccessFromFileURLs ||
      settings.allowUniversalAccessFromFileURLs;
  }

  private setPathAllowingUniversalAccess() {
    if (!this.shouldAllowUniversalFileAccess()) {
      return;
    }
    try {
      const context = getContext()
      const applicationContext = context.getApplicationContext()
      const cacheDirPath = `${context.cacheDir}/flutter`
      const filesDirPath = `${context.filesDir}/flutter`
      const resourceDirPath = this.getUIContext().getHostContext()?.resourceDir;
      const accessList = new List<string>()

      accessList.add(cacheDirPath)
      accessList.add(filesDirPath)

      if (applicationContext != null) {
        const appCacheDirPath = `${applicationContext.cacheDir}/flutter`
        const appFilesDirPath = `${applicationContext.filesDir}/flutter`
        accessList.add(appCacheDirPath)
        accessList.add(appFilesDirPath)
      } else {
        Log.w(TAG, "setPathAllowingUniversalAccess: applicationContext is null, skip app-level paths")
      }

      if (resourceDirPath) {
        accessList.add(resourceDirPath)
      }

      this.controller!.setPathAllowingUniversalAccess(accessList.convertToArray())
    } catch (error) {
      Log.e(TAG, "setPathAllowingUniversalAccess error: " + JSON.stringify(error))
    }
  }

  private setWebSchemeHandler() {
    if (this.schemeHandler == null || this.shouldInterceptSchemeHandler == null) {
      return;
    }
    this.schemeHandler.onRequestStart((request: web_webview.WebSchemeHandlerRequest,
      resourceHandler: web_webview.WebResourceHandler) => {
      return true;
    })
    for (let scheme of OhosWebView.schemeArray) {
      this.controller!.setWebSchemeHandler(scheme, this.schemeHandler);
    }

    this.shouldInterceptSchemeHandler.onRequestStart((
      request: web_webview.WebSchemeHandlerRequest,
      resourceHandler: web_webview.WebResourceHandler
    ) => {
      return this.getAliveClient()?.onSchemeHandlerInterceptRequest(request, resourceHandler) ?? false;
    });
    this.controller!.setWebSchemeHandler('https', this.shouldInterceptSchemeHandler);
    this.controller!.setWebSchemeHandler('http', this.shouldInterceptSchemeHandler);
  }
}

@Builder
export function buildOhosWebView(params: Params) {
  OhosWebView({
    params: params,
    controller: (params.platformView as FlutterWebView).getController(),
    inAppWebView: (params.platformView as FlutterWebView).getWebView()
  }).backgroundColor(Color.Transparent)
}

@Observed
export class HeadlessWebParams {
  direction: Direction = Direction.Ltr;
  platformView: PlatformView;
  width: Length;
  height: Length;

  constructor(platformView: PlatformView, width: Length, height: Length) {
    this.platformView = platformView;
    this.width = width;
    this.height = height;
  }
}

@Builder
export function buildHeadlessOhosWebView(params: HeadlessWebParams) {
  Column() {
    OhosWebView({
      params: params as Object as Params,
      controller: (params.platformView as FlutterWebView).getController(),
      inAppWebView: (params.platformView as FlutterWebView).getWebView()
    }).backgroundColor(Color.Transparent)
  }
  .width(params.width)
  .height(params.height)
  .clip(true)
  .visibility(Visibility.Hidden)
  .hitTestBehavior(HitTestMode.None)
}

@Observed
export class InAppBrowserWebParams {
  direction: Direction = Direction.Ltr;
  platformView: PlatformView;
  visible: boolean = true;

  constructor(platformView: PlatformView, visible: boolean) {
    this.platformView = platformView;
    this.visible = visible;
  }
}

@Builder
export function buildInAppBrowserOhosWebView(params: InAppBrowserWebParams) {
  Column() {
    OhosWebView({
      params: params as Object as Params,
      controller: (params.platformView as FlutterWebView).getController(),
      inAppWebView: (params.platformView as FlutterWebView).getWebView()
    })
  }
  .width('100%')
  .height('100%')
  .clip(true)
  .visibility(params.visible ? Visibility.Visible : Visibility.Hidden)
  .hitTestBehavior(params.visible ? HitTestMode.Default : HitTestMode.None)
}
