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

export default class ProxyRuleExt {
  schemeFilter: string | null = null;
  url: string = '';

  static fromMap(map: Map<string, Object> | Object | null | undefined): ProxyRuleExt | null {
    if (map == null || map == undefined) {
      return null;
    }
    let rule = new ProxyRuleExt();
    if (map instanceof Map) {
      rule.schemeFilter = map.get('schemeFilter') as string | null;
      rule.url = map.get('url') as string;
    } else {
      let obj = map as Record<string, Object>;
      rule.schemeFilter = obj['schemeFilter'] as string | null;
      rule.url = obj['url'] as string;
    }
    if (rule.url == null || rule.url.length === 0) {
      return null;
    }
    return rule;
  }
}
