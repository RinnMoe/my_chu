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

import { Any, MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';

import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import ChannelResultUtil from '../types/ChannelResultUtil';
import FindSession from '../types/FindSession';
import { FindInteractionController } from './FindInteractionController';

const LOG_TAG = 'FindInteractionChannelDelegate'

export class FindInteractionChannelDelegate extends ChannelDelegateImpl {
  private findInteractionController: FindInteractionController | null = null;

  constructor(findInteractionController: FindInteractionController | null, channel: MethodChannel) {
    super(channel);
    this.findInteractionController = findInteractionController;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'findAll':
          if (this.findInteractionController != null) {
            let find: string = call.argument('find') as string;
            this.findInteractionController.findAll(find);
          }
          result.success(true);
          break;
        case 'findNext':
          if (this.findInteractionController != null) {
            let forward: boolean = call.argument('forward');
            this.findInteractionController.findNext(forward);
          }
          result.success(true);
          break;
        case 'clearMatches':
          if (this.findInteractionController != null) {
            this.findInteractionController.clearMatches();
          }
          result.success(true);
          break;
        case 'setSearchText':
          if (this.findInteractionController != null) {
            this.findInteractionController.searchText = call.argument('searchText');
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case 'getSearchText':
          if (this.findInteractionController != null) {
            result.success(this.findInteractionController.searchText);
          } else {
            result.success(false);
          }
          break;
        case 'getActiveFindSession':
          if (this.findInteractionController != null && this.findInteractionController.activeFindSession != null) {
            result.success(this.findInteractionController.activeFindSession.toMap());
          } else {
            result.success(null);
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

  public onFindResultReceived(activeMatchOrdinal: number, numberOfMatches: number, isDoneCounting: boolean): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;

    if (isDoneCounting && this.findInteractionController != null && this.findInteractionController.webView != null) {
      this.findInteractionController.activeFindSession = new FindSession(numberOfMatches, activeMatchOrdinal);
    }

    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set('activeMatchOrdinal', activeMatchOrdinal);
    obj.set('numberOfMatches', numberOfMatches);
    obj.set('isDoneCounting', isDoneCounting);
    channel.invokeMethod('onFindResultReceived', obj);
  }

  dispose(): void {
    super.dispose();
    this.findInteractionController = null;
  }
}
