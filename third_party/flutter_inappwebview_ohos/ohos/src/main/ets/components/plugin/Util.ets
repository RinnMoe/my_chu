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

import { Any, Log } from '@ohos/flutter_ohos'
import display from '@ohos.display';
import Size2D from './types/Size2D';

export default class Util {
  static LOG_TAG: string = "Util"

  constructor() {
  }

  /// android.text.TextUtils未找对应的，未完善
  public static replaceAll(s: string, oldString: string, newString: string): string {
    let escapedOldString = oldString.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return s.replace(new RegExp(escapedOldString, 'g'), newString);
  }

  public static getOrDefault(map: Map<string, Any>, key: string, defaultValue: Object): Object {
    let keys = map.keys()
    for (let keyValue of keys) {
      if (keyValue == key) {
        return map.get(key) as Any
      }
    }
    return defaultValue;
  }

  public static objEquals(a: Any, b: Any): boolean {
    // ArkTS primitives (string/number) have no .equals; calling it throws
    // "undefined is not callable". Use == (null-safe value/reference equality).
    return a == b;
  }

  /**
   * Java String.format-compatible helper: supports `%s` placeholders (used by injectDeferredObject)
   * and `{0}` indexed placeholders.
   */
  public static formatString(format: string, ...args: Object[]): string {
    if (format.includes('%s')) {
      let argIndex = 0;
      return format.replace(/%s/g, () => {
        if (argIndex >= args.length) {
          return '%s';
        }
        const arg: Any = args[argIndex++];
        return arg !== undefined && arg !== null ? arg.toString() + "" : '';
      });
    }
    return format.replace(/{(\d+)}/g, (match, index: number) => {
      const arg: Any = args[index];
      return arg !== undefined ? arg.toString() + "" : match;
    });
  }

  static getPixelDensity(): number {
    try {
      return display.getDefaultDisplaySync().densityPixels;
    } catch (e) {
      Log.e(Util.LOG_TAG, `getPixelDensity failed: ${JSON.stringify(e)}`);
      return 1.0;
    }
  }

  static getFullscreenSize(): Size2D {
    try {
      let displayInfo = display.getDefaultDisplaySync();
      let width = displayInfo.width;
      let height = displayInfo.height;
      return new Size2D(width, height);
    } catch (e) {
      Log.e(Util.LOG_TAG, `getFullscreenSize failed: ${JSON.stringify(e)}`);
      return new Size2D(0, 0);
    }
  }
}