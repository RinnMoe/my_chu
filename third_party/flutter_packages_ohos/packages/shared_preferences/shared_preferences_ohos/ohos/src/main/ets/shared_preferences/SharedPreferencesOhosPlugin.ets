// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on SharedPreferencesPlugin.java originally written by
// Copyright 2013 The Flutter Authors.

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/MessageCodec';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { FlutterError, SharedPreferencesApi, wrapError } from './Messages';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import data_preferences from '@ohos.data.preferences';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import { bundleManager } from '@kit.AbilityKit';
import {
  SharedPreferencesAsyncApi,
  setupSharedPreferencesAsyncApi,
  SharedPreferencesPigeonOptions,
  StringListResult,
  StringListLookupResultType
} from './MessagesAsync';

const TAG = "SharedPreferencesOhosPlugin";
const PREFERENCES_NAME = "FlutterSharedPreferences";
const DATA_STORE_BACKEND_NAME = "FlutterSharedPreferencesDataStore";
const PREFERENCES_NOT_INITIALIZED_ERROR = "Preferences not initialized";
const LIST_IDENTIFIER = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu";
const JSON_LIST_PREFIX = LIST_IDENTIFIER + "!";
const BIG_INTEGER_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBCaWdJbnRlZ2Vy";
const DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu";
// ListEncoder implementation
interface ListEncoder {
  encode(list: string[]): string;
  decode(encoded: string): string[];
}

class ListEncoderImpl implements ListEncoder {
  encode(list: string[]): string {
    return JSON.stringify(list);
  }

  decode(encoded: string): string[] {
    try {
      return JSON.parse(encoded) as string[];
    } catch (e) {
      Log.e(TAG, "Failed to decode list: " + e);
      return [];
    }
  }
}

// Extended type definition to handle all OHOS ValueType values
type PreferenceScalarValue = string | number | boolean | bigint;
type ExtendedPreferenceValue = PreferenceScalarValue | object | null;
type PreferenceWriteValue = PreferenceScalarValue | string[];

// Async API implementation class
class SharedPreferencesAsyncApiImpl implements SharedPreferencesAsyncApi {
  private plugin: SharedPreferencesOhosPlugin;

  constructor(plugin: SharedPreferencesOhosPlugin) {
    this.plugin = plugin;
  }

  private typeMismatch(key: string, expectedType: string, actualValue: ExtendedPreferenceValue): FlutterError {
    const actualType = actualValue === null ? 'null' : typeof actualValue;
    return new FlutterError(
      'ClassCastException',
      `Expected ${expectedType} for key "${key}", but found ${actualType}.`,
      `key=${key}, expectedType=${expectedType}, actualType=${actualType}`
    );
  }

