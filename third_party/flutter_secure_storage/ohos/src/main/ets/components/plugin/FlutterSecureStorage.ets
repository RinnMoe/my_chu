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

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

import { StorageCipherFactory } from './ciphers/StorageCipherFactory';
import StorageCipher from './ciphers/StorageCipher';
import { convertObjectToMap, StringToUint8Array, Uint8ArrayToString } from './utils';

interface KeyPrefixInterface {
  get getKeyPrefix(): string;
  set setKeyPrefix(value: string);
}

const TAG: string = "SecureStorage::FlutterSecureStorage";

export default class FlutterSecureStorage implements KeyPrefixInterface {
  private context: Context | null = null;
  protected ELEMENT_PREFERENCES_KEY_PREFIX: string = "";
  public options: Map<String, Object> = new Map();
  private SHARED_PREFERENCES_NAME: string = "FlutterSecureStorage";
  private dataPreferences: preferences.Preferences | null = null;
  private storageCipher: StorageCipher | null = null;
  private storageCipherFactory: StorageCipherFactory | null = null;
  base64: util.Base64Helper = new util.Base64Helper();

  // 新增：监听器注册表
  private listeners: Map<string, Set<(value: string | null) => void>> = new Map();

  constructor(context: Context, options: Map<String, Object>) {
    this.context = context;
    this.options = options;
    this.setKeyPrefix = 'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg';
  }

  // 新增：注册监听器
  public registerListener(key: string, listener: (value: string | null) => void): void {
    if (!this.listeners.has(key)) {
      this.listeners.set(key, new Set());
    }
    this.listeners.get(key)?.add(listener);
  }

  // 新增：注销监听器
  public unregisterListener(key: string, listener?: (value: string | null) => void): void {
    if (!this.listeners.has(key)) return;

    if (listener) {
      this.listeners.get(key)?.delete(listener);
    } else {
      this.listeners.delete(key);
    }
  }

  // 新增：通知监听器
  private notifyListeners(key: string, value: string | null): void {
    const listeners = this.listeners.get(key);
    if (listeners) {
      listeners.forEach(listener => {
        try {
          listener(value);
        } catch (e) {
          console.error(TAG, `Listener error for key ${key}: ${e}`);
        }
      });
    }
  }

  public async write(key: string, value: string) {
    try {
      this.ensureInitialized();
      if (!this.dataPreferences || !this.storageCipher) {
        throw new Error('Secure storage is unavailable');
      }

      let result = await this.storageCipher.encrypt({data: StringToUint8Array(value)});
      let resultStr = this.base64.encodeToStringSync(result.data);

      await this.dataPreferences.put(key, resultStr);
      this.storageCipherFactory?.storeCurrentAlgorithms(this.dataPreferences);
      await this.dataPreferences.flush();
      this.notifyListeners(key, value); // 新增：触发监听器
    } catch (e) {
      console.error(TAG, 'Secure storage write failed');
      this.notifyListeners(key, null); // 新增：失败时通知监听器
      throw new Error('Secure storage write failed');
    }
  }

  public async read(key: string): Promise<string> {
    try {
      this.ensureInitialized();
      if (!this.dataPreferences) {
        throw new Error('Secure storage is unavailable');
      }
      let result: preferences.ValueType = this.dataPreferences.getSync(key, null);
      if (result === null) {
        return '';
      }
      result = await this.decodeRawValue(result as string);
      return result;
    } catch (e) {
      console.error(TAG, 'Secure storage read failed');
      throw new Error('Secure storage read failed');
    }
  }

  get getKeyPrefix(): string {
    return this.ELEMENT_PREFERENCES_KEY_PREFIX;
  }

  set setKeyPrefix(key: string) {
    this.ELEMENT_PREFERENCES_KEY_PREFIX = key;
  }

  public async readAll(): Promise<Map<string, string>>{
    let all: Map<string, string> =  new Map();
    try {
      this.ensureInitialized();
      if (!this.dataPreferences) {
        throw new Error('Secure storage is unavailable');
      }

      let raw: Object = this.dataPreferences.getAllSync();
      let rawMap = convertObjectToMap(raw);
      let promises: Promise<void>[] = [];

      if(!rawMap.size) return all;
      rawMap.forEach((rawVal, rawKey) => {
        const keyPrefix = this.getKeyPrefix + '_';
        if (rawKey.startsWith(keyPrefix)) {
          const identifier = rawKey.substring(keyPrefix.length);
          const valuePromise: Promise<string> = this.decodeRawValue(rawVal);
          promises.push(valuePromise.then((value: string) => {
            all.set(identifier, value);
          }))
        }
      })
      await Promise.all(promises);
    } catch (e) {
      console.error(TAG, 'Secure storage readAll failed');
      throw new Error('Secure storage readAll failed');
    }
    return all;
  }

  public async delete(key: string) {
    try {
      this.ensureInitialized();
      if (!this.dataPreferences) {
        throw new Error('Secure storage is unavailable');
      }

      await this.dataPreferences.delete(key);
      await this.dataPreferences.flush();
      this.notifyListeners(key, null); // 新增：触发监听器
    } catch (e) {
      console.error(TAG, 'Secure storage delete failed');
      this.notifyListeners(key, null); // 新增：失败时通知监听器
      throw new Error('Secure storage delete failed');
    }
  }

