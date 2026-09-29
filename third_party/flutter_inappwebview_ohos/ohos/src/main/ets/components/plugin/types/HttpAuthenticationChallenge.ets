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
import URLAuthenticationChallenge from './URLAuthenticationChallenge';
import URLCredential from './URLCredential';
import URLProtectionSpace from './URLProtectionSpace';

export default class HttpAuthenticationChallenge extends URLAuthenticationChallenge {
  private previousFailureCount: number
  proposedCredential: URLCredential | null

  constructor(protectionSpace: URLProtectionSpace, previousFailureCount: number, proposedCredential: URLCredential | null) {
    super(protectionSpace)
    this.previousFailureCount = previousFailureCount
    this.proposedCredential = proposedCredential
  }

  public async toMap() {
    let challengeMap: Map<string, Any> = await super.toMap();
    challengeMap.set("previousFailureCount", this.previousFailureCount);
    challengeMap.set("proposedCredential", (this.proposedCredential != null) ? this.proposedCredential.toMap() : null);
    challengeMap.set("failureResponse", null);
    challengeMap.set("error", null);
    return challengeMap;
  }

  public getPreviousFailureCount(): number {
    return this.previousFailureCount;
  }

  public setPreviousFailureCount(previousFailureCount: number): void {
    this.previousFailureCount = previousFailureCount;
  }

  public getProposedCredential(): URLCredential | null {
    return this.proposedCredential;
  }

  public setProposedCredential(proposedCredential: URLCredential | null): void {
    this.proposedCredential = proposedCredential;
  }

  public toString(): string {
    return "HttpAuthenticationChallenge{" +
      "previousFailureCount=" + this.previousFailureCount +
      ", proposedCredential=" + this.proposedCredential +
      "} " + super.toString();
  }
}