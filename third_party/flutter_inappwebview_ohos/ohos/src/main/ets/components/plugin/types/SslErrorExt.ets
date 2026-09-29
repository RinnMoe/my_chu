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

export default class SslErrorExt {
  constructor() {
  }

  public static toMap(sslError: SslError | null): Map<string, Any> | null {
    if (sslError == null) {
      return null
    }

    let message: string | null = null;

    switch (sslError) {
      case SslError.DateInvalid:
        message = "The date of the certificate is invalid";
        break;
      case SslError.HostMismatch:
        message = "Hostname mismatch";
        break;
      case SslError.Invalid:
        message = "A generic error occurred";
        break;
      case SslError.Untrusted:
        message = "The certificate authority is not trusted";
        break;
      default:
        message = null;
        break;
    }

    let urlProtectionSpaceMap : Map<string, Any> = new Map<string, Any>();
    urlProtectionSpaceMap.set("code", covertSslErrorCode(sslError));
    urlProtectionSpaceMap.set("message", message);
    return urlProtectionSpaceMap;
  }
}

function covertSslErrorCode(sslError: SslError) {
  if (sslError == SslError.DateInvalid) {
    return 4;
  } else if (sslError == SslError.HostMismatch) {
    return 2;
  } else if (sslError == SslError.Invalid) {
    return 5;
  } else if (sslError == SslError.Untrusted) {
    return 3;
  }
  return 0;
}