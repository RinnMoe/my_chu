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

export default class SafeBrowsingResponse {
  private action: number;
  private report: boolean;

  constructor(report: boolean, action: number) {
    this.action = action
    this.report = report;
  }

  getAction(): number {
    return this.action;
  }

  isReport(): boolean {
    return this.report;
  }

  public static fromMap(map: Map<string, Any>): SafeBrowsingResponse | null {
    if (map == null) {
      return null;
    }
    let action: number = map.get("action") as number;
    let report: boolean = map.get("report") as boolean;
    return new SafeBrowsingResponse(report, action);
  }
}