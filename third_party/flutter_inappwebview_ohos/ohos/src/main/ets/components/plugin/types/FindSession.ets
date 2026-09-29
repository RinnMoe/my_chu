/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
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

export default class FindSession {
  private resultCount: number;
  private highlightedResultIndex: number;
  private searchResultDisplayStyle: number = 2;

  constructor(resultCount: number, highlightedResultIndex: number) {
    this.resultCount = resultCount;
    this.highlightedResultIndex = highlightedResultIndex;
  }

  public toMap(): Map<string, Any> {
    let obj: Map<string, Any> = new Map<string, Any>();
    obj.set("resultCount", this.resultCount);
    obj.set("highlightedResultIndex", this.highlightedResultIndex);
    obj.set("searchResultDisplayStyle", this.searchResultDisplayStyle);
    return obj;
  }

  public getResultCount(): number {
    return this.resultCount;
  }

  public setResultCount(resultCount: number): void {
    this.resultCount = resultCount;
  }

  public getHighlightedResultIndex(): number {
    return this.highlightedResultIndex;
  }

  public setHighlightedResultIndex(highlightedResultIndex: number): void {
    this.highlightedResultIndex = highlightedResultIndex;
  }

  public getSearchResultDisplayStyle(): number {
    return this.searchResultDisplayStyle;
  }

  public setSearchResultDisplayStyle(searchResultDisplayStyle: number): void {
    this.searchResultDisplayStyle = searchResultDisplayStyle;
  }

  public toString(): string {
    return "FindSession{" +
      "resultCount=" + this.resultCount +
      ", highlightedResultIndex=" + this.highlightedResultIndex +
      ", searchResultDisplayStyle=" + this.searchResultDisplayStyle +
      '}';
  }
}
