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

export default class HttpAuthResponse {
  private username: string
  private password: string
  permanentPersistence: boolean
  private action: number | null

  constructor(username: string, password: string, permanentPersistence: boolean, action: number | null) {
    this.username = username
    this.password = password
    this.permanentPersistence = permanentPersistence
    this.action = action
  }

  public static fromMap(map: Map<string, Any>): HttpAuthResponse | null {
    if (map == null) {
      return null;
    }
    let username: string = map.get("username") as string;
    let password: string = map.get("password") as string;
    let permanentPersistence: boolean = map.get("permanentPersistence") as boolean;
    let action: number = map.get("action") as number;
    return new HttpAuthResponse(username, password, permanentPersistence, action);
  }

  public getUsername(): string {
    return this.username;
  }

  public setUsername(username: string): void {
    this.username = username;
  }

  public getPassword(): string {
    return this.password;
  }

  public setPassword(password: string): void {
    this.password = password;
  }

  public isPermanentPersistence(): boolean {
    return this.permanentPersistence;
  }

  public setPermanentPersistence(permanentPersistence: boolean): void {
    this.permanentPersistence = permanentPersistence;
  }

  public getAction(): number | null {
    return this.action;
  }

  public setAction(action: number | null): void {
    this.action = action;
  }

  public toString(): string {
    return "HttpAuthResponse{" +
      "username='" + this.username + '\'' +
      ", password='" + this.password + '\'' +
      ", permanentPersistence=" + this.permanentPersistence +
      ", action=" + this.action +
      '}';
  }
}