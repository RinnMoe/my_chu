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

export default class WebMessagePortCompatExt {
  private index: number | null = null

  private webMessageChannelId: string | null = null

  constructor(index: number, webMessageChannelId: string) {
    this.index = index
    this.webMessageChannelId = webMessageChannelId
  }

  public static fromMap(map: Map<string, Any>): WebMessagePortCompatExt | null {
    if (map == null) {
      return null;
    }
    let index: number = map.get("index") as number;
    let webMessageChannelId: string = map.get("webMessageChannelId") as string;
    return new WebMessagePortCompatExt(index, webMessageChannelId);
  }

  public toMap(): Map<string, Any> {
    let proxyRuleMap: Map<string, Any> = new Map<string, Any>()
    proxyRuleMap.set("index", this.index);
    proxyRuleMap.set("webMessageChannelId", this.webMessageChannelId);
    return proxyRuleMap;
  }

  public getIndex(): number { return this.index!; }

  public setIndex(index: number): void { this.index = index; }

  public getWebMessageChannelId(): string { return this.webMessageChannelId!; }

  public setWebMessageChannelId(webMessageChannelId: string): void {
    this.webMessageChannelId = webMessageChannelId;
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;

    let that: WebMessagePortCompatExt = o as WebMessagePortCompatExt;

    if (this.index != that.index) return false;
    return this.webMessageChannelId != that.webMessageChannelId;
  }

  public hashCode(): number {
    let result: number = this.index!;
    // result = 31 * result + this.webMessageChannelId!.hashCode();
    return result;
  }

  public toString(): string {
    return "WebMessagePortCompatExt{" +
      "index=" + this.index +
      ", webMessageChannelId='" + this.webMessageChannelId + '\'' +
      '}';
  }
}