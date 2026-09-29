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
import {
  allContentBlockerTriggerResourceTypes,
  contentBlockerTriggerResourceTypeFromValue,
  ContentBlockerTriggerResourceType
} from './ContentBlockerTriggerResourceType';
import ContentBlockerUtil from './ContentBlockerUtil';

export default class ContentBlockerTrigger {
  private urlFilter: string;
  private urlFilterPatternCompiled: RegExp;
  private urlFilterIsCaseSensitive: boolean;
  private resourceType: ContentBlockerTriggerResourceType[] = [];
  private ifDomain: string[] = [];
  private unlessDomain: string[] = [];
  private loadType: string[] = [];
  private ifTopUrl: string[] = [];
  private unlessTopUrl: string[] = [];

  constructor(
    urlFilter: string,
    urlFilterIsCaseSensitive: boolean,
    resourceType: ContentBlockerTriggerResourceType[],
    ifDomain: string[],
    unlessDomain: string[],
    loadType: string[],
    ifTopUrl: string[],
    unlessTopUrl: string[]
  ) {
    this.urlFilter = urlFilter;
    this.urlFilterIsCaseSensitive = urlFilterIsCaseSensitive;
    this.urlFilterPatternCompiled = new RegExp(urlFilter, urlFilterIsCaseSensitive ? '' : 'i');
    this.resourceType = resourceType;
    this.ifDomain = ifDomain;
    this.unlessDomain = unlessDomain;
    this.loadType = loadType;
    this.ifTopUrl = ifTopUrl;
    this.unlessTopUrl = unlessTopUrl;
  }

  getUrlFilterPatternCompiled(): RegExp {
    return this.urlFilterPatternCompiled;
  }

  getResourceType(): ContentBlockerTriggerResourceType[] {
    return this.resourceType;
  }

  getIfDomain(): string[] {
    return this.ifDomain;
  }

  getUnlessDomain(): string[] {
    return this.unlessDomain;
  }

  getLoadType(): string[] {
    return this.loadType;
  }

  getIfTopUrl(): string[] {
    return this.ifTopUrl;
  }

  getUnlessTopUrl(): string[] {
    return this.unlessTopUrl;
  }

  private static getStringList(map: Map<string, Any>, key: string): string[] {
    const raw: Object | null | undefined = ContentBlockerUtil.getMapValue(map, key);
    if (raw === null || raw === undefined) {
      return [];
    }
    if (Array.isArray(raw)) {
      const list = raw as string[];
      return list;
    }
    return [];
  }

  static fromMap(map: Map<string, Any>): ContentBlockerTrigger {
    let urlFilter = ContentBlockerUtil.getMapValue(map, "url-filter") as string;
    let urlFilterIsCaseSensitive = ContentBlockerUtil.getMapValue(map, "url-filter-is-case-sensitive") as boolean;
    if (urlFilterIsCaseSensitive == null) {
      urlFilterIsCaseSensitive = false;
    }

    let resourceType: ContentBlockerTriggerResourceType[] = [];
    let resourceTypeStringList = ContentBlockerTrigger.getStringList(map, "resource-type");
    if (resourceTypeStringList.length > 0) {
      for (let i = 0; i < resourceTypeStringList.length; i++) {
        let typeValue: string = resourceTypeStringList[i];
        let type = contentBlockerTriggerResourceTypeFromValue(typeValue);
        if (type != null) {
          resourceType.push(type);
        }
      }
    } else {
      resourceType = allContentBlockerTriggerResourceTypes();
    }

    let ifDomain = ContentBlockerTrigger.getStringList(map, "if-domain");
    let unlessDomain = ContentBlockerTrigger.getStringList(map, "unless-domain");
    let loadType = ContentBlockerTrigger.getStringList(map, "load-type");
    let ifTopUrl = ContentBlockerTrigger.getStringList(map, "if-top-url");
    let unlessTopUrl = ContentBlockerTrigger.getStringList(map, "unless-top-url");

    return new ContentBlockerTrigger(
      urlFilter,
      urlFilterIsCaseSensitive,
      resourceType,
      ifDomain,
      unlessDomain,
      loadType,
      ifTopUrl,
      unlessTopUrl
    );
  }
}
