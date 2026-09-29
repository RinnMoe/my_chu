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

import { Log } from '@ohos/flutter_ohos';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import business_error from '@ohos.base';

export default class ChannelResultUtil {
  public static reportError(tag: string, operation: string, result: MethodResult, error: Object): void {
    let message: string;
    let code: string = operation + 'Error';
    if (error instanceof Error) {
      message = error.message ?? String(error);
    } else {
      let businessError = error as business_error.BusinessError;
      if (businessError?.message != null) {
        message = businessError.message;
        if (businessError.code != null) {
          code = String(businessError.code);
        }
      } else {
        message = JSON.stringify(error);
      }
    }
    Log.e(tag, `${operation} failed: ${message}`);
    result.error(code, message, null);
  }
}
