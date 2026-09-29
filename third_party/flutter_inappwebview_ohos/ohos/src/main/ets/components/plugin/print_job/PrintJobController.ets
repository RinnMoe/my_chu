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

import { print } from '@kit.BasicServicesKit';
import { Log, MethodChannel } from '@ohos/flutter_ohos';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import { Disposable } from '../types/Disposable';
import PrintJobInfoExt from '../types/PrintJobInfoExt';
import { PrintAttributesExt } from '../types/PrintAttributesExt';
import PrintJobChannelDelegate from './PrintJobChannelDelegate';
import PrintJobSettings from './PrintJobSettings';
import { PrintJobState } from './PrintJobState';

export default class PrintJobController implements Disposable {
  protected LOG_TAG: string = "PrintJob"
  public METHOD_CHANNEL_NAME_PREFIX: string = "com.pichillilorenzo/flutter_inappwebview_printjobcontroller_"

  public id: string

  public plugin: InAppWebViewFlutterPlugin | null

  public channelDelegate: PrintJobChannelDelegate | null

  /// OHOS print.PrintTask type
  public job: print.PrintTask | null

  public settings: PrintJobSettings | null

  /// Internal state tracking (OHOS PrintTask does not expose state directly)
  private _state: PrintJobState = PrintJobState.CREATED
  private _creationTime: number = 0
  private _label: string | null = null

  constructor(id: string, job: print.PrintTask | null, settings: PrintJobSettings, plugin: InAppWebViewFlutterPlugin) {
    this.id = id
    this.plugin = plugin
    this.job = job
    this.settings = settings
    let channel: MethodChannel = new MethodChannel(plugin.messenger!, this.METHOD_CHANNEL_NAME_PREFIX + id)
    this.channelDelegate = new PrintJobChannelDelegate(this, channel);
  }

  public setJob(printTask: print.PrintTask): void {
    this.job = printTask;
  }

  public setState(state: PrintJobState): void {
    this._state = state;
  }

  public setCreationTime(creationTime: number): void {
    this._creationTime = creationTime;
  }

  public setLabel(label: string): void {
    this._label = label;
  }

  public cancel(): void {
    // Off all event listeners to stop receiving state updates,
    // then mark as CANCELED and release the job reference.
    // The system print dialog may still be showing, but the app
    // side has relinquished control of this print task.
    if (this.job != null) {
      try {
        this.job!.off('block');
        this.job!.off('succeed');
        this.job!.off('fail');
        this.job!.off('cancel');
      } catch (e) {
        Log.e(this.LOG_TAG, "cancel: error off listeners: " + JSON.stringify(e));
      }
      this.job = null;
    }
    this._state = PrintJobState.CANCELED;
  }

  public dismiss(animated: boolean): void {
    // OHOS does not have a programmatic API to dismiss the system print dialog.
    // Cancel the job to stop receiving state updates and release the reference.
    if (this.job != null) {
      try {
        this.job!.off('block');
        this.job!.off('succeed');
        this.job!.off('fail');
        this.job!.off('cancel');
      } catch (e) {
        Log.e(this.LOG_TAG, 'dismiss: error off listeners: ' + JSON.stringify(e));
      }
      this.job = null;
    }
    this._state = PrintJobState.CANCELED;
  }

  public restart(): void {
    // OHOS PrintTask does not provide a restart() method.
    // To restart, dispose this controller and start a new print flow
    // via InAppWebView.printCurrentPage() with the same settings.
    // This is consistent with how iOS handles restart (also unsupported natively).
    if (this.job != null) {
      try {
        this.job!.off('block');
        this.job!.off('succeed');
        this.job!.off('fail');
        this.job!.off('cancel');
      } catch (e) {
        Log.e(this.LOG_TAG, "restart: error off listeners: " + JSON.stringify(e));
      }
      this.job = null;
    }
    this._state = PrintJobState.QUEUED;
  }

  public getInfo(): PrintJobInfoExt | null {
    let info: PrintJobInfoExt = new PrintJobInfoExt();
    info.setState(this._state);
    info.setCreationTime(this._creationTime);
    info.setLabel(this._label != null ? this._label! : (this.settings != null && this.settings.jobName != null) ? this.settings.jobName! : "PrintJob");
    // Set attributes from the original PrintJobSettings
    if (this.settings != null) {
      info.setAttributes(PrintAttributesExt.fromPrintJobSettings(this.settings!)!);
    }
    // numberOfPages, copies, printerId are not available from OHOS PrintTask API
    return info;
  }

  public disposeNoCancel(): void {
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    if (this.plugin != null && this.plugin.printJobManager != null) {
      this.plugin.printJobManager.jobs.delete(this.id);
    }
    if (this.job != null) {
      try {
        this.job!.off('block');
        this.job!.off('succeed');
        this.job!.off('fail');
        this.job!.off('cancel');
      } catch (e) {
        Log.e(this.LOG_TAG, "disposeNoCancel: error off listeners: " + JSON.stringify(e));
      }
      this.job = null;
    }
    this.plugin = null;
  }

  public dispose(): void {
    if (this.channelDelegate != null) {
      this.channelDelegate.dispose();
      this.channelDelegate = null;
    }
    if (this.plugin != null && this.plugin.printJobManager != null) {
      this.plugin.printJobManager.jobs.delete(this.id);
    }
    if (this.job != null) {
      try {
        this.job!.off('block');
        this.job!.off('succeed');
        this.job!.off('fail');
        this.job!.off('cancel');
      } catch (e) {
        Log.e(this.LOG_TAG, "dispose: error off listeners: " + JSON.stringify(e));
      }
      this.job = null;
    }
    this.plugin = null;
  }
}
