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
import WebResourceErrorTypeUtil from './WebResourceErrorTypeUtil';

export default class WebResourceErrorExt {
  private type: number
  private description: string

  constructor(type: number, description: string) {
    this.type = type
    this.description = description
  }

  public toMap(): Map<string, Any> {
    let webResourceErrorMap: Map<string, Any> = new Map<string, Any>();
    webResourceErrorMap.set("type", WebResourceErrorTypeUtil.toWebResourceErrorTypeName(this.getType()));
    webResourceErrorMap.set("description", this.getDescription() ?? "");
    return webResourceErrorMap;
  }

  static fromWebResourceError(error: WebResourceError) {
    return new WebResourceErrorExt(error.getErrorCode(), error.getErrorInfo());
  }

  public getType(): number {
    return this.type;
  }

  public setType(type: number): void {
    this.type = type;
  }

  public getDescription(): string {
    return this.description;
  }

  public setDescription(description: string): void {
    this.description = description;
  }

  public toString(): string {
    return "WebResourceErrorExt{" +
      "type=" + this.type +
      ", description='" + this.description + '\'' +
      '}';
  }
}