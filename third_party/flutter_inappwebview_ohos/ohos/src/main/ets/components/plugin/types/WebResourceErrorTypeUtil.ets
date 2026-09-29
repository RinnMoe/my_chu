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

/**
 * Maps ArkWeb / Chromium net error codes to [WebResourceErrorType] string values
 * consumed by Dart via WebResourceErrorType.fromValue.
 */
export default class WebResourceErrorTypeUtil {
  public static toWebResourceErrorTypeName(errorCode: number): string {
    switch (errorCode) {
      // Android WebViewClient error codes
      case -1:
        return "UNKNOWN";
      case -2:
        return "HOST_LOOKUP";
      case -3:
        return "UNSUPPORTED_AUTH_SCHEME";
      case -4:
        return "USER_AUTHENTICATION_FAILED";
      case -5:
        return "PROXY_AUTHENTICATION";
      case -6:
        return "CANNOT_CONNECT_TO_HOST";
      case -7:
        return "IO";
      case -8:
        return "TIMEOUT";
      case -9:
        return "TOO_MANY_REDIRECTS";
      case -10:
        return "UNSUPPORTED_SCHEME";
      case -11:
        return "FAILED_SSL_HANDSHAKE";
      case -12:
        return "BAD_URL";
      case -13:
        return "GENERIC_FILE_ERROR";
      case -14:
        return "FILE_NOT_FOUND";
      case -15:
        return "TOO_MANY_REQUESTS";
      case -16:
        return "UNSAFE_RESOURCE";
      // Common Chromium net errors (ArkWeb)
      case -105:
        return "HOST_LOOKUP";
      case -106:
        return "NOT_CONNECTED_TO_INTERNET";
      case -102:
        return "CANNOT_CONNECT_TO_HOST";
      case -118:
        return "TIMEOUT";
      case -109:
        return "BAD_URL";
      case -200:
      case -201:
      case -202:
      case -203:
        return "FAILED_SSL_HANDSHAKE";
      case -501:
        return "UNSAFE_RESOURCE";
      // HarmonyOS documented net errors
      case 302:
        return "UNSUPPORTED_SCHEME";
      default:
        return "UNKNOWN";
    }
  }
}
