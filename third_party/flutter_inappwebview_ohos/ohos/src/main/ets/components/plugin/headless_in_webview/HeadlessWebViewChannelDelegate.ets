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

import { MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import ChannelResultUtil from '../types/ChannelResultUtil';
import Size2D from '../types/Size2D';
import { HeadlessInAppWebView } from './HeadlessInAppWebView';

const LOG_TAG = 'HeadlessWebViewChannelDelegate'

export class HeadlessWebViewChannelDelegate extends ChannelDelegateImpl {
  private headlessInAppWebView: HeadlessInAppWebView | null = null;

  constructor(headlessInAppWebView: HeadlessInAppWebView, channel: MethodChannel) {
    super(channel);
    this.headlessInAppWebView = headlessInAppWebView;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'dispose':
          if (this.headlessInAppWebView != null) {
            this.headlessInAppWebView.dispose();
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case 'setSize':
          if (this.headlessInAppWebView != null) {
            let sizeMap = call.argument('size') as Map<string, number>;
            let size = Size2D.fromMap(sizeMap);
            if (size != null) {
              this.headlessInAppWebView.setSize(size);
            }
            result.success(true);
          } else {
            result.success(false);
          }
          break;
        case 'getSize':
          if (this.headlessInAppWebView != null) {
            let size = this.headlessInAppWebView.getSize();
            result.success(size != null ? size.toMap() : null);
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

  onWebViewCreated(): void {
    let channel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Object> = new Map<string, Object>();
    channel.invokeMethod('onWebViewCreated', obj);
  }

  dispose(): void {
    super.dispose();
    this.headlessInAppWebView = null;
  }
}
