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

export default class MarginsExt {
  private top: number
  private right: number
  private bottom: number
  private left: number

  constructor(top: number, right: number, bottom: number, left: number) {
    this.top = top;
    this.right = right;
    this.bottom = bottom;
    this.left = left;
  }

  /// 缺少android.print.PrintAttributes
  // public fromMargins(margins: PrintAttributes.Margins): MarginsExt | null {
  //    if (margins == null) {
  //     return null;
  //   }
  //   let marginsExt: MarginsExt = new MarginsExt();
  //   marginsExt.top = this.milsToPixels(margins.getTopMils());
  //   marginsExt.right = this.milsToPixels(margins.getRightMils());
  //   marginsExt.bottom = this.milsToPixels(margins.getBottomMils());
  //   marginsExt.left = this.milsToPixels(margins.getLeftMils());
  //   return marginsExt;
  // }

  public static fromMap(map: Map<String, Object>): MarginsExt | null {
    if (map == null) {
      return null;
    }
    return new MarginsExt(
      map.get("top") as number,
      map.get("right") as number,
      map.get("bottom") as number,
      map.get("left") as number);
  }

  // public toMargins(): PrintAttributes.Margins {
  //   return new PrintAttributes.Margins(
  //     this.pixelsToMils(this.left!),
  //     this.pixelsToMils(this.top!),
  //     this.pixelsToMils(this.right!),
  //     this.pixelsToMils(this.bottom!)
  //   );
  // }

  private milsToPixels(mils: number): number {
    return mils * 0.09600001209449;
  }

  private pixelsToMils(pixels: number): number {
    return Math.round(pixels * 10.416665354331) as number;
  }

  public toMap(): Map<String, Object> {
    let obj: Map<String, Object> = new Map<String, Object>();
    obj.set("top", this.top!);
    obj.set("right", this.right!);
    obj.set("bottom", this.bottom!);
    obj.set("left", this.left!);
    return obj;
  }

  public getTop(): number {
    return this.top!;
  }

  public setTop(top: number): void {
    this.top = top;
  }

  public getRight(): number {
    return this.right!;
  }

  public setRight(right: number): void {
    this.right = right;
  }

  public getBottom(): number {
    return this.bottom!;
  }

  public setBottom(bottom: number): void {
    this.bottom = bottom;
  }

  public getLeft(): number {
    return this.left!;
  }

  public setLeft(left: number): void {
    this.left = left;
  }

  public equals(o: Object): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;

    let that: MarginsExt = o as MarginsExt;

    if (that.top != this.top) return false;
    if (that.right != this.right) return false;
    if (that.bottom != this.bottom) return false;
    return that.left == this.left;
  }

  public hashCode(): number {
    let result: number;
    let temp: number;
    temp = this.top!;
    result = temp ^ (temp >>> 32);
    temp = this.right!;
    result = 31 * result + temp ^ (temp >>> 32);
    temp = this.bottom!;
    result = 31 * result + temp ^ (temp >>> 32);
    temp = this.left!;
    result = 31 * result + temp ^ (temp >>> 32);
    return result;
  }

  public toString(): string {
    return "MarginsExt{" +
      "top=" + this.top +
      ", right=" + this.right +
      ", bottom=" + this.bottom +
      ", left=" + this.left +
      '}';
  }
}