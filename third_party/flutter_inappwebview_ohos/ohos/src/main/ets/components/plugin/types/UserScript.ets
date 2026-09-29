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
import ContentWorld from './ContentWorld';
import { UserScriptInjectionTime } from './UserScriptInjectionTime';

export default class UserScript {
  private groupName: string;
  private source: string;
  private injectionTime: UserScriptInjectionTime;
  private contentWorld: ContentWorld;
  private allowedOriginRules: Set<string>;

  constructor(groupName: string, source: string, injectionTime: UserScriptInjectionTime, contentWorld: ContentWorld | null, allowedOriginRules: Set<string> | null) {
    this.groupName = groupName;
    this.source = source;
    this.injectionTime = injectionTime;
    this.contentWorld = contentWorld == null ? ContentWorld.PAGE : contentWorld;
    if (allowedOriginRules == null) {
      let set = new Set<string>();
      set.add("*")
      this.allowedOriginRules = set;
    } else {
      this.allowedOriginRules = allowedOriginRules;
    }
  }

  public static fromMap(map: Map<string, Any>): UserScript | null {
    if (map == null) {
      return null;
    }
    let groupName = map.get("groupName") as string;
    let source = map.get("source") as string;
    let injectionTime = map.get("injectionTime") as number;
    let contentWorld = ContentWorld.fromMap(map.get("contentWorld"));
    let rules: Array<string> = map.get("allowedOriginRules") as Array<string>;
    let allowedOriginRules = new Set<string>();
    for (let rulesElement of rules) {
      allowedOriginRules.add(rulesElement)
    }
    return new UserScript(groupName, source, injectionTime, contentWorld, allowedOriginRules);
  }

  getGroupName(): string {
    return this.groupName;
  }

  setGroupName(groupName: string) {
    this.groupName = groupName;
  }

  getSource(): string {
    return this.source;
  }

  setSource(source: string) {
    this.source = source;
  }

  getInjectionTime(): UserScriptInjectionTime {
    return this.injectionTime;
  }

  setInjectionTime(injectionTime: UserScriptInjectionTime) {
    this.injectionTime = injectionTime;
  }

  getContentWorld(): ContentWorld {
    return this.contentWorld;
  }

  setContentWorld(contentWorld: ContentWorld) {
    this.contentWorld = contentWorld == null ? ContentWorld.PAGE : contentWorld;
  }

  getAllowedOriginRules(): Set<string> {
    return this.allowedOriginRules;
  }

  getAllowedOriginRulesArray(): Array<string> {
    let rules = Array<string>()
    for (let valuesElement of this.allowedOriginRules.values()) {
      rules.push(valuesElement);
    }
    return rules;
  }

  setAllowedOriginRules(allowedOriginRules: Set<string>) {
    this.allowedOriginRules = allowedOriginRules;
  }

  equals(o: Object | null): boolean {
    if (this == o) return true;

    let that = o as UserScript;

    if (this.groupName != null ? !(this.groupName == that.groupName) : that.groupName != null)
      return false;
    if (!(this.source == that.source)) return false;
    if (this.injectionTime != that.injectionTime) return false;
    if (!this.contentWorld.equals(that.contentWorld)) return false;
    return this.checkSetEquals(this.allowedOriginRules, that.allowedOriginRules);
  }

  private checkSetEquals(rules: Set<string>, rules2: Set<string>): boolean {
    let isEquals = true
    rules.forEach(item => {
      isEquals = isEquals && rules2.has(item)
    })
    return isEquals;
  }
}