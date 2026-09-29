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

import ICallbackResult from './ICallbackResult';

export default class BaseCallbackResultImpl<T> implements ICallbackResult<T> {
  nonNullSuccess(result: T): boolean {
    return true;
  }

  nullSuccess(): boolean {
    return true;
  }

  defaultBehaviour(result: T | null): void {

  }

  success(obj: Object | null): void {
    let result = this.decodeResult(obj);
    let shouldRunDefaultBehaviour: boolean = false;
    if (result == null) {
      shouldRunDefaultBehaviour = this.nullSuccess();
    } else {
      shouldRunDefaultBehaviour = this.nonNullSuccess(result);
    }
    if (shouldRunDefaultBehaviour) {
      this.defaultBehaviour(result);
    }
  }

  decodeResult(obj: Object | null): T | null {
    return null;
  }


  error(errorCode: string, errorMessage: string, errorDetails: Object | null): void {

  }

  notImplemented(): void {
    this.defaultBehaviour(null);
  }
}