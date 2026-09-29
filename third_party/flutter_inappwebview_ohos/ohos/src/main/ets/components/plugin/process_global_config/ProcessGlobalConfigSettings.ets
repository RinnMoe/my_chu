/*
* Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the 'License');
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an 'AS IS' BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import { Log } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import WebViewFeatureManager from '../WebViewFeatureManager';

const LOG_TAG = 'ProcessGlobalConfigSettings';

const STARTUP_FEATURE_SET_DATA_DIRECTORY_SUFFIX =
  'STARTUP_FEATURE_SET_DATA_DIRECTORY_SUFFIX';
const STARTUP_FEATURE_SET_DIRECTORY_BASE_PATHS =
  'STARTUP_FEATURE_SET_DIRECTORY_BASE_PATHS';

export class ProcessGlobalConfigDirectoryBasePaths {
  public cacheDirectoryBasePath: string | null = null;
  public dataDirectoryBasePath: string | null = null;

  public parse(settings: Object): ProcessGlobalConfigDirectoryBasePaths {
    let obj = settings as Record<string, Object>;
    let keys: string[] = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      let key: string = keys[i];
      let value: Object | undefined = obj[key];
      if (value == null || value == undefined) {
        continue;
      }
      switch (key) {
        case 'cacheDirectoryBasePath':
          this.cacheDirectoryBasePath = value as string;
          break;
        case 'dataDirectoryBasePath':
          this.dataDirectoryBasePath = value as string;
          break;
        default:
          break;
      }
    }
    return this;
  }
}

export default class ProcessGlobalConfigSettings {
  public dataDirectorySuffix: string | null = null;
  public directoryBasePaths: ProcessGlobalConfigDirectoryBasePaths | null = null;

  public parse(settings: Object): ProcessGlobalConfigSettings {
    if (settings instanceof Map) {
      let keys: IterableIterator<string> = settings.keys();
      for (let key of keys) {
        let value: Object | undefined = settings.get(key) as Object | undefined;
        if (value == null || value == undefined) {
          continue;
        }
        this._parseKeyValue(key, value);
      }
      return this;
    }

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
    return this;
  }

  private _parseKeyValue(key: string, value: Object): void {
    switch (key) {
      case 'dataDirectorySuffix':
        this.dataDirectorySuffix = value as string;
        break;
      case 'directoryBasePaths':
        this.directoryBasePaths = new ProcessGlobalConfigDirectoryBasePaths().parse(value);
        break;
      default:
        break;
    }
  }

  public apply(_context: common.Context): void {
    if (this.dataDirectorySuffix != null &&
      WebViewFeatureManager.isStartupFeatureSupported(STARTUP_FEATURE_SET_DATA_DIRECTORY_SUFFIX)) {
      Log.w(LOG_TAG, 'dataDirectorySuffix is not supported on OHOS yet');
    } else if (this.dataDirectorySuffix != null) {
      Log.d(LOG_TAG,
        `Ignoring unsupported dataDirectorySuffix=${this.dataDirectorySuffix} on OHOS`);
    }

    if (this.directoryBasePaths != null &&
      WebViewFeatureManager.isStartupFeatureSupported(STARTUP_FEATURE_SET_DIRECTORY_BASE_PATHS)) {
      Log.w(LOG_TAG, 'directoryBasePaths is not supported on OHOS yet');
    } else if (this.directoryBasePaths != null) {
      Log.d(LOG_TAG, 'Ignoring unsupported directoryBasePaths on OHOS');
    }
  }
}
