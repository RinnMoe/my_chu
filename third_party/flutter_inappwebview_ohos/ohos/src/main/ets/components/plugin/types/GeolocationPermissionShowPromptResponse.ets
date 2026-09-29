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

export default class GeolocationPermissionShowPromptResponse {
  private origin: string
  allow: boolean
  retain: boolean

  constructor(origin: string, allow: boolean, retain: boolean) {
    this.origin = origin
    this.allow = allow
    this.retain = retain
  }

  public static fromMap(map: Map<string, Any>): GeolocationPermissionShowPromptResponse | null {
    if (map == null) {
      return null;
    }
    let origin: string = map.get("origin") as string;
    let allow: boolean = map.get("allow") as boolean;
    let retain: boolean = map.get("retain") as boolean;
    return new GeolocationPermissionShowPromptResponse(origin, allow, retain);
  }

  public getOrigin(): string {
    return this.origin;
  }

  public setOrigin(origin: string): void {
    this.origin = origin;
  }

  public isAllow(): boolean {
    return this.allow;
  }

  public setAllow(allow: boolean): void {
    this.allow = allow;
  }

  public isRetain(): boolean {
    return this.retain;
  }

  public setRetain(retain: boolean): void {
    this.retain = retain;
  }

  public toString(): string {
    return "GeolocationPermissionShowPromptResponse{" +
      "origin='" + this.origin + '\'' +
      ", allow=" + this.allow +
      ", retain=" + this.retain +
      '}';
  }
}