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

export default class ResolutionExt {
  private id: string
  private label: string
  private verticalDpi: number
  private horizontalDpi: number

  constructor(id: string, label: string, verticalDpi: number, horizontalDpi: number) {
    this.id = id
    this.label = label
    this.verticalDpi = verticalDpi
    this.horizontalDpi = horizontalDpi
  }

  /// 缺少android.print.PrintAttributes
  // public static fromResolution(resolution: PrintAttributes.Resolution): ResolutionExt | null {
  //   if (resolution == null) {
  //     return null;
  //   }
  //   return new ResolutionExt(
  //     resolution.getId(),
  //     resolution.getLabel(),
  //     resolution.getVerticalDpi(),
  //     resolution.getHorizontalDpi()
  //   );
  // }

  public static fromMap(map: Map<String, Object>): ResolutionExt | null {
    if (map == null) {
      return null
    }
    let id: string = map.get("id") as string
    let label: string = map.get("label") as string
    let verticalDpi: number = map.get("verticalDpi") as number
    let horizontalDpi: number = map.get("horizontalDpi") as number
    return new ResolutionExt(id, label, verticalDpi, horizontalDpi)
  }

  // public toResolution(): PrintAttributes.Resolution {
  //   return new PrintAttributes.Resolution(
  //     id, label, horizontalDpi, verticalDpi
  //   );
  // }

  public toMap(): Map<String, Object> {
    let obj: Map<String, Object> = new Map<String, Object>()
    obj.set("id", this.id!)
    obj.set("label", this.label!)
    obj.set("verticalDpi", this.verticalDpi!)
    obj.set("horizontalDpi", this.horizontalDpi!)
    return obj
  }

  public getId(): string {
    return this.id!;
  }

  public setId(id: string): void {
    this.id = id;
  }

  public getLabel(): string {
    return this.label!;
  }

  public setLabel(label: string): void {
    this.label = label;
  }

  public getVerticalDpi(): number {
    return this.verticalDpi!;
  }

  public setVerticalDpi(verticalDpi: number): void {
    this.verticalDpi = verticalDpi;
  }

  public getHorizontalDpi(): number {
    return this.horizontalDpi!;
  }

  public setHorizontalDpi(horizontalDpi: number) {
    this.horizontalDpi = horizontalDpi;
  }

  public equals(o: Object): boolean {
    if (this == o) return true
    // if (o == null || getClass() != 0.getClass()) return false

    let that: ResolutionExt = o as ResolutionExt

    if (this.verticalDpi != that.verticalDpi) return false;
    if (this.horizontalDpi != that.horizontalDpi) return false;
    if (this.id?.indexOf(that.id!) == -1) return false;
    return this.label != null ? this.label?.indexOf(that.label!) == -1 : that.label == null
  }

  public hashCode(): number {
    // let result: number = this.id?.hashCode();
    // result = 31 * result + (this.label != null ? this.label.hashCode() : 0)
    // result = 31 * result + this.widthMils!
    // result = 31 * result + this.heightMils!
    // return result
    return 0
  }

  public toString(): string {
    return "MediaSizeExt{" +
      "id='" + this.id + '\'' +
      ", label='" + this.label + '\'' +
      ", widthMils=" + this.verticalDpi +
      ", heightMils=" + this.horizontalDpi +
      '}';
  }
}