  async getString(key: string, options: SharedPreferencesPigeonOptions): Promise<string | null> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return null;
      }
      const value = await preferences.get(key, null) as ExtendedPreferenceValue;
      if (value === null) {
        return null;
      }
      if (typeof value === 'string') {
        if (!value.startsWith(LIST_IDENTIFIER)) {
          return value;
        }
        return Promise.reject(this.typeMismatch(key, 'string', value));
      }
      return Promise.reject(this.typeMismatch(key, 'string', value));
    } catch (err) {
      Log.w(TAG, "Failed to getString: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  async getBool(key: string, options: SharedPreferencesPigeonOptions): Promise<boolean | null> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return null;
      }
      const value = await preferences.get(key, null) as ExtendedPreferenceValue;
      if (value === null) {
        return null;
      }
      if (typeof value === 'boolean') {
        return value;
      }
      return Promise.reject(this.typeMismatch(key, 'boolean', value));
    } catch (err) {
      Log.w(TAG, "Failed to getBool: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  async getDouble(key: string, options: SharedPreferencesPigeonOptions): Promise<number | null> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return null;
      }
      const value = await preferences.get(key, null) as ExtendedPreferenceValue;
      if (value === null) {
        return null;
      }
      if (typeof value === 'number') {
        return value;
      } else if (typeof value === 'bigint') {
        return Number(value);
      }
      return Promise.reject(this.typeMismatch(key, 'number', value));
    } catch (err) {
      Log.w(TAG, "Failed to getDouble: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  async getInt(key: string, options: SharedPreferencesPigeonOptions): Promise<bigint | null> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return null;
      }
      const value = await preferences.get(key, null) as ExtendedPreferenceValue;
      if (value === null) {
        return null;
      }
      if (typeof value ==='bigint' || typeof value === 'number'){
        return BigInt(value);
      }
      return Promise.reject(this.typeMismatch(key, 'int', value));
    } catch (err) {
      Log.w(TAG, "Failed to getInt: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  async getPlatformEncodedStringList(key: string, options: SharedPreferencesPigeonOptions): Promise<Array<string> | null> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return null;
      }
      const value = await preferences.get(key, null) as ExtendedPreferenceValue;
      if (typeof value === 'string' && value.startsWith(LIST_IDENTIFIER)) {
        const decoded: string[] = this.plugin.listEncoder.decode(value.substring(LIST_IDENTIFIER.length));
        return decoded;
      }
      return null;
    } catch (err) {
      Log.w(TAG, "Failed to getPlatformEncodedStringList: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  async getStringList(key: string, options: SharedPreferencesPigeonOptions): Promise<StringListResult | null> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return null;
      }
      const value = await preferences.get(key, null) as ExtendedPreferenceValue;
      if (typeof value === 'string') {
        if (value.startsWith(JSON_LIST_PREFIX)) {
          return new StringListResult(value, StringListLookupResultType.jsonEncoded);
        } else if (value.startsWith(LIST_IDENTIFIER)) {
          return new StringListResult(undefined, StringListLookupResultType.platformEncoded);
        } else {
          return new StringListResult(undefined, StringListLookupResultType.unexpectedString);
        }
      }
      return null;
    } catch (err) {
      Log.w(TAG, "Failed to getStringList: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  async clear(allowList: Array<string> | null, options: SharedPreferencesPigeonOptions): Promise<void> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return Promise.reject(new Error("Preferences not initialized"));
      }
      let keysToDelete: string[] = [];
      if (allowList == null) {
        const allData = await preferences.getAll() as Record<string, ExtendedPreferenceValue>;
        keysToDelete = Object.keys(allData);
      } else {
        keysToDelete = Array.from(new Set<string>(allowList));
      }

      // 分批删除，每批10个key
      const batchSize = 10;
      for (let i = 0; i < keysToDelete.length; i += batchSize) {
        const batch = keysToDelete.slice(i, i + batchSize);
        const deletePromises = batch.map(key =>
          new Promise<void>((resolve, reject) => {
            preferences.delete(key, (err: ESObject) => {
              if (err) reject(err);
              else resolve();
            });
          })
        );
        await Promise.all(deletePromises);
      }
      await preferences.flush();
    } catch (err) {
      Log.w(TAG, "Failed to clear: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  async getAll(allowList: Array<string> | null, options: SharedPreferencesPigeonOptions): Promise<Map<string, Object>> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return new Map<string, Object>();
      }
      const allData = await preferences.getAll() as Record<string, ExtendedPreferenceValue>;
      const result = new Map<string, Object>();
      Object.keys(allData).forEach((key: string) => {
        const value = allData[key];
        if (allowList == null || allowList.indexOf(key) != -1) {
          result.set(key, this.plugin.transformPref(value));
        }
      });
      return result;
    } catch (err) {
      Log.w(TAG, "Failed to getAll: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  async getKeys(allowList: Array<string> | null, options: SharedPreferencesPigeonOptions): Promise<Array<string>> {
    try {
      const preferences = await this.plugin.getPreferencesForOptions(options);
      if (preferences == null) {
        return [];
      }
      const allData = await preferences.getAll() as Record<string, ExtendedPreferenceValue>;
      const allKeys = Object.keys(allData);
      return allKeys.filter((key: string) => allowList == null || allowList.indexOf(key) != -1);
    } catch (err) {
      Log.w(TAG, "Failed to getKeys: " + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  // Async setter methods
  async setBool(key: string, value: boolean, options: SharedPreferencesPigeonOptions): Promise<void> {
    return this.plugin.putWithOptions(key, value, options);
  }

  async setString(key: string, value: string, options: SharedPreferencesPigeonOptions): Promise<void> {
    return this.plugin.putWithOptions(key, value, options);
  }

  async setInt(key: string, value: bigint, options: SharedPreferencesPigeonOptions): Promise<void> {
    return this.plugin.putWithOptions(key, value, options);
  }

  async setDouble(key: string, value: number, options: SharedPreferencesPigeonOptions): Promise<void> {
    return this.plugin.putWithOptions(key, value, options);
  }

  async setEncodedStringList(key: string, value: string, options: SharedPreferencesPigeonOptions): Promise<void> {
    return this.plugin.putWithOptions(key, value, options);
  }

  async setDeprecatedStringList(key: string, value: Array<string>, options: SharedPreferencesPigeonOptions): Promise<void> {
    return this.plugin.setStringListWithOptions(key, value, options);
  }
}

// Setup function implementation
export function setup(binaryMessenger: BinaryMessenger, api: SharedPreferencesApi | null): void {
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.remove", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const keyArg = args[0] as string;
          let wrapped: Array<Object>;
          try {
            const result = api.remove(keyArg);
            wrapped = [result];
          } catch (exception) {
            wrapped = wrapError(exception as Error);
          }
          reply.reply(wrapped);
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // setBool
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.setBool", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as boolean;
          const wrapped: Array<Object> = [true];

          api.setBool(keyArg, valueArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // setString
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.setString", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as string;
          const wrapped: Array<Object> = [true];

          api.setString(keyArg, valueArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // setInt
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.setInt", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = BigInt(args[1] as bigint);
          const wrapped: Array<Object> = [true];

          api.setInt(keyArg, valueArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // setDouble
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.setDouble", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as number;
          const wrapped: Array<Object> = [true];

          api.setDouble(keyArg, valueArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // setEncodedStringList
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.setEncodedStringList", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as string;
          const wrapped: Array<Object> = [true];

          api.setEncodedStringList(keyArg, valueArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // setDeprecatedStringList
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.setDeprecatedStringList", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as Array<string>;
          const wrapped: Array<Object> = [true];

          api.setDeprecatedStringList(keyArg, valueArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // clear
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.clear", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const prefixArg = args[0] as string;
          const allowListArg = args[1] as Array<string> | null;
          const wrapped: Array<Object> = [true];

          api.clear(prefixArg, allowListArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // getAll
  {
    const channel = new BasicMessageChannel<Object>(binaryMessenger, "dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesApi.getAll", api?.getCodec() ?? new StandardMessageCodec());
    if (api != null) {
      channel.setMessageHandler({
        onMessage(message: Object, reply: Reply<Object>): void {
          const args = message as Array<Object>;
          const prefixArg = args[0] as string;
          const allowListArg = args[1] as Array<string>;
          let wrapped: Array<Object>;

          api.getAll(prefixArg, allowListArg).then((result) => {
            wrapped = [result];
            reply.reply(wrapped);
          }).catch((err: Error) => {
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }
}

// Main plugin class
export default class SharedPreferencesOhosPlugin implements FlutterPlugin, SharedPreferencesApi {
  private context: common.ApplicationContext | null = null;
  preferences: data_preferences.Preferences | null = null;
  listEncoder: ListEncoderImpl = new ListEncoderImpl();
  private asyncApiImpl: SharedPreferencesAsyncApiImpl;
  private asyncPreferencesCache: Map<string, data_preferences.Preferences | null> = new Map<string, data_preferences.Preferences | null>();
  private defaultSharedPreferencesName: string = `${PREFERENCES_NAME}_default`;

  constructor() {
    this.asyncApiImpl = new SharedPreferencesAsyncApiImpl(this);
  }

  getUniqueClassName(): string {
    return "SharedPreferencesOhosPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext() as common.ApplicationContext;
    try {
      const flag: bundleManager.BundleFlag = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION;
      const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(flag);
      const bundleName = bundleInfo.name;
      if (bundleName != undefined && bundleName.length > 0) {
        this.defaultSharedPreferencesName = `${bundleName}_preferences`;
      }
    } catch (err) {
      let message = (err as BusinessError).message;
      Log.w(TAG, "getBundleInfoForSelfSync failed: " + message);
    }

    // Register sync API first (doesn't depend on preferences initialization)
    setup(binding.getBinaryMessenger(), this);

    // Initialize preferences and register async API after initialization
    try {
      this.preferences = data_preferences.getPreferencesSync(this.context, { name: PREFERENCES_NAME });
      Log.i(TAG, "Succeeded in getting preferences.");
      this.asyncPreferencesCache.set(PREFERENCES_NAME, this.preferences);
      // Register async API only after preferences are initialized
      setupSharedPreferencesAsyncApi(binding.getBinaryMessenger(), this.asyncApiImpl, '.data_store');
      setupSharedPreferencesAsyncApi(binding.getBinaryMessenger(), this.asyncApiImpl, '.shared_preferences');
    } catch(err) {
      Log.w(TAG, "Failed to get preferences."+ JSON.stringify(err));
      // 缓存null值表示初始化失败
      this.asyncPreferencesCache.set(PREFERENCES_NAME, null);
      // Even if preferences initialization fails, we should still register the async API
      // so that it can properly return errors instead of hanging
      setupSharedPreferencesAsyncApi(binding.getBinaryMessenger(), this.asyncApiImpl, '.data_store');
      setupSharedPreferencesAsyncApi(binding.getBinaryMessenger(), this.asyncApiImpl, '.shared_preferences');
    }
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    // Unregister APIs
  // Unregister APIs
    setup(binding.getBinaryMessenger(), null);
    setupSharedPreferencesAsyncApi(binding.getBinaryMessenger(), null, '.data_store');
    setupSharedPreferencesAsyncApi(binding.getBinaryMessenger(), null, '.shared_preferences');
    this.asyncPreferencesCache.clear();
    this.preferences = null;
    this.context = null;
  }

  private resolveStorageNameForBackend(options: SharedPreferencesPigeonOptions): string {
    if (options.useDataStore) {
      return DATA_STORE_BACKEND_NAME;
    }
    if (options.fileName != undefined && options.fileName.length > 0) {
      return options.fileName;
    }
    return this.defaultSharedPreferencesName;
  }

  async getPreferencesForOptions(options: SharedPreferencesPigeonOptions): Promise<data_preferences.Preferences | null> {
    if (this.context == null) {
      return null;
    }
    const storageName = this.resolveStorageNameForBackend(options);
    const cachedPreferences = this.asyncPreferencesCache.get(storageName);
    if (cachedPreferences != undefined) {
      return cachedPreferences;
    }
    try {
      const preferences = await data_preferences.getPreferences(this.context, { name: storageName });
      this.asyncPreferencesCache.set(storageName, preferences);
      return preferences;
    } catch (err) {
      Log.e(TAG, `Failed to get preferences for ${storageName}: ${JSON.stringify(err)}`);
      // 缓存null值表示创建失败
      this.asyncPreferencesCache.set(storageName, null);
      return Promise.reject(err);
    }
  }

  // Implement setup method required by SharedPreferencesApi interface
  setup(messenger: BinaryMessenger, api: SharedPreferencesApi): void {
    setup(messenger, api);
  }

  // SharedPreferencesApi sync methods implementation
  remove(key: string): boolean {
    try {
      if (this.preferences == null) {
        return false;
      }
      this.preferences.deleteSync(key);
      this.preferences.flushSync();
      return true;
    } catch (err) {
      Log.e(TAG, "Failed to delete. " + JSON.stringify(err));
      return false;
    }
  }

  async setString(key: string, value: string): Promise<void> {
    if (
      value.startsWith(LIST_IDENTIFIER) ||
      value.startsWith(BIG_INTEGER_PREFIX) ||
      value.startsWith(DOUBLE_PREFIX)
    ) {
      return Promise.reject(
        new Error(
          'StorageError: This string cannot be stored as it clashes with special identifier prefixes'
        )
      );
    }
    await this.put(key, value);
  }

  async setInt(key: string, value: bigint): Promise<void> {
    await this.put(key, value);
  }

  private async persistValue(
    preferences: data_preferences.Preferences | null,
    key: string,
    value: PreferenceWriteValue,
    failureMessage: string
  ): Promise<void> {
    if (preferences == null) {
      return Promise.reject(new Error(PREFERENCES_NOT_INITIALIZED_ERROR));
    }
    try {
      await preferences.put(key, value);
      await preferences.flush();
    } catch (err) {
      Log.w(TAG, `${failureMessage}${JSON.stringify(err)}`);
      return Promise.reject(err);
    }
  }

  async put(key: string, value: PreferenceWriteValue): Promise<void> {
    return this.persistValue(this.preferences, key, value, "Failed to put value. ");
  }

  async putWithOptions(key: string, value: PreferenceWriteValue, options: SharedPreferencesPigeonOptions): Promise<void> {
    const preferences = await this.getPreferencesForOptions(options);
    return this.persistValue(preferences, key, value, "Failed to put value with options. ");
  }

  async setDouble(key: string, value: number): Promise<void> {
    await this.put(key, value);
  }

  async setBool(key: string, value: boolean): Promise<void> {
    await this.put(key, value);
  }

  async setEncodedStringList(key: string, value: string): Promise<void> {
    await this.put(key, value);
  }

  async setDeprecatedStringList(key: string, value: string[]): Promise<void> {
    await this.setStringList(key, value);
  }

  async setStringList(key: string, value: string[]): Promise<void> {
    Log.w(TAG, "setStringList :" + value);
    Log.w(TAG, "setStringList encoded:" + (LIST_IDENTIFIER + this.listEncoder.encode(value)));
    await this.put(key, LIST_IDENTIFIER + this.listEncoder.encode(value));
  }

  async setStringListWithOptions(key: string, value: string[], options: SharedPreferencesPigeonOptions): Promise<void> {
    await this.putWithOptions(key, LIST_IDENTIFIER + this.listEncoder.encode(value), options);
  }

  async clear(prefix: string, allowList: string[] | null): Promise<void> {
    try {
      if (this.preferences == null) {
        return Promise.reject(new Error("Preferences not initialized"));
      }
      const allData = await this.preferences.getAll() as Record<string, ExtendedPreferenceValue>;
      const allKeys = Object.keys(allData);
      const deletePromises: Promise<void>[] = [];
      for (let key of allKeys) {
        if (key.startsWith(prefix) && (allowList == null || allowList.indexOf(key) != -1)) {
          deletePromises.push(new Promise<void>((resolve, reject) => {
            this.preferences?.delete(key, (err: ESObject) => {
              if (err) {
                reject(err);
              } else {
                resolve();
              }
            });
          }));
        }
      }
      await Promise.all(deletePromises);
      await this.preferences.flush();
    } catch (err) {
      Log.w(TAG, "Failed to clear." + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  transformPref(value: ExtendedPreferenceValue): ESObject {
    if (typeof value === 'string') {
      if (value.startsWith(JSON_LIST_PREFIX)) {
        return value;
      } else if (value.startsWith(LIST_IDENTIFIER)) {
        try {
          return this.listEncoder.decode(value.substring(LIST_IDENTIFIER.length));
        } catch (err) {
          Log.w(TAG, "Failed to decode legacy list: " + JSON.stringify(err));
          return value;
        }
      }
    }
    if (typeof value === 'bigint') {
      return BigInt(value);
    }
    if (typeof value === 'object' && value !== null) {
      return value;
    }
    return value;
  }

  filterData(value: [string, ExtendedPreferenceValue], prefix: string, allowList: string[] | null): Map<string, Object> {
    const result = new Map<string, Object>();
    const key = value[0];
    const val = value[1];
    if (key.startsWith(prefix) && (allowList == null || allowList.indexOf(key) != -1)) {
      result.set(key, this.transformPref(val));
    }
    return result;
  }

  async getAll(prefix: string, allowList: string[] | null): Promise<Map<string, Object>> {
    try {
      if (this.preferences == null) {
        return new Map<string, Object>();
      }
      const allData = await this.preferences.getAll() as Record<string, ExtendedPreferenceValue>;
      const result = new Map<string, Object>();
      Object.entries(allData).forEach((entry: [string, ExtendedPreferenceValue]) => {
        const filteredData = this.filterData(entry, prefix, allowList);
        filteredData.forEach((value, key) => {
          result.set(key, value);
        });
      });
      return result;
    } catch (err) {
      Log.w(TAG, "Failed to getAll." + JSON.stringify(err));
      return Promise.reject(err);
    }
  }

  getCodec(): MessageCodec<Object> {
    return new StandardMessageCodec();
  }
}
