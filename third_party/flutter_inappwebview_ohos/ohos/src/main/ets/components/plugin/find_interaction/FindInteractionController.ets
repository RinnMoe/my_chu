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

import { MethodChannel } from '@ohos/flutter_ohos';

import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { Disposable } from '../types/Disposable';
import FindSession from '../types/FindSession';
import InAppWebViewInterface from '../webview/InAppWebViewInterface';
import { FindInteractionChannelDelegate } from './FindInteractionChannelDelegate';
import { FindInteractionSettings } from './FindInteractionSettings';

const LOG_TAG = "FindInteractionController";
const METHOD_CHANNEL_NAME_PREFIX = "com.pichillilorenzo/flutter_inappwebview_find_interaction_";

export class FindInteractionController implements Disposable {
  public webView: InAppWebViewInterface | null = null;
  public activeFindSession: FindSession | null = null;

  public channelDelegate: FindInteractionChannelDelegate | null = null;
  public settings: FindInteractionSettings | null = null;
  public searchText: string | null = null;

  constructor(webView: InAppWebViewInterface, plugin: InAppWebViewFlutterPlugin, id: string, settings: FindInteractionSettings | null) {
    this.webView = webView;
    this.settings = settings;
    let channel: MethodChannel = new MethodChannel(plugin.messenger!, METHOD_CHANNEL_NAME_PREFIX + id);
    this.channelDelegate = new FindInteractionChannelDelegate(this, channel);
  }

  public prepare(): void {

  }

  public findAll(find: string | null): void {
    if (find == null) {
      find = this.searchText;
    } else {
      // updated searchText
      this.searchText = find;
    }
    if (this.webView != null && find != null) {
      this.webView.findAllAsync(find);
    }
  }

  public findNext(forward: boolean): void {
    if (this.webView != null) {
      this.webView.findNext(forward);
    }
  }

  public clearMatches(): void {
    if (this.webView != null) {
      this.webView.clearMatches();
    }
  }

  dispose(): void {
    if(this.channelDelegate != null){
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    this.webView = null;
    this.activeFindSession = null;
    this.searchText = null;
  }
}