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

import web_webview from '@ohos.web.webview'
import { Any } from '@ohos/flutter_ohos'

export default class HitTestResult {
  private type: number
  private extra: string | null
  //对应Flutter端未知内容
  public static unknownType = 0;
  //对应Flutter端电话号码
  private static phoneType = 2;
  //对应Flutter端地理地址
  private static geoType = 3;
  //对应Flutter端电子邮件地址
  private static emailType = 4;
  //对应Flutter端HTML::img标签
  private static imageType = 5;
  //对应Flutter端超链接，其中src为http
  private static SRC_ANCHOR_TYPE = 7;
  //对应Flutter端带有超链接的图片，其中src为http + HTML::img
  private static srcImageAnchorType = 8;
  //对应Flutter端可编辑的区域
  private static editTextType = 9;

  constructor(type: number, extra: string | null) {
    this.type = type
    this.extra = extra
  }

  public static getFlutterHitTestResultType(ohosTitTestResultType: web_webview.WebHitTestType): number {
    switch (ohosTitTestResultType) {
      case web_webview.WebHitTestType.EditText:
        return HitTestResult.editTextType;
      case web_webview.WebHitTestType.Email:
        return HitTestResult.emailType;
      case web_webview.WebHitTestType.HttpAnchor:
        return HitTestResult.SRC_ANCHOR_TYPE;
      case web_webview.WebHitTestType.HttpAnchorImg:
        return HitTestResult.srcImageAnchorType;
      case web_webview.WebHitTestType.Img:
        return HitTestResult.imageType;
      case web_webview.WebHitTestType.Map:
        return HitTestResult.geoType;
      case web_webview.WebHitTestType.Phone:
        return HitTestResult.phoneType;
      case web_webview.WebHitTestType.Unknown:
        return HitTestResult.unknownType;
      default:
        return HitTestResult.unknownType;
    }
  }

  public static fromWebViewHitTestResult(hitTestResult: web_webview.HitTestValue | null): HitTestResult | null {
    if (hitTestResult == null) {
      return null;
    }
    return new HitTestResult(HitTestResult.getFlutterHitTestResultType(hitTestResult.type) , hitTestResult.extra);
  }

  public getType(): number {
    return this.type;
  }

  public setType(type: number): void {
    this.type = type;
  }

  public getExtra(): string | null {
    return this.extra;
  }

  public setExtra(extra: string | null): void {
    this.extra = extra;
  }

  public toMap(): Map<string, Any> {
    let hitTestResultMap: Map<string, Any> = new Map<string, Any>()
    hitTestResultMap.set("type", this.type);
    hitTestResultMap.set("extra", this.extra);
    return hitTestResultMap;
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;

    let that: HitTestResult = o as HitTestResult;

    if (this.type != that.type) return false;
    return this.extra != null ? this.extra.includes(that.extra??'') : that.extra == null;
  }

  public hashCode(): number {
    let result: number = this.type;
    // result = 31 * result + (this.extra != null ? this.extra.hashCode() : 0);
    return result;
  }

  public toString(): string {
    return "HitTestResultMap{" +
      "type=" + this.type +
      ", extra='" + this.extra + '\'' +
      '}';
  }
}