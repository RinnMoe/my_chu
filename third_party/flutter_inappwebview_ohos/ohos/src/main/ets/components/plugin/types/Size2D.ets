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

export default class Size2D {
  private width: number;
  private height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }

  static fromMap(map: Map<string, number> | null | undefined): Size2D | null {
    if (map == null || map == undefined) {
      return null;
    }
    let width = map.get("width") as number;
    let height = map.get("height") as number;
    return new Size2D(width, height);
  }

  toMap(): Map<string, number> {
    let sizeMap: Map<string, number> = new Map<string, number>();
    // Force floating-point values so Dart Size() receives doubles, not ints.
    sizeMap.set("width", parseFloat(this.width.toString()));
    sizeMap.set("height", parseFloat(this.height.toString()));
    return sizeMap;
  }

  getWidth(): number {
    return this.width;
  }

  setWidth(width: number): void {
    this.width = width;
  }

  getHeight(): number {
    return this.height;
  }

  setHeight(height: number): void {
    this.height = height;
  }

  equals(o: Object | null): boolean {
    if (this == o) return true;
    if (o == null || !(o instanceof Size2D)) return false;

    let size = o as Size2D;
    return size.width === this.width && size.height === this.height;
  }

  toString(): string {
    return "Size{" +
      "width=" + this.width +
      ", height=" + this.height +
      "}";
  }
}
