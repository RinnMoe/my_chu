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

export default class CustomSchemeResponse {
  private data: ArrayBuffer;
  private contentType: string;
  private contentEncoding: string;

  constructor(data: ArrayBuffer, contentType: string, contentEncoding: string) {
    this.data = data;
    this.contentType = contentType;
    this.contentEncoding = contentEncoding;
  }

  static fromMap(map: Map<string, Any>): CustomSchemeResponse | null {
    if (map == null) {
      return null;
    }
    let data: ArrayBuffer = map.get("data");
    let contentType: string = map.get("contentType");
    let contentEncoding: string = map.get("contentEncoding");
    return new CustomSchemeResponse(data, contentType, contentEncoding);
  }

  getData(): ArrayBuffer {
    return this.data;
  }

  setData(data: ArrayBuffer) {
    this.data = data;
  }

  getContentType(): string {
    return this.contentType;
  }

  setContentType(contentType: string) {
    this.contentType = contentType;
  }

  getContentEncoding(): string {
    return this.contentEncoding;
  }

  setContentEncoding(contentEncoding: string) {
    this.contentEncoding = contentEncoding;
  }
}