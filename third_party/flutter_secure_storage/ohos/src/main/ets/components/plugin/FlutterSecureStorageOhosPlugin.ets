/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
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

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  BinaryMessenger,
  StandardMethodCodec,
  EventChannel,
  EventSink
} from '@ohos/flutter_ohos';
import FlutterSecureStorage from './FlutterSecureStorage';

const TAG: string = "SecureStorage::FlutterSecureStoragePlugin";

interface EventListenerEvent {
  key: string;
  value: string | null;
}
/** FlutterSecureStorageOhosPlugin **/
export default class FlutterSecureStorageOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private secureStorage: FlutterSecureStorage | null = null;
  private ELEMENT_PREFERENCES_KEY_PREFIX: string = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg";
  private listeners: Map<string, Set<EventSink>> = new Map();

  public initInstance(messenger: BinaryMessenger, context: Context): void {
    try {
      this.secureStorage = new FlutterSecureStorage(context, new Map());
      this.channel = new MethodChannel(messenger, "plugins.it_nomads.com/flutter_secure_storage", StandardMethodCodec.INSTANCE);
      this.channel.setMethodCallHandler(this);

      // 初始化事件通道
      this.eventChannel = new EventChannel(messenger, "plugins.it_nomads.com/flutter_secure_storage/events");
     this.eventChannel.setStreamHandler({
  onListen: (arg: ESObject, eventSink: EventSink): void => {
    const key: string = arg as string;
    this.registerListener(key, eventSink);
  },
  onCancel: (arg: ESObject): void => {
    const key: string = arg as string;
    this.unregisterListener(key);
  }
});
    } catch (e) {
      console.error(TAG, "Registration failed", e);
    }
  }

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.initInstance(binding.getBinaryMessenger(), binding.getApplicationContext());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }

    if (this.eventChannel !== null) {
      this.eventChannel.setStreamHandler(null);
      this.eventChannel = null;
    }

    this.listeners.clear();
  }

  private getKeyFromCall(call: MethodCall): string {
    if (this.secureStorage !== null) {
      const map: ESObject = call.args;
      const key: string = this.ELEMENT_PREFERENCES_KEY_PREFIX + '_' + (map.get("key") as string);
      return key;
    } else {
      return '';
    }
  }

  private getValueFromCall(call: MethodCall): string {
    const map: ESObject = call.args;
    return map.get("value") as string;
  }

  // 注册监听器
  private registerListener(key: string, eventSink: EventSink): void {
    if (!this.listeners.has(key)) {
      this.listeners.set(key, new Set());
    }
    this.listeners.get(key)?.add(eventSink);
  }

  // 注销监听器
  private unregisterListener(key: string, eventSink?: EventSink): void {
    if (!this.listeners.has(key)) return;

    if (eventSink !== undefined) {
      this.listeners.get(key)?.delete(eventSink);
    } else {
      this.listeners.delete(key);
    }
  }

  // 触发监听器事件
  private notifyListeners(key: string, value: string | null): void {
    const event: EventListenerEvent = { key, value };

    if (key === '*') {
      // 通知所有监听器（用于deleteAll）
      this.listeners.forEach((sinks: Set<EventSink>, k: string): void => {
        if (k !== '*') {
          sinks.forEach((sink: EventSink): void => sink.success({ key: k, value: null }));
        }
      });
    } else {
      // 通知特定key的监听器
      this.listeners.get(key)?.forEach((sink: EventSink): void => sink.success(event));
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === "getPlatformVersion") {
      result.success("OpenHarmony ^ ^ ");
    } else {
      let resetOnError: boolean = false;
      if (this.secureStorage === null) {
        result.error('secure_storage_unavailable', 'Secure storage is not initialized', null);
        return;
      }
      this.secureStorage.options = call.args.get("options") as Map<string, object>;
      resetOnError = this.secureStorage.getResetOnError();
      try {
        switch (call.method) {
          case 'write': {
            const key: string = this.getKeyFromCall(call);
            const value: string = this.getValueFromCall(call);
            if (value !== null) {
              this.secureStorage?.write(key, value).then((): void => {
                this.notifyListeners(key, value);
                result.success(null);
              }).catch((): void => {
                console.error(TAG, 'Secure storage write failed');
                this.notifyListeners(key, null);
                result.error('secure_storage_write_failed', 'Secure storage write failed', null);
              });
            } else {
              result.error("null", null, null);
            }
            break;
          }
          case "read": {
            const key: string = this.getKeyFromCall(call);

            if (this.secureStorage.containsKey(key)) {
              this.secureStorage.read(key).then((res: string | null): void => {
                result.success(res);
              }).catch((): void => {
                console.error(TAG, 'Secure storage read failed');
                result.error('secure_storage_read_failed', 'Secure storage read failed', null);
              });
            } else {
              result.success(null);
            }
            break;
          }
          case "readAll": {
            this.secureStorage.readAll().then((all: Map<string, string>): void => {
              result.success(all);
            }).catch((): void => {
              console.error(TAG, 'Secure storage readAll failed');
              result.error('secure_storage_read_all_failed', 'Secure storage readAll failed', null);
            });
            break;
          }
          case "containsKey": {
            const key: string = this.getKeyFromCall(call);

            const containsKey: boolean = this.secureStorage.containsKey(key);
            result.success(containsKey);
            break;
          }
          case "delete": {
            const key: string = this.getKeyFromCall(call);

            this.secureStorage?.delete(key).then((): void => {
              this.notifyListeners(key, null);
              result.success(null);
            }).catch((): void => {
              console.error(TAG, 'Secure storage delete failed');
              result.error('secure_storage_delete_failed', 'Secure storage delete failed', null);
            });
            break;
          }
          case "deleteAll": {
            this.secureStorage.deleteAll().then((): void => {
              this.notifyListeners('*', null);
              result.success(null);
            }).catch((): void => {
              console.error(TAG, 'Secure storage deleteAll failed');
              result.error('secure_storage_delete_all_failed', 'Secure storage deleteAll failed', null);
            });
            break;
          }
          // 处理iOS特有方法
          case "isCupertinoProtectedDataAvailable":
            result.success(null); // 鸿蒙不支持，返回null
            break;

          case "onCupertinoProtectedDataAvailabilityChanged":
            result.notImplemented(); // 不实现此方法
            break;

          default:
            result.notImplemented();
            break;
        }
      } catch (e) {
        if (resetOnError) {
          this.secureStorage.deleteAll().then((): void => {
            this.notifyListeners('*', null);
            result.success('Data has been reset');
          }).catch((): void => {
            console.error(TAG, 'Secure storage reset failed');
            result.error('secure_storage_reset_failed', 'Secure storage reset failed', null);
          });
        } else {
          console.error(TAG, 'Secure storage operation failed');
          result.error('secure_storage_operation_failed', 'Secure storage operation failed', null);
        }
      }
    }
  }
}
