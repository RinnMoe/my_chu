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

import { Any, Log } from '@ohos/flutter_ohos';
import ContentBlocker from './ContentBlocker';
import ContentBlockerTrigger from './ContentBlockerTrigger';
import ContentBlockerAction from './ContentBlockerAction';
import ContentBlockerHandler from './ContentBlockerHandler';

const TAG = "ContentBlockerUtil";

type StringAnyRecord = Record<string, Any>;
type ContentBlockerItemInput = Map<string, Map<string, Any>> | StringAnyRecord;
type ContentBlockerNestedInput = Map<string, Any> | StringAnyRecord | null | undefined;

export default class ContentBlockerUtil {
  static getMapValue(map: Map<string, Any>, key: string): Object | null | undefined {
    return map.get(key) as Object | null | undefined;
  }

  static getObjectValue(obj: StringAnyRecord, key: string): Object | null | undefined {
    return obj[key] as Object | null | undefined;
  }

  static objectToMap(obj: StringAnyRecord): Map<string, Any> {
    let map: Map<string, Any> = new Map<string, Any>();
    let keys: string[] = Object.keys(obj);
    for (let i: number = 0; i < keys.length; i++) {
      let key: string = keys[i];
      map.set(key, obj[key]);
    }
    return map;
  }

  static coerceToMap(value: ContentBlockerNestedInput): Map<string, Any> {
    let empty: Map<string, Any> = new Map<string, Any>();
    if (value == null || value === undefined) {
      return empty;
    }
    if (value instanceof Map) {
      return value as Map<string, Any>;
    }
    return ContentBlockerUtil.objectToMap(value as StringAnyRecord);
  }

  static coerceBlockerItem(item: ContentBlockerItemInput): Map<string, Any> {
    if (item instanceof Map) {
      let blockerMap: Map<string, Any> = new Map<string, Any>();
      let triggerNested: ContentBlockerNestedInput =
        (item as Map<string, Map<string, Any>>).get("trigger");
      let actionNested: ContentBlockerNestedInput =
        (item as Map<string, Map<string, Any>>).get("action");
      blockerMap.set("trigger", ContentBlockerUtil.coerceToMap(triggerNested));
      blockerMap.set("action", ContentBlockerUtil.coerceToMap(actionNested));
      return blockerMap;
    }
    let obj: StringAnyRecord = item as StringAnyRecord;
    let blockerMap: Map<string, Any> = new Map<string, Any>();
    let triggerRaw: Object | null | undefined = ContentBlockerUtil.getObjectValue(obj, "trigger");
    let actionRaw: Object | null | undefined = ContentBlockerUtil.getObjectValue(obj, "action");
    blockerMap.set("trigger",
      ContentBlockerUtil.coerceToMap(triggerRaw as ContentBlockerNestedInput));
    blockerMap.set("action",
      ContentBlockerUtil.coerceToMap(actionRaw as ContentBlockerNestedInput));
    return blockerMap;
  }

  static populateRuleList(
    handler: ContentBlockerHandler,
    contentBlockers: Array<Map<string, Map<string, Any>>> | null
  ): number {
    handler.getRuleList().clear();
    if (contentBlockers == null) {
      return 0;
    }

    let added: number = 0;
    for (let i: number = 0; i < contentBlockers.length; i++) {
      let rawItem: ContentBlockerItemInput = contentBlockers[i] as ContentBlockerItemInput;
      try {
        let blockerMap: Map<string, Any> = ContentBlockerUtil.coerceBlockerItem(rawItem);
        let triggerRaw: Object | null | undefined = ContentBlockerUtil.getMapValue(blockerMap, "trigger");
        let actionRaw: Object | null | undefined = ContentBlockerUtil.getMapValue(blockerMap, "action");
        let triggerMap: Map<string, Any> = ContentBlockerUtil.coerceToMap(
          triggerRaw as ContentBlockerNestedInput
        );
        let actionMap: Map<string, Any> = ContentBlockerUtil.coerceToMap(
          actionRaw as ContentBlockerNestedInput
        );
        let trigger: ContentBlockerTrigger = ContentBlockerTrigger.fromMap(triggerMap);
        let action: ContentBlockerAction = ContentBlockerAction.fromMap(actionMap);
        handler.getRuleList().add(new ContentBlocker(trigger, action));
        added++;
      } catch (e) {
        Log.e(TAG, "Failed to parse content blocker index " + i + ": " + e);
      }
    }
    Log.d(TAG, "populateRuleList added " + added + " rules");
    return added;
  }
}
