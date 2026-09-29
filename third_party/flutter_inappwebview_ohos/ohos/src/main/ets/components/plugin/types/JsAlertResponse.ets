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

export default class JsAlertResponse {
  private message: string
  private confirmButtonTitle: string
  private handledByClient: boolean
  private action: number | null

  constructor(message: string, confirmButtonTitle: string, handledByClient: boolean, action: number | null) {
    this.message = message
    this.confirmButtonTitle = confirmButtonTitle
    this.handledByClient = handledByClient
    this.action = action
  }

  public static fromMap(map: Map<string, Any>): JsAlertResponse | null{
    if (map == null) {
      return null;
    }
    let message: string = map.get("message") as string
    let confirmButtonTitle: string = map.get("confirmButtonTitle") as string
    let handledByClient: boolean = map.get("handledByClient") as boolean
    let action: number = map.get("action") as number
    return new JsAlertResponse(message, confirmButtonTitle, handledByClient, action);
  }

  public getMessage(): string {
    return this.message;
  }

  public setMessage(message: string): void {
    this.message = message;
  }

  public getConfirmButtonTitle(): string {
    return this.confirmButtonTitle;
  }

  public setConfirmButtonTitle(confirmButtonTitle: string): void {
    this.confirmButtonTitle = confirmButtonTitle;
  }

  public isHandledByClient(): boolean {
    return this.handledByClient;
  }

  public setHandledByClient(handledByClient: boolean): void {
    this.handledByClient = handledByClient;
  }

  public getAction(): number | null {
    return this.action;
  }

  public setAction(action: number | null): void {
    this.action = action;
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;

    let that: JsAlertResponse = o as JsAlertResponse;

    if (this.handledByClient != that.handledByClient) return false;
    if (this.message != null ? !this.message.includes(that.message) : that.message != null) return false;
    if (this.confirmButtonTitle != null ? !this.confirmButtonTitle.includes(that.confirmButtonTitle) : that.confirmButtonTitle != null) return false;
    return this.action != null ? this.action == that.action : that.action == null;
  }

  public hashCode(): number {
    // let result: number = this.message != null ? this.message.hashCode() : 0;
    // result = 31 * result + (this.confirmButtonTitle != null ? this.confirmButtonTitle.hashCode() : 0);
    // result = 31 * result + (this.handledByClient ? 1 : 0);
    // result = 31 * result + (this.action != null ? this.action.hashCode() : 0);
    // return result;
    return 0
  }

  public toString(): string {
    return "JsAlertResponse{" +
      "message='" + this.message + '\'' +
      ", confirmButtonTitle='" + this.confirmButtonTitle + '\'' +
      ", handledByClient=" + this.handledByClient +
      ", action=" + this.action +
      '}';
  }
}