  public async deleteAll() {
    try {
      this.ensureInitialized();
      if (!this.dataPreferences) {
        throw new Error('Secure storage is unavailable');
      }

      let raw: Object = this.dataPreferences.getAllSync();
      let rawMap = convertObjectToMap(raw);

      rawMap.forEach((rawVal, rawKey) => {
        const keyPrefix = this.getKeyPrefix + '_';
        if (rawKey.startsWith(keyPrefix)) {
          this.dataPreferences?.deleteSync(rawKey);
        }
      })

      await this.dataPreferences.flush();
      this.listeners.forEach((listeners, key) => {
        listeners.forEach(listener => listener(null)); // 新增：触发所有监听器
      });
    } catch (e) {
      console.error(TAG, 'Secure storage deleteAll failed');
      this.listeners.forEach((listeners, key) => {
        listeners.forEach(listener => listener(null)); // 新增：失败时触发所有监听器
      });
      throw new Error('Secure storage deleteAll failed');
    }
  }

  public containsKey(key: string): boolean {
    this.ensureInitialized();
    if (this.dataPreferences) {
      return this.dataPreferences.hasSync(key);
    } else {
      throw new Error('Secure storage is unavailable');
    }
  }

  private ensureInitialized() {
    if(this.dataPreferences && this.storageCipher) return;
    this.ensureOptions();
    // 创建 preferences
    let nonEncryptedPreferences: preferences.Preferences = preferences.getPreferencesSync(this.context, { name: this.SHARED_PREFERENCES_NAME});
    // 初始化 storageCipher
    if (this.storageCipher == null) {
      this.initStorageCipher(nonEncryptedPreferences);
      if (!this.storageCipher) {
        throw new Error('Secure storage cipher is unavailable');
      }
    }
    this.dataPreferences = nonEncryptedPreferences;
  }

  protected ensureOptions() {
    if (this.options.has("sharedPreferencesName") && this.options.get("sharedPreferencesName")) {
      this.SHARED_PREFERENCES_NAME = this.options.get("sharedPreferencesName") as string;
    }

    if (this.options.has("preferencesKeyPrefix") && this.options.get("preferencesKeyPrefix")) {
      this.setKeyPrefix = this.options.get("preferencesKeyPrefix") as string;
    }
  }

  private initStorageCipher(source: preferences.Preferences) {
    this.storageCipherFactory = new StorageCipherFactory(source, this.options);

    // 如果需要重新加密
    if (this.storageCipherFactory.requiresReEncryption()) {
      throw new Error('Secure storage algorithm migration is required');
    } else {
      this.storageCipher = this.storageCipherFactory.getCurrentStorageCipher(this.context as Context);
    }
  }

  private async reEncryptPreferences(storageCipherFactory: StorageCipherFactory, source: preferences.Preferences) {
    try {
      this.storageCipher = storageCipherFactory.getSavedStorageCipher(this.context as Context);
      let raw: Object = await source.getAll();
      let cache: Map<string, string> = new Map();
      let rawMap = convertObjectToMap(raw);
      let promises: Promise<void>[] = [];

      rawMap.forEach(async (rawVal, rawKey) => {
        if (rawKey.includes(this.getKeyPrefix) && typeof rawVal == 'string') {
          const valuePromise = this.decodeRawValue(rawVal);
          promises.push(valuePromise.then((value: string) => {
            cache.set(rawKey, value);
          }))
        }
      })

      await Promise.all(promises);

      // 如果密钥算法更新了,应该删除密钥缓存中的key,value,重新加密后存储
      await storageCipherFactory.removeSaveAlgorithms(this.context as Context);

      this.storageCipher = storageCipherFactory.getCurrentStorageCipher(this.context as Context);
      let dataPreferencesPromises: Promise<void>[] = [];
      dataPreferencesPromises = Array.from(cache.keys()).map(async (key) => {
        if(!this.storageCipher || !this.dataPreferences) return;
        let val = cache.get(key);
        if (!val) return; // 检查缓存中是否包含该键

        try {
          let result: cryptoFramework.DataBlob | undefined = await this.storageCipher.encrypt({data: StringToUint8Array(val)});
          let resultBlob = this.base64.encodeToStringSync(result?.data);
          await this.dataPreferences.put(key, resultBlob);
        } catch (e) {
          console.error(TAG, `re-encryption after modifying the algorithm failure. code =${e.code}, message =${e.message}`);
        }
      })

      await Promise.all(dataPreferencesPromises);
      storageCipherFactory.storeCurrentAlgorithms(this.dataPreferences as preferences.Preferences);
      await this.dataPreferences?.flush();
    } catch (e) {
      console.error(TAG, `re-encryption failure. code =${e.code}, message =${e.message}`);
      this.storageCipher = storageCipherFactory.getSavedStorageCipher(this.context as Context);
    }
  }

  public getResetOnError(): boolean {
    return this.options.has("resetOnError") && !!this.options?.get("resetOnError");
  }

  private async decodeRawValue(value: string): Promise<string> {
    if (!value || !this.storageCipher) {
      throw new Error('Secure storage ciphertext is unavailable');
    }
    let data = this.base64.decodeSync(value);
    let result = await this.storageCipher.decrypt({data});
    return Uint8ArrayToString(result.data);
  }
}
