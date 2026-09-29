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

import { Any } from '@ohos/flutter_ohos';
import ISettings from '../ISettings';
import MediaSizeExt from '../types/MediaSizeExt';
import ResolutionExt from '../types/ResolutionExt';
import PrintJobController from './PrintJobController';

export default class PrintJobSettings implements ISettings<PrintJobController> {
  public LOG_TAG: string = "PrintJobSettings"

  public handledByClient: boolean = false
  public jobName: string | null = null
  public orientation: number | null = null
  // public margins: number | null = null;
  public mediaSize: MediaSizeExt | null = null
  public colorMode: number | null = null
  public duplexMode: number | null = null
  public resolution: ResolutionExt | null = null

  constructor() {}

  public parse(settings: Map<string, Any> | Object): PrintJobSettings {
    if (settings instanceof Map) {
      let keys: IterableIterator<string> = settings.keys();
      for (let key of keys) {
        let value: Object = settings.get(key) as Object;
        if (value == null) {
          continue;
        }
        this._parseKeyValue(key, value);
      }
    } else {
      let obj = settings as Record<string, Object>;
      let keys: string[] = Object.keys(obj);
      for (let i = 0; i < keys.length; i++) {
        let key: string = keys[i];
        let value: Object | undefined = obj[key];
        if (value == null || value == undefined) {
          continue;
        }
        this._parseKeyValue(key, value);
      }
    }
    return this;
  }

  private _parseKeyValue(key: string, value: Object): void {
    switch (key) {
      case "handledByClient":
        this.handledByClient = value as boolean;
        break;
      case "jobName":
        this.jobName = value as string;
        break;
      case "orientation":
        this.orientation = value as number;
        break;
      case "mediaSize":
        this.mediaSize = MediaSizeExt.fromMap(value as Map<string, Object>);
        break;
      case "colorMode":
        this.colorMode = value as number;
        break;
      case "duplexMode":
        this.duplexMode = value as number;
        break;
      case "resolution":
        this.resolution = ResolutionExt.fromMap(value as Map<string, Object>);
        break;
    }
  }

  public toMap(): Map<string, Any> {
    let settings: Map<string, Any> = new Map<string, Any>();
    settings.set("handledByClient", this.handledByClient);
    settings.set("jobName", this.jobName!);
    settings.set("orientation", this.orientation!);
//    settings.set("margins", this.margins != null ? this.margins.toMap() : Object);
    settings.set("mediaSize", this.mediaSize != null ? this.mediaSize.toMap() : null);
    settings.set("colorMode", this.colorMode!);
    settings.set("duplexMode", this.duplexMode!);
    settings.set("resolution", this.resolution != null ? this.resolution.toMap() : null);
    return settings;
  }

  public getRealSettings(printJobController: PrintJobController): Map<string, Any> {
    let realSettings: Map<string, Any> = this.toMap()
    return realSettings
  }
}