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

import { Any, MethodChannel } from '@ohos/flutter_ohos';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import InAppBrowserMenuItem from '../types/InAppBrowserMenuItem';

export default class InAppBrowserChannelDelegate extends ChannelDelegateImpl {

  constructor(channel: MethodChannel) {
    super(channel)
  }

  public onBrowserCreated(): void {
    let channel: MethodChannel = this.getChannel()
    if(channel == null) return
    let obj: Map<string, Any> = new Map<string, Any>()
    channel.invokeMethod("onBrowserCreated", obj)
  }

  public onMenuItemClicked(menuItem: InAppBrowserMenuItem): void {
    let channel: MethodChannel = this.getChannel()
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set("id", menuItem.getId());
    channel.invokeMethod("onMenuItemClicked", obj);
  }

  public onExit(): void {
    let channel: MethodChannel = this.getChannel();
    if (channel == null) return;
    let obj: Map<string, Any> = new Map<string, Any>();
    channel.invokeMethod("onExit", obj);
  }
}