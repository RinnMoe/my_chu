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

import { Log } from '@ohos/flutter_ohos';
import web_webview from '@ohos.web.webview';
import InAppWebView from './InAppWebView';
import { WebBuilderParams, WebNodeController } from './WebNodeController';

const TAG = 'BuilderNodeManager'

export class WebViewNodeEntry {
  public webNodeController: WebNodeController | null = null;
  public webController: web_webview.WebviewController | null = null;
  public inAppWebView: InAppWebView | null = null;
  public isMounted: boolean = false;

  constructor(
    webNodeController: WebNodeController,
    webController: web_webview.WebviewController,
    inAppWebView: InAppWebView
  ) {
    this.webNodeController = webNodeController;
    this.webController = webController;
    this.inAppWebView = inAppWebView;
  }
}

export class BuilderNodeManager {
  private nodeMap: Map<string, WebViewNodeEntry> = new Map();

  public register(
    key: string,
    webNodeController: WebNodeController,
    webController: web_webview.WebviewController,
    inAppWebView: InAppWebView
  ): WebViewNodeEntry {
    let existing = this.nodeMap.get(key);
    if (existing != null) {
      existing.webNodeController = webNodeController;
      existing.webController = webController;
      existing.inAppWebView = inAppWebView;
      return existing;
    }

    let entry = new WebViewNodeEntry(webNodeController, webController, inAppWebView);
    this.nodeMap.set(key, entry);
    return entry;
  }

  public getWebNodeController(key: string): WebNodeController | null {
    let entry = this.nodeMap.get(key);
    return entry != null ? entry.webNodeController : null;
  }

  public getWebController(key: string): web_webview.WebviewController | null {
    let entry = this.nodeMap.get(key);
    return entry != null ? entry.webController : null;
  }

  public attachWebView(key: string): void {
    let entry = this.nodeMap.get(key);
    if (entry == null) {
      return;
    }
    if (entry.webNodeController != null) {
      entry.webNodeController.mountWebComponent();
      entry.isMounted = entry.webNodeController.isMounted();
    }
  }

  public detachWebView(key: string): void {
    let entry = this.nodeMap.get(key);
    if (entry == null) {
      return;
    }
    if (entry.webNodeController != null) {
      entry.webNodeController.unmountWebComponent();
      entry.isMounted = false;
    }
  }

  public updateParams(key: string, params: WebBuilderParams): void {
    let entry = this.nodeMap.get(key);
    if (entry == null) {
      return;
    }
    if (entry.webNodeController != null) {
      entry.webNodeController.updateParams(params);
    }
  }

  public removeWebViewNode(key: string): void {
    let entry = this.nodeMap.get(key);
    if (entry == null) {
      return;
    }

    if (entry.webNodeController != null) {
      entry.webNodeController.dispose();
    }

    this.nodeMap.delete(key);
  }

  public containsKey(key: string): boolean {
    return this.nodeMap.has(key);
  }

  public size(): number {
    return this.nodeMap.size;
  }

  public dispose(): void {
    this.nodeMap.forEach((entry: WebViewNodeEntry, _key: string) => {
      if (entry.webNodeController != null) {
        entry.webNodeController.dispose();
      }
    });
    this.nodeMap.clear();
  }
}
