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
import URLProtectionSpace from './URLProtectionSpace'

export default class URLAuthenticationChallenge {
  private protectionSpace: URLProtectionSpace

  constructor(protectionSpace: URLProtectionSpace) {
    this.protectionSpace = protectionSpace
  }

  public async toMap() {
    let challengeMap: Map<string, Any> = new Map<string, Any>();
    challengeMap.set("protectionSpace", await this.protectionSpace.toMap());
    return challengeMap;
  }

  public getProtectionSpace(): URLProtectionSpace {
    return this.protectionSpace;
  }

  public setProtectionSpace(protectionSpace: URLProtectionSpace): void {
    this.protectionSpace = protectionSpace;
  }

  public toString(): string {
    return "URLAuthenticationChallenge{" +
      "protectionSpace=" + this.protectionSpace +
      '}';
  }
}