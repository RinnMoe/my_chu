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

import { Any, Log, MethodChannel } from '@ohos/flutter_ohos';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import BaseCallbackResultImpl from './BaseCallbackResultImpl';
import ChannelDelegateImpl from './ChannelDelegateImpl';
import { Disposable } from './Disposable';
import SyncBaseCallbackResultImpl from './SyncBaseCallbackResultImpl';
import WebResourceResponseExt from './WebResourceResponseExt';
import WebViewAssetLoader, {
  AssetsPathHandler,
  InternalStoragePathHandler,
  PathHandler,
  ResourcesPathHandler,
  WebViewAssetLoaderBuilder
} from './WebViewAssetLoader';

const TAG = "WebViewAssetLoaderExt";

export default class WebViewAssetLoaderExt implements Disposable {
  public loader: WebViewAssetLoader;
  public customPathHandlers: Array<PathHandlerExt>;

  constructor(loader: WebViewAssetLoader, customPathHandlers: Array<PathHandlerExt>) {
    this.loader = loader;
    this.customPathHandlers = customPathHandlers;
  }

  /**
   * Default loader for [InAppWebView.loadFile]: serves Flutter rawfile assets at
   * https://appassets.androidplatform.net/assets/flutter_assets/{assetFilePath}
   */
  static createDefaultFlutterAssetsLoader(context: Context): WebViewAssetLoaderExt {
    let builder = new WebViewAssetLoaderBuilder();
    builder.addPathHandler("/assets/", new AssetsPathHandler(context));
    return new WebViewAssetLoaderExt(builder.build(), new Array<PathHandlerExt>());
  }

  static fromMap(map: Map<string, Any> | null, plugin: InAppWebViewFlutterPlugin,
    context: Context): WebViewAssetLoaderExt | null {
    if (map == null) {
      return null;
    }
    let builder = new WebViewAssetLoaderBuilder();
    let domain: string | null = map.get("domain");
    let httpAllowed: boolean | null = map.get("httpAllowed");
    let pathHandlers: Array<Map<string, Any>> | null = map.get("pathHandlers");
    let customPathHandlers = new Array<PathHandlerExt>();
    if (domain != null && domain.length > 0) {
      builder.setDomain(domain);
    }
    if (httpAllowed != null) {
      builder.setHttpAllowed(httpAllowed);
    }
    if (pathHandlers != null) {
      pathHandlers!!.forEach((pathHandler: Map<string, Any>) => {
        let type: string | null = pathHandler.get("type");
        let path: string | null = pathHandler.get("path");
        if (type != null && path != null) {
          switch (type) {
            case "AssetsPathHandler":
              let assetsPathHandler = new AssetsPathHandler(context);
              builder.addPathHandler(path, assetsPathHandler);
              break;
            case "InternalStoragePathHandler":
              let directory: string = pathHandler.get("directory");
              if (directory != null) {
                let internalStoragePathHandler = new InternalStoragePathHandler(context, directory);
                builder.addPathHandler(path, internalStoragePathHandler);
              }
              break;
            case "ResourcesPathHandler":
              let resourcesPathHandler = new ResourcesPathHandler(context);
              builder.addPathHandler(path, resourcesPathHandler);
              break;
            default:
              let id: string | null = pathHandler.get("id");
              if (id != null) {
                let customPathHandler = new PathHandlerExt(id, plugin);
                builder.addPathHandler(path, customPathHandler);
                customPathHandlers.push(customPathHandler);
              }
              break;
          }
        }
      })
    }
    return new WebViewAssetLoaderExt(builder.build(), customPathHandlers);
  }

  dispose(): void {
    for (let pathHandler of this.customPathHandlers) {
      pathHandler.dispose();
    }
    this.customPathHandlers = [];
  }
}

class PathHandlerExt implements PathHandler, Disposable {
  protected staticLOG_TAG = "PathHandlerExt";
  public static METHOD_CHANNEL_NAME_PREFIX = "com.pichillilorenzo/flutter_inappwebview_custompathhandler_";
  public id: string;
  public channelDelegate: PathHandlerExtChannelDelegate | null;

  constructor(id: string, plugin: InAppWebViewFlutterPlugin) {
    this.id = id;
    let channel = new MethodChannel(plugin.messenger!, PathHandlerExt.METHOD_CHANNEL_NAME_PREFIX + id);
    this.channelDelegate = new PathHandlerExtChannelDelegate(this, channel);
  }

  handle(path: string): WebResourceResponse {
    let webResourceResponse = new WebResourceResponse()
    if (this.channelDelegate != null) {
      try {
        this.channelDelegate.handleSync(path).then(response => {
          if (response != null) {
            webResourceResponse.setResponseMimeType(response!.getContentType())
            webResourceResponse.setResponseEncoding(response!.getContentEncoding())
            webResourceResponse.setResponseCode(response!.getStatusCode())
            webResourceResponse.setReasonMessage(response!.getReasonPhrase())
            webResourceResponse.setResponseData(response!.getData())
            webResourceResponse.setResponseIsReady(true);
          } else {
            webResourceResponse.setResponseIsReady(false)
          }
        })
      } catch (e) {
        webResourceResponse.setResponseIsReady(false)
      }
    }
    return webResourceResponse;
  }

  dispose(): void {
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
  }
}

class PathHandlerExtChannelDelegate extends ChannelDelegateImpl {
  private pathHandler: PathHandlerExt | null;

  constructor(pathHandler: PathHandlerExt, channel: MethodChannel) {
    super(channel);
    this.pathHandler = pathHandler;
  }

  handle(path: string, callback: HandleCallback): void {
    let channel = this.getChannel();
    if (channel == null) {
      return;
    }
    let obj: Map<String, Any> = new Map<String, Any>();
    obj.set("path", path);
    channel.invokeMethod("handle", obj, callback);
  }

  async handleSync(path: string) {
    let channel = this.getChannel();
    if (channel == null) {
      return null;
    }
    let callback = new SyncHandleCallback();
    let obj: Map<String, Any> = new Map<String, Any>();
    obj.set("path", path);
    channel.invokeMethod("handle", obj, callback);
    if (!await callback.waitResponseWithTimeout(500)) {
      return null;
    }
    return callback.result;
  }

  dispose(): void {
    super.dispose();
    this.pathHandler = null;
  }
}

class HandleCallback extends BaseCallbackResultImpl<WebResourceResponseExt> {
  public decodeResult(obj: Object | null): WebResourceResponseExt | null {
    return WebResourceResponseExt.fromMap(obj as Map<string, Any>);
  }
}

class SyncHandleCallback extends SyncBaseCallbackResultImpl<WebResourceResponseExt> {
  decodeResult(obj: Object | null): WebResourceResponseExt | null {
    return (new HandleCallback()).decodeResult(obj);
  }
}