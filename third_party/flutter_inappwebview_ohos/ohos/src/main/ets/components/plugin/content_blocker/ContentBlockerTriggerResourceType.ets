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

export enum ContentBlockerTriggerResourceType {
  DOCUMENT = "document",
  IMAGE = "image",
  STYLE_SHEET = "style-sheet",
  SCRIPT = "script",
  FONT = "font",
  SVG_DOCUMENT = "svg-document",
  MEDIA = "media",
  POPUP = "popup",
  RAW = "raw"
}

export function contentBlockerTriggerResourceTypeFromValue(value: string): ContentBlockerTriggerResourceType | null {
  const values = [
    ContentBlockerTriggerResourceType.DOCUMENT,
    ContentBlockerTriggerResourceType.IMAGE,
    ContentBlockerTriggerResourceType.STYLE_SHEET,
    ContentBlockerTriggerResourceType.SCRIPT,
    ContentBlockerTriggerResourceType.FONT,
    ContentBlockerTriggerResourceType.SVG_DOCUMENT,
    ContentBlockerTriggerResourceType.MEDIA,
    ContentBlockerTriggerResourceType.POPUP,
    ContentBlockerTriggerResourceType.RAW
  ];
  for (let type of values) {
    if (type === value) {
      return type;
    }
  }
  return null;
}

export function allContentBlockerTriggerResourceTypes(): ContentBlockerTriggerResourceType[] {
  return [
    ContentBlockerTriggerResourceType.DOCUMENT,
    ContentBlockerTriggerResourceType.IMAGE,
    ContentBlockerTriggerResourceType.STYLE_SHEET,
    ContentBlockerTriggerResourceType.SCRIPT,
    ContentBlockerTriggerResourceType.FONT,
    ContentBlockerTriggerResourceType.SVG_DOCUMENT,
    ContentBlockerTriggerResourceType.MEDIA,
    ContentBlockerTriggerResourceType.POPUP,
    ContentBlockerTriggerResourceType.RAW
  ];
}
