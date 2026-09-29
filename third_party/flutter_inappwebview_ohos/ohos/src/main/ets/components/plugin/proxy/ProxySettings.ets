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
import ProxyRuleExt from './ProxyRuleExt';

export default class ProxySettings implements ISettings<Object> {
  public bypassRules: string[] = [];
  public directs: string[] = [];
  public proxyRules: ProxyRuleExt[] = [];
  public bypassSimpleHostnames: boolean | null = null;
  public removeImplicitRules: boolean | null = null;
  public reverseBypassEnabled: boolean = false;

  public parse(settings: Map<string, Any> | Object): ISettings<Object> {
    if (settings instanceof Map) {
      let keys: IterableIterator<string> = settings.keys();
      for (let key of keys) {
        let value: Object = settings.get(key) as Object;
        if (value == null) {
          continue;
        }
        this._parseKeyValue(key, value);
      }
    } else {
      let obj = settings as Record<string, Object>;
      let keys: string[] = Object.keys(obj);
      for (let i = 0; i < keys.length; i++) {
        let key: string = keys[i];
        let value: Object | undefined = obj[key];
        if (value == null || value == undefined) {
          continue;
        }
        this._parseKeyValue(key, value);
      }
    }
    return this;
  }

  private _parseKeyValue(key: string, value: Object): void {
    switch (key) {
      case 'bypassRules':
        this.bypassRules = value as string[];
        break;
      case 'directs':
        this.directs = value as string[];
        break;
      case 'proxyRules':
        this.proxyRules = [];
        let ruleList = value as Object[];
        for (let i = 0; i < ruleList.length; i++) {
          let rule = ProxyRuleExt.fromMap(ruleList[i] as Map<string, Object>);
          if (rule != null) {
            this.proxyRules.push(rule);
          }
        }
        break;
      case 'bypassSimpleHostnames':
        this.bypassSimpleHostnames = value as boolean;
        break;
      case 'removeImplicitRules':
        this.removeImplicitRules = value as boolean;
        break;
      case 'reverseBypassEnabled':
        this.reverseBypassEnabled = value as boolean;
        break;
      default:
        break;
    }
  }

  public toMap(): Map<string, Any> {
    let settings: Map<string, Any> = new Map<string, Any>();
    settings.set('bypassRules', this.bypassRules);
    settings.set('directs', this.directs);
    settings.set('proxyRules', this.proxyRules);
    settings.set('bypassSimpleHostnames', this.bypassSimpleHostnames);
    settings.set('removeImplicitRules', this.removeImplicitRules);
    settings.set('reverseBypassEnabled', this.reverseBypassEnabled);
    return settings;
  }

  public getRealSettings(_realObj: Object): Map<string, Any> {
    return this.toMap();
  }
}
