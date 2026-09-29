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
import ISettings from '../ISettings';
import PullToRefreshLayout from './PullToRefreshLayout';

export default class PullToRefreshSettings implements ISettings<PullToRefreshLayout> {
  static LOG_TAG: string = "PullToRefreshSettings";

  enabled: boolean = true;
  color: string | null = null;

  backgroundColor: string | null = null;
  distanceToTriggerSync: number | null = null;

  slingshotDistance: number | null = null;
  size: number | null = null;

  public parse(settings: Map<string, Any>): PullToRefreshSettings {
    let keys = settings.keys();
    for(let key of keys) {
      if(key == null) {
        continue;
      }

      switch (key) {
        case "enabled":
          this.enabled = settings.get(key) as boolean;
          break;
        case "color":
          this.color = settings.get(key) as string;
          break;
        case "backgroundColor":
          this.backgroundColor = settings.get(key)as string;
          break;
        case "distanceToTriggerSync":
          this.distanceToTriggerSync = settings.get(key) as number;
          break;
        case "slingshotDistance":
          this.slingshotDistance = settings.get(key) as number;
          break;
        case "size":
          this.size = settings.get(key) as number;
          break;
      }
    }
    return this;
  }

  public toMap() {
    let settings: Map<string, Any> = new Map<string, Object>();
    settings.set("enabled", this.enabled);
    settings.set("color", this.color!);
    settings.set("backgroundColor", this.backgroundColor!);
    settings.set("distanceToTriggerSync", this.distanceToTriggerSync!);
    settings.set("slingshotDistance", this.slingshotDistance!);
    settings.set("size", this.size!);
    return settings;
  }

  public getRealSettings(pullToRefreshLayout: PullToRefreshLayout) {
    let realSettings: Map<string, Any> = this.toMap();
    return realSettings;
  }
}