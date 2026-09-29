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

export default class ContentWorld {
  private name: string | null
  static PAGE: ContentWorld = new ContentWorld("page");
  public static DEFAULT_CLIENT: ContentWorld = new ContentWorld("defaultClient");

  constructor(name: string) {
    this.name = name;
  }

  public static world(name: string): ContentWorld {
    return new ContentWorld(name);
  }

  public static fromMap(map: Map<string, Any>): ContentWorld | null {
    if (map == null) {
      return null;
    }
    let name: string = map.get("name") as string;
    // assert this.name != null;
    return new ContentWorld(name);
  }

  public getName(): string {
    return this.name!;
  }

  public setName(name: string): void {
    this.name = name;
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;
    let that: ContentWorld = o as ContentWorld;
    return this.name == that.name
  }
}