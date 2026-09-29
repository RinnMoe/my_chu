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

import { Log } from '@ohos/flutter_ohos';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { Disposable } from '../types/Disposable';
import PrintJobController from './PrintJobController';

const LOG_TAG = 'PrintJobManager';

export default class PrintJobManager implements Disposable {
  public plugin: InAppWebViewFlutterPlugin | null;
  public jobs = new Map<string, PrintJobController>();

  constructor(plugin: InAppWebViewFlutterPlugin) {
    this.plugin = plugin;
  }

  dispose(): void {
    let printJobControllers = this.jobs.values();
    for (let job of printJobControllers) {
      if (job != null) {
        try {
          job.dispose();
        } catch (e) {
          Log.e(LOG_TAG, 'dispose: print job dispose failed: ' + JSON.stringify(e));
        }
      }
    }
    this.jobs.clear();
    this.plugin = null;
  }
}