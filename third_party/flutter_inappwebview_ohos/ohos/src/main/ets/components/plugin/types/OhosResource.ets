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

export default class AndroidResource {

  private name: string
  private defType: string | null
  private defPackage: string | null

  constructor(name: string, defType: string | null, defPackage: string | null) {
    this.name = name
    this.defType = defType
    this.defPackage = defPackage
  }

  public static fromMap(map: Map<string, Any>): AndroidResource | null {
    if (map == null) {
      return null;
    }
    let name: string = map.get("name") as string;
    let defType: string = map.get("defType") as string;
    let defPackage: string = map.get("defPackage") as string;
    return new AndroidResource(name, defType, defPackage);
  }

  public toMap(): Map<string, Any> {
    let urlRequestMap: Map<string, Any> = new Map<string, Any>();
    urlRequestMap.set("name", this.name);
    urlRequestMap.set("defType", this.defType);
    urlRequestMap.set("defPackage", this.defPackage);
    return urlRequestMap;
  }

  public getName(): string {
    return this.name;
  }

  public setName(name: string): void {
    this.name = name;
  }

  public getDefType(): String {
    return this.defType??'';
  }

  public setDefType(defType: null): void {
    this.defType = defType;
  }

  public getDefPackage(): string {
    return this.defPackage??'';
  }

  public setDefPackage(defPackage: string): void {
    this.defPackage = defPackage;
  }

  public getIdentifier(ctx: Context): number {
    // return ctx.getResources().getIdentifier(name, defType, defPackage);
    return 0
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;

    let that: AndroidResource = o as AndroidResource;

    if (!this.name.includes(that.name)) return false;
    if (this.defType != null ? !this.defType.includes(that.defType??'') : that.defType != null) return false;
    return this.defPackage != null ? this.defPackage.includes(that.defPackage??'') : that.defPackage == null;
  }

  public hashCode(): number {
    // let result: number = this.name.hashCode();
    // result = 31 * result + (this.defType != null ? this.defType.hashCode() : 0);
    // result = 31 * result + (this.defPackage != null ? this.defPackage.hashCode() : 0);
    // return result;
    return 0
  }

  public toString(): string {
    return "AndroidResource{" +
      "name='" + this.name + '\'' +
      ", type='" + this.defType + '\'' +
      ", defPackage='" + this.defPackage + '\'' +
      '}';
  }
}