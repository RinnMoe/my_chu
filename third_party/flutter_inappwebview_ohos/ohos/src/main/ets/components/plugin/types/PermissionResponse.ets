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

import { List } from '@kit.ArkTS'
import { Any } from '@ohos/flutter_ohos'

export default class PermissionResponse{
  private resources: List<string>
  private action: number

  constructor(resources: List<string>, action: number) {
    this.resources = resources
    this.action = action
  }

  public static fromMap(map: Map<string, Any>): PermissionResponse | null {
    if (map == null) {
      return null;
    }
    let resources: List<string> = map.get("resources") as List<string>;
    let action: number = map.get("action") as number;
    return new PermissionResponse(resources, action);
  }

  public getResources(): List<string> {
    return this.resources;
  }

  public setResources(resources: List<string>): void {
    this.resources = resources;
  }

  public getAction(): number {
    return this.action;
  }

  public setAction(action: number): void {
    this.action = action;
  }

  public toString(): string {
    return "PermissionResponse{" +
      "resources=" + this.resources +
      ", action=" + this.action +
      '}';
  }
}