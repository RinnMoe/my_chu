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

import { Any } from '@ohos/flutter_ohos'
import URLRequest from './URLRequest'

export default class NavigationAction {
  request: URLRequest
  isForMainFrame: boolean
  hasGesture: boolean
  isRedirect: boolean

  constructor(request: URLRequest, isForMainFrame: boolean, hasGesture: boolean, isRedirect: boolean) {
    this.request = request
    this.isForMainFrame = isForMainFrame
    this.hasGesture = hasGesture
    this.isRedirect = isRedirect
  }

  public toMap(): Map<string, Any> {
    let navigationActionMap: Map<string, Any> = new Map<string, Any>();
    navigationActionMap.set("request", this.request.toMap());
    navigationActionMap.set("isForMainFrame", this.isForMainFrame);
    navigationActionMap.set("hasGesture", this.hasGesture);
    navigationActionMap.set("isRedirect", this.isRedirect);
    navigationActionMap.set("navigationType", null);
    navigationActionMap.set("sourceFrame", null);
    navigationActionMap.set("targetFrame", null);
    navigationActionMap.set("shouldPerformDownload", null);
    return navigationActionMap;
  }

  public getRequest(): URLRequest {
    return this.request;
  }

  public setRequest(request: URLRequest): void {
    this.request = request;
  }

  public getForMainFrame(): boolean {
    return this.isForMainFrame;
  }

  public setForMainFrame(forMainFrame: boolean): void {
    this.isForMainFrame = forMainFrame;
  }

  public isHasGesture(): boolean {
    return this.hasGesture;
  }

  public setHasGesture(hasGesture: boolean): void {
    this.hasGesture = hasGesture;
  }

  public getRedirect(): boolean {
    return this.isRedirect;
  }

  public setRedirect(redirect: boolean): void {
    this.isRedirect = redirect;
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;

    let that: NavigationAction = o as NavigationAction;

    if (this.isForMainFrame != that.isForMainFrame) return false;
    if (this.hasGesture != that.hasGesture) return false;
    if (this.isRedirect != that.isRedirect) return false;
    return this.request == that.request;
  }

  public toString(): string {
    return "NavigationAction{" +
      "request=" + this.request +
      ", isForMainFrame=" + this.isForMainFrame +
      ", hasGesture=" + this.hasGesture +
      ", isRedirect=" + this.isRedirect +
      '}';
  }
}