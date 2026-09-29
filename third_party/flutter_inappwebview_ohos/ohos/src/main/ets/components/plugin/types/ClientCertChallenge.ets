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
import URLProtectionSpace from './URLProtectionSpace';

export default class ClientCertChallenge extends URLAuthenticationChallenge {
  private principals: Array<string> | null;
  private keyTypes: Array<string> | null;

  constructor(protectionSpace: URLProtectionSpace, principals: Array<string> | null, keyTypes: Array<string> | null) {
    super(protectionSpace);
    this.principals = principals;
    this.keyTypes = keyTypes;
  }

  public async toMap() {
    let challengeMap: Map<string, Any> = new Map<string, Any>();
    challengeMap.set('protectionSpace', await this.getProtectionSpace().toMap());
    challengeMap.set('principals', this.principals ? this.principals : null);
    challengeMap.set('keyTypes', this.keyTypes != null ? this.keyTypes : null);
    return challengeMap;
  }

  /** Synchronous map for callbacks that must block the WebView network thread. */
  public toSyncMap(): Map<string, Any> {
    let challengeMap: Map<string, Any> = new Map<string, Any>();
    challengeMap.set('protectionSpace', this.getProtectionSpace().toSyncMap());
    challengeMap.set('principals', this.principals ? this.principals : null);
    challengeMap.set('keyTypes', this.keyTypes != null ? this.keyTypes : null);
    return challengeMap;
  }

  public getPrincipals(): Array<string> | null {
    return this.principals;
  }

  public setPrincipals(principals: Array<string> | null): void {
    this.principals = principals;
  }

  public getKeyTypes(): Array<string> | null {
    return this.keyTypes;
  }

  public setKeyTypes(keyTypes: Array<string> | null): void {
    this.keyTypes = keyTypes;
  }
}