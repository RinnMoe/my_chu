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
import Util from '../Util'
import AndroidResource from './OhosResource'

export default class InAppBrowserMenuItem {

  private id: number
  private title: string
  private order: number | null
  private icon: AndroidResource | ArrayBuffer | null
  private iconColor: string | null
  private showAsAction: boolean

  constructor(id: number, title: string, order: number | null, icon: AndroidResource | ArrayBuffer | null, iconColor: string | null, showAsAction: boolean) {
    this.id = id
    this.title = title
    this.order = order
    this.icon = icon
    this.iconColor = iconColor
    this.showAsAction = showAsAction
  }

  public static fromMap(map: Map<string, Any>): InAppBrowserMenuItem | null {
    if (map == null) {
      return null;
    }
    let id: number = map.get("id") as number
    let title: string = map.get("title") as string
    let order: number = map.get("order") as number
    let icon: AndroidResource | ArrayBuffer | null = map.get("icon") as AndroidResource | ArrayBuffer | null
    if (icon instanceof Map) {
      icon = AndroidResource.fromMap(map.get("icon") as Map<string, Any>);
    } else if (!(icon instanceof ArrayBuffer)) {
      icon = null;
    }
    let iconColor: string = map.get("iconColor") as string;
    let showAsAction: boolean = Util.getOrDefault(map, "showAsAction", false) as boolean;
    return new InAppBrowserMenuItem(id, title, order, icon, iconColor, showAsAction);
  }

  public getId(): number {
    return this.id;
  }

  public setId(id: number): void {
    this.id = id;
  }

  public getTitle(): string {
    return this.title;
  }

  public setTitle(title: string): void {
    this.title = title;
  }

  public getOrder(): number {
    return this.order??0;
  }

  public setOrder(order: number): void {
    this.order = order;
  }

  public getIcon(): AndroidResource | ArrayBuffer | null {
    return this.icon;
  }

  public setIcon(icon: AndroidResource | ArrayBuffer | null): void {
    this.icon = icon;
  }

  public getIconColor(): string {
    return this.iconColor??'';
  }

  public setIconColor(iconColor: string): void {
    this.iconColor = iconColor;
  }

  public isShowAsAction(): boolean {
    return this.showAsAction;
  }

  public setShowAsAction(showAsAction: boolean): void {
    this.showAsAction = showAsAction;
  }

  public equals(o: Object | null): boolean {
    if (this == o) return true;
    // if (o == null || getClass() != o.getClass()) return false;

    let that: InAppBrowserMenuItem = o as InAppBrowserMenuItem;

    if (this.id != that.id) return false;
    if (this.showAsAction != that.showAsAction) return false;
    if (!this.title.includes(that.title)) return false;
    // if (!Any.equals(this.order, that.order)) return false;
    // if (!Any.equals(this.icon, that.icon)) return false;
    // return Any.equals(this.iconColor, that.iconColor);
    if(!(this.order == that.order)) return false
    if(!(this.icon == that.icon)) return false
    return this.iconColor == that.iconColor
  }

  public hashCode(): number {
    let result: number = this.id;
    // result = 31 * result + this.title.hashCode();
    // result = 31 * result + (this.order != null ? this.order.hashCode() : 0);
    // result = 31 * result + (this.icon != null ? this.icon.hashCode() : 0);
    // result = 31 * result + (this.iconColor != null ? this.iconColor.hashCode() : 0);
    // result = 31 * result + (this.showAsAction ? 1 : 0);
    return result;
  }

  public toString(): string {
    return "InAppBrowserMenuItem{" +
      "id=" + this.id +
      ", title='" + this.title + '\'' +
      ", order=" + this.order +
      ", icon=" + this.icon +
      ", iconColor='" + this.iconColor + '\'' +
      ", showAsAction=" + this.showAsAction +
      '}';
  }
}