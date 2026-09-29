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

export default class URLCredential {
  private id: number | null
  private username: string | null
  private password: string | null
  private protectionSpaceId: number | null

  constructor(id: number | null, username: string | null, password: string | null, protectionSpaceId: number | null) {
    this.id = id
    this.username = username
    this.password = password
    this.protectionSpaceId = protectionSpaceId
  }

  public toMap(): Map<string, Any> {
    let urlCredentialMap: Map<string, Any> = new Map<string, Any>();
    urlCredentialMap.set("username", this.username);
    urlCredentialMap.set("password", this.password);
    urlCredentialMap.set("certificates", null);
    urlCredentialMap.set("persistence", null);
    return urlCredentialMap;
  }

  public getId(): number | null {
    return this.id;
  }

  public setId(id: number | null): void {
    this.id = id;
  }

  public getUsername(): string | null {
    return this.username;
  }

  public setUsername(username: string | null) {
    this.username = username;
  }

  public getPassword(): string | null {
    return this.password;
  }

  public setPassword(password: string | null): void {
    this.password = password;
  }

  public getProtectionSpaceId(): number | null {
    return this.protectionSpaceId;
  }

  public setProtectionSpaceId(protectionSpaceId: number | null): void {
    this.protectionSpaceId = protectionSpaceId;
  }

  public toString(): string {
    return "URLCredential{" +
      "username='" + this.username + '\'' +
      ", password='" + this.password + '\'' +
      '}';
  }
}