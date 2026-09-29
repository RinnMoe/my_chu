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

export default class JsBeforeUnloadResponse {
  private message: string
  private confirmButtonTitle: string
  private cancelButtonTitle: string
  private handledByClient: boolean
  private action: number | null = null

  constructor(message: string, confirmButtonTitle: string, cancelButtonTitle: string, handledByClient: boolean, action: number | null) {
    this.message = message
    this.confirmButtonTitle = confirmButtonTitle
    this.cancelButtonTitle = cancelButtonTitle
    this.handledByClient = handledByClient
    this.action = action
  }

  public static fromMap(map: Map<string, Any>): JsBeforeUnloadResponse | null{
    if (map == null) {
      return null;
    }
    let message: string = map.get("message") as string
    let confirmButtonTitle: string = map.get("confirmButtonTitle") as string
    let cancelButtonTitle: string = map.get("cancelButtonTitle") as string;
    let handledByClient: boolean = map.get("handledByClient") as boolean
    let action: number = map.get("action") as number
    return new JsBeforeUnloadResponse(message, confirmButtonTitle, cancelButtonTitle, handledByClient, action);
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

  public getCancelButtonTitle(): string {
    return this.cancelButtonTitle;
  }

  public setCancelButtonTitle(cancelButtonTitle: string): void {
    this.cancelButtonTitle = cancelButtonTitle;
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

    let that: JsBeforeUnloadResponse = o as JsBeforeUnloadResponse;

    if (this.handledByClient != that.handledByClient) return false;
    if (this.message != null ? !this.message.includes(that.message) : that.message != null) return false;
    if (this.confirmButtonTitle != null ? !this.confirmButtonTitle.includes(that.confirmButtonTitle) : that.confirmButtonTitle != null) return false;
    if (this.cancelButtonTitle != null ? !this.cancelButtonTitle.includes(that.cancelButtonTitle) : that.cancelButtonTitle != null) return false;
    return this.action != null ? this.action == that.action : that.action == null;
  }

  public hashCode(): number {
    // let result: number = this.message != null ? this.message.hashCode() : 0;
    // result = 31 * result + (this.confirmButtonTitle != null ? this.confirmButtonTitle.hashCode() : 0);
    // result = 31 * result + (this.cancelButtonTitle != null ? this.cancelButtonTitle.hashCode() : 0);
    // result = 31 * result + (this.handledByClient ? 1 : 0);
    // result = 31 * result + (this.action != null ? this.action.hashCode() : 0);
    // return result;
    return 0
  }

  public toString(): string {
    return "JsConfirmResponse{" +
      "message='" + this.message + '\'' +
      ", confirmButtonTitle='" + this.confirmButtonTitle + '\'' +
      ", cancelButtonTitle='" + this.cancelButtonTitle + '\'' +
      ", handledByClient=" + this.handledByClient +
      ", action=" + this.action +
      '}';
  }
}