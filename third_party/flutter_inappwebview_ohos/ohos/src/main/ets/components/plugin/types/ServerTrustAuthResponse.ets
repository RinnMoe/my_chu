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

export default class ServerTrustAuthResponse {
  private action: number

  constructor(action: number) {
    this.action = action
  }

  getAction(): number {
    return this.action;
  }

  public static fromMap(map: Map<string, Any>): ServerTrustAuthResponse | null {
    if (map == null) {
      return null;
    }
    let action: number = map.get("action") as number;
    return new ServerTrustAuthResponse(action);
  }
}