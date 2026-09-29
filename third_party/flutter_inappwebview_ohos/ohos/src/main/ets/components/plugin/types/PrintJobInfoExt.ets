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

import { PrintAttributesExt } from './PrintAttributesExt'
import { PrintJobState } from '../print_job/PrintJobState'

export default class PrintJobInfoExt {
  private state: number | null = null
  private copies: number | null = null
  private numberOfPages: number | null = null
  private creationTime: number | null = null
  private label: string | null = null
  private printerId: string | null = null
  private attributes: PrintAttributesExt | null = null

  public setState(state: PrintJobState): void {
    this.state = state;
  }

  public setCopies(copies: number): void {
    this.copies = copies;
  }

  public setNumberOfPages(numberOfPages: number): void {
    this.numberOfPages = numberOfPages;
  }

  public setCreationTime(creationTime: number): void {
    this.creationTime = creationTime;
  }

  public setLabel(label: string): void {
    this.label = label;
  }

  public setPrinterId(printerId: string): void {
    this.printerId = printerId;
  }

  public setAttributes(attributes: PrintAttributesExt): void {
    this.attributes = attributes;
  }

  public toMap(): Map<String, Object> {
    let obj: Map<String, Object> = new Map<String, Object>();
    if (this.state != null) {
      obj.set("state", this.state!);
    }
    if (this.copies != null) {
      obj.set("copies", this.copies!);
    }
    if (this.numberOfPages != null) {
      obj.set("numberOfPages", this.numberOfPages!);
    }
    if (this.creationTime != null) {
      obj.set("creationTime", this.creationTime!);
    }
    if (this.label != null) {
      obj.set("label", this.label!);
    }
    if (this.printerId != null) {
      let printer: Map<String, Object> = new Map<String, Object>();
      printer.set("id", this.printerId!);
      obj.set("printer", printer);
    }
    if (this.attributes != null) {
      obj.set("attributes", this.attributes.toMap());
    }
    return obj;
  }
}
