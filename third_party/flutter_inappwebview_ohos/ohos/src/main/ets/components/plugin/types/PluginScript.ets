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

import ContentWorld from './ContentWorld';
import UserScript from './UserScript';
import { UserScriptInjectionTime } from './UserScriptInjectionTime';

export default class PluginScript extends UserScript {
  private requiredInAllContentWorlds: boolean;

  constructor(groupName: string, source: string, injectionTime: UserScriptInjectionTime,
              contentWorld: ContentWorld | null, requiredInAllContentWorlds: boolean, allowedOriginRules: Set<string> | null) {
    super(groupName, source, injectionTime, contentWorld, allowedOriginRules);
    this.requiredInAllContentWorlds = requiredInAllContentWorlds;
  }

  public isRequiredInAllContentWorlds(): boolean { return this.requiredInAllContentWorlds }

  public setRequiredInAllContentWorlds(requiredInAllContentWorlds: boolean): void {
    this.requiredInAllContentWorlds = requiredInAllContentWorlds;
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;
    if (!super.equals(o)) return false;

    let that: PluginScript = o as PluginScript;

    return this.requiredInAllContentWorlds == that.requiredInAllContentWorlds;
  }

  public hashCode(): number {
    // let result: number = super.hashCode();
    // result = 31 * result + (this.requiredInAllContentWorlds ? 1 : 0);
    // return result;
    return 0;
  }

  public toString() {
    return "PluginScript{" +
      "requiredInContentWorld=" + this.requiredInAllContentWorlds +
      "} " + super.toString();
  }
}