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

import MarginsExt from './MarginsExt'
import MediaSizeExt from './MediaSizeExt'
import ResolutionExt from './ResolutionExt'
import PrintJobSettings from '../print_job/PrintJobSettings'

export class PrintAttributesExt {
  private colorMode: number = 0
  private duplex: number | null = null
  private orientation: number | null = null
  private mediaSize: MediaSizeExt | null = null
  private resolution: ResolutionExt | null = null
  private margins: MarginsExt | null = null

  constructor() {}

  public static fromPrintJobSettings(settings: PrintJobSettings): PrintAttributesExt | null {
    if (settings == null) {
      return null;
    }
    let attributesExt: PrintAttributesExt = new PrintAttributesExt();
    attributesExt.colorMode = settings.colorMode != null ? settings.colorMode! : 0;
    attributesExt.duplex = settings.duplexMode;
    attributesExt.orientation = settings.orientation;
    attributesExt.mediaSize = settings.mediaSize;
    attributesExt.resolution = settings.resolution;
    return attributesExt;
  }

  public setColorMode(colorMode: number): void {
    this.colorMode = colorMode;
  }

  public setDuplex(duplex: number | null): void {
    this.duplex = duplex;
  }

  public setOrientation(orientation: number | null): void {
    this.orientation = orientation;
  }

  public setMediaSize(mediaSize: MediaSizeExt | null): void {
    this.mediaSize = mediaSize;
  }

  public setResolution(resolution: ResolutionExt | null): void {
    this.resolution = resolution;
  }

  public setMargins(margins: MarginsExt | null): void {
    this.margins = margins;
  }

  public toMap(): Map<String, Object> {
    let obj: Map<String, Object> = new Map<String, Object>();
    obj.set("colorMode", this.colorMode);
    if (this.duplex != null) {
      obj.set("duplex", this.duplex as Object);
    }
    if (this.orientation != null) {
      obj.set("orientation", this.orientation as Object);
    }
    if (this.mediaSize != null) {
      obj.set("mediaSize", this.mediaSize.toMap());
    }
    if (this.resolution != null) {
      obj.set("resolution", this.resolution.toMap());
    }
    if (this.margins != null) {
      obj.set("margins", this.margins.toMap());
    }
    return obj;
  }
}
