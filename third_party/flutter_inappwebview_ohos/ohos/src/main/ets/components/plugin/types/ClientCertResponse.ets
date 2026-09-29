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

export default class ClientCertResponse {
  private certificatePath: string;
  private certificatePassword: string;
  private keyStoreType: string;
  private action: number;

  constructor(certificatePath: string, certificatePassword: string, keyStoreType: string, action: number) {
    this.certificatePath = certificatePath;
    this.certificatePassword = certificatePassword;
    this.keyStoreType = keyStoreType;
    this.action = action;
  }

  public static fromMap(map: Map<string, Any>): ClientCertResponse | null {
    if (map == null) {
      return null;
    }
    let certificatePath: string = map.get("certificatePath");
    let certificatePassword: string = map.get("certificatePassword");
    let keyStoreType: string = map.get("keyStoreType");
    let action: number = map.get("action");

    return new ClientCertResponse(certificatePath, certificatePassword, keyStoreType, action);
  }

  getCertificatePath(): string {
    return this.certificatePath;
  }

  public setCertificatePath(certificatePath: string) {
    this.certificatePath = certificatePath;
  }

  public getCertificatePassword(): string {
    return this.certificatePassword;
  }

  public setCertificatePassword(certificatePassword: string) {
    this.certificatePassword = certificatePassword;
  }

  public getKeyStoreType(): string {
    return this.keyStoreType;
  }

  public setKeyStoreType(keyStoreType: string) {
    this.keyStoreType = keyStoreType;
  }

  public getAction(): number {
    return this.action;
  }

  public setAction(action: number) {
    this.action = action;
  }
}