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
import BaseCallbackResultImpl from './BaseCallbackResultImpl';
import napi from 'libinappwebview.so';

const RESPONSE_PENDING: number = 0;
const RESPONSE_DONE: number = 1;

export default class SyncBaseCallbackResultImpl<T> extends BaseCallbackResultImpl<T> {
  public result: T | null = null;

  private readonly responseState: Int32Array;

  private static readonly DEFAULT_TIMEOUT_MS: number = 10_000;

  constructor() {
    super();
    const sab = new SharedArrayBuffer(4);
    this.responseState = new Int32Array(sab);
    Atomics.store(this.responseState, 0, RESPONSE_PENDING);
  }

  public get responsed(): boolean {
    return Atomics.load(this.responseState, 0) === RESPONSE_DONE;
  }

  private signalDone(): void {
    Atomics.store(this.responseState, 0, RESPONSE_DONE);
  }

  defaultBehaviour(result: T | null): void {
    this.signalDone();
  }

  success(obj: Object | null): void {
    let result = this.decodeResult(obj);
    this.result = result;
    let shouldRunDefaultBehaviour: boolean = false;
    if (result == null) {
      shouldRunDefaultBehaviour = this.nullSuccess();
    } else {
      shouldRunDefaultBehaviour = this.nonNullSuccess(result);
    }
    if (shouldRunDefaultBehaviour) {
      this.defaultBehaviour(result);
    } else {
      this.signalDone();
    }
  }

  waitResponse(): boolean {
    return this.waitResponseWithTimeout(SyncBaseCallbackResultImpl.DEFAULT_TIMEOUT_MS);
  }

  waitResponseWithTimeout(timeoutMs: number): boolean {
    let startTime = Date.now();
    while (Atomics.load(this.responseState, 0) === RESPONSE_PENDING) {
      if (Date.now() - startTime >= timeoutMs) {
        Log.w("SyncBaseCallbackResultImpl", `waitResponseWithTimeout timed out after ${timeoutMs}ms`);
        return false;
      }
      napi.uvRunNowait();
    }
    return true;
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null) {
    this.signalDone();
  }

  notImplemented(): void {
    this.defaultBehaviour(null);
  }
}
