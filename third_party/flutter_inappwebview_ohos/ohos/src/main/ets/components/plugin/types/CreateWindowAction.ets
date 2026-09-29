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

import { Any } from '@ohos/flutter_ohos';
import NavigationAction from './NavigationAction';
import URLRequest from './URLRequest';

export default class CreateWindowAction extends NavigationAction {
  windowId: number
  isDialog: boolean

  constructor(request: URLRequest, isForMainFrame: boolean, hasGesture: boolean, isRedirect: boolean, windowId: number, isDialog: boolean) {
    super(request, isForMainFrame, hasGesture, isRedirect)
    this.windowId = windowId
    this.isDialog = isDialog
  }

  public toMap(): Map<string, Any> {
    let createWindowActionMap: Map<string, Any> = super.toMap();
    createWindowActionMap.set("windowId", this.windowId);
    createWindowActionMap.set("isDialog", this.isDialog);
    createWindowActionMap.set("windowFeatures", null);
    return createWindowActionMap;
  }

  public getWindowId(): number {
    return this.windowId;
  }

  public setWindowId(windowId: number): void {
    this.windowId = windowId;
  }

  public getDialog(): boolean {
    return this.isDialog;
  }

  public setDialog(dialog: boolean): void {
    this.isDialog = dialog;
  }

  public toString(): string {
    return "CreateWindowAction{" +
      "windowId=" + this.windowId +
      ", isDialog=" + this.isDialog +
      ", request=" + this.request +
      ", isForMainFrame=" + this.isForMainFrame +
      ", hasGesture=" + this.hasGesture +
      ", isRedirect=" + this.isRedirect +
      '}';
  }
}