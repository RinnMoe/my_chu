/*
 * Copyright (c) 2025 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { wrapError } from './Messages';

const TAG = "MessagesAsync";

// Enum for StringListLookupResultType
export enum StringListLookupResultType {
  platformEncoded = 0,
  jsonEncoded = 1,
  unexpectedString = 2
}

// SharedPreferencesPigeonOptions class
export class SharedPreferencesPigeonOptions {
  fileName?: string;
  useDataStore: boolean;

  constructor(fileName?: string, useDataStore: boolean = true) {
    this.fileName = fileName;
    this.useDataStore = useDataStore;
  }

  encode(): Array<Object | null> {
    return [this.fileName ?? null, this.useDataStore];
  }

  static decode(result: Array<Object>): SharedPreferencesPigeonOptions {
    return new SharedPreferencesPigeonOptions(
      result[0] as string | undefined,
      result[1] as boolean
    );
  }
}

// StringListResult class
export class StringListResult {
  jsonEncodedValue?: string;
  type: StringListLookupResultType;

  constructor(jsonEncodedValue?: string, type: StringListLookupResultType = StringListLookupResultType.jsonEncoded) {
    this.jsonEncodedValue = jsonEncodedValue;
    this.type = type;
  }

  encode(): Array<Object | null> {
    return [this.jsonEncodedValue ?? null, this.type];
  }

  static decode(result: Array<Object>): StringListResult {
    return new StringListResult(
      result[0] as string | undefined,
      result[1] as StringListLookupResultType
    );
  }
}
// Custom codec for handling the async API types
class PigeonCodec extends StandardMessageCodec {
  writeValue(stream: ESObject, value: ESObject): ESObject {
    if (typeof value === 'bigint') {
      stream.writeUint8(4);
      stream.writeInt64(value, true);
    } else if (typeof value === 'number') {
      stream.writeUint8(6);
      this.writeAlignment(stream, 8);
      stream.writeFloat64(value, true);
    } else if (value instanceof SharedPreferencesPigeonOptions) {
      stream.writeUint8(130);
      const encoded = (value as SharedPreferencesPigeonOptions).encode();
      return this.writeValue(stream, encoded);
    } else if (value instanceof StringListResult) {
      stream.writeUint8(131);
      const slr = value as StringListResult;
      // Manually write the 2-element list so the enum field is written with the
      // correct type tag (129), matching the Kotlin PigeonCodec on Android.
      stream.writeUint8(12); // list type tag
      this.writeSize(stream, 2); // list length: use variable-length encoding (1 byte for size < 254)
      // Element 0: the JSON-encoded string value
      this.writeValue(stream, slr.jsonEncodedValue ?? null);
      // Element 1: the enum ordinal, encoded as:
      //   byte 129  — custom enum type tag (Dart readValueOfType(129))
      //   byte 4    — _valueInt64 type marker (Flutter StandardMessageCodec)
      //   8 bytes   — int64 value little-endian
      // Matches Android Kotlin: writeValue(stream, value.raw.toLong())
      // Dart readValueOfType(129) calls readValue() which reads type byte 4
      // (_valueInt64) → buffer.getInt64() → int, then indexes into
      // StringListLookupResultType.values[ordinal].
      stream.writeUint8(129);
      stream.writeUint8(4); // _valueInt64 type marker (matches Android Kotlin)
      stream.writeInt64(BigInt(slr.type as number), true); // 8-byte little-endian int64
      return stream;
    } else {
      return super.writeValue(stream, value);
    }
    return stream;
  }


  readValueOfType(type: number, buffer: ESObject): Object | null {
    switch (type) {
      case 129:
        // 处理 StringListLookupResultType 枚举
        const enumValue = this.readValue(buffer) as number | null;
        return enumValue;
      case 130:
        // 处理 SharedPreferencesPigeonOptions
        const optionsData = this.readValue(buffer) as Array<Object>;
        return SharedPreferencesPigeonOptions.decode(optionsData);
      case 131:
        // 处理 StringListResult
        const resultData = this.readValue(buffer) as Array<Object>;
        return StringListResult.decode(resultData);
      default:
        return super.readValueOfType(type, buffer);
    }
  }
}

// SharedPreferencesAsyncApi interface
export interface SharedPreferencesAsyncApi {
  setBool(key: string, value: boolean, options: SharedPreferencesPigeonOptions): Promise<void>;
  setString(key: string, value: string, options: SharedPreferencesPigeonOptions): Promise<void>;
  setInt(key: string, value: bigint, options: SharedPreferencesPigeonOptions): Promise<void>;
  setDouble(key: string, value: number, options: SharedPreferencesPigeonOptions): Promise<void>;
  setEncodedStringList(key: string, value: string, options: SharedPreferencesPigeonOptions): Promise<void>;
  setDeprecatedStringList(key: string, value: Array<string>, options: SharedPreferencesPigeonOptions): Promise<void>;
  getString(key: string, options: SharedPreferencesPigeonOptions): Promise<string | null>;
  getBool(key: string, options: SharedPreferencesPigeonOptions): Promise<boolean | null>;
  getDouble(key: string, options: SharedPreferencesPigeonOptions): Promise<number | null>;
  getInt(key: string, options: SharedPreferencesPigeonOptions): Promise<bigint | null>;
  getPlatformEncodedStringList(key: string, options: SharedPreferencesPigeonOptions): Promise<Array<string> | null>;
  getStringList(key: string, options: SharedPreferencesPigeonOptions): Promise<StringListResult | null>;
  clear(allowList: Array<string> | null, options: SharedPreferencesPigeonOptions): Promise<void>;
  getAll(allowList: Array<string> | null, options: SharedPreferencesPigeonOptions): Promise<Map<string, Object>>;
  getKeys(allowList: Array<string> | null, options: SharedPreferencesPigeonOptions): Promise<Array<string>>;
}

// Setup function for SharedPreferencesAsyncApi
export function setupSharedPreferencesAsyncApi(binaryMessenger: BinaryMessenger, api: SharedPreferencesAsyncApi | null, channelSuffix: string = ''): void {
  const codec = new PigeonCodec();
  {
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.setBool${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as boolean;
          const optionsArg = args[2] as SharedPreferencesPigeonOptions;

          api.setBool(keyArg, valueArg, optionsArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to setBool. message =" + err.message);
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
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.setString${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as string;
          const optionsArg = args[2] as SharedPreferencesPigeonOptions;

          api.setString(keyArg, valueArg, optionsArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to setString. message =" + err.message);
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
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.setInt${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = BigInt(args[1] as bigint);
          const optionsArg = args[2] as SharedPreferencesPigeonOptions;

          api.setInt(keyArg, valueArg, optionsArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to setInt. message =" + err.message);
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
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.setDouble${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as number;
          const optionsArg = args[2] as SharedPreferencesPigeonOptions;

          api.setDouble(keyArg, valueArg, optionsArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to setDouble. message =" + err.message);
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
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.setEncodedStringList${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as string;
          const optionsArg = args[2] as SharedPreferencesPigeonOptions;

          api.setEncodedStringList(keyArg, valueArg, optionsArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to setEncodedStringList. message =" + err.message);
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
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.setDeprecatedStringList${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const valueArg = args[1] as Array<string>;
          const optionsArg = args[2] as SharedPreferencesPigeonOptions;

          api.setDeprecatedStringList(keyArg, valueArg, optionsArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to setDeprecatedStringList. message =" + err.message);
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // getString
  {
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.getString${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.getString(keyArg, optionsArg).then((result) => {
            wrapped.push(result);
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to getString. message =" + err.message);
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // getBool
  {
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.getBool${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.getBool(keyArg, optionsArg).then((result) => {
            wrapped.push(result);
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to getBool. message =" + err.message);
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // getDouble
  {
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.getDouble${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.getDouble(keyArg, optionsArg).then((result) => {
            wrapped.push(result);
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to getDouble. message =" + err.message);
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // getInt
  {
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.getInt${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.getInt(keyArg, optionsArg).then((result) => {
            wrapped.push(result);
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to getInt. message =" + err.message);
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // getPlatformEncodedStringList
  {
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.getPlatformEncodedStringList${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.getPlatformEncodedStringList(keyArg, optionsArg).then((result) => {
            wrapped.push(result);
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to getPlatformEncodedStringList. message =" + err.message);
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // getStringList
  {
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.getStringList${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const keyArg = args[0] as string;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.getStringList(keyArg, optionsArg).then((result) => {
            wrapped.push(result);
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to getStringList. message =" + err.message);
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
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.clear${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const allowListArg = args[0] as Array<string> | null;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.clear(allowListArg, optionsArg).then(() => {
            reply.reply(wrapped);
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to clear. message =" + err.message);
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
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.getAll${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const allowListArg = args[0] as Array<string> | null;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.getAll(allowListArg, optionsArg).then((result) => {
            if (result == null) {
              const error = new Error('Host platform returned null value for non-null return value.');
              const errs = wrapError(error);
              reply.reply(errs);
            } else {
              wrapped.push(result);
              reply.reply(wrapped);
            }
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to getAll. message =" + err.message);
            const errs = wrapError(err);
            reply.reply(errs);
          });
        }
      });
    } else {
      channel.setMessageHandler(null);
    }
  }

  // getKeys
  {
    const channelName = `dev.flutter.pigeon.shared_preferences_ohos.SharedPreferencesAsyncApi.getKeys${channelSuffix}`;
    const channel = new BasicMessageChannel<Object>(binaryMessenger, channelName, codec);
    if (api != null) {
      channel.setMessageHandler({
        onMessage(msg: Object, reply: Reply<Object>): void {
          const wrapped = new Array<Object>();
          const args = msg as Array<Object>;
          const allowListArg = args[0] as Array<string> | null;
          const optionsArg = args[1] as SharedPreferencesPigeonOptions;

          api.getKeys(allowListArg, optionsArg).then((result) => {
            if (result == null) {
              const error = new Error('Host platform returned null value for non-null return value.');
              const errs = wrapError(error);
              reply.reply(errs);
            } else {
              wrapped.push(result);
              reply.reply(wrapped);
            }
          }).catch((err: Error) => {
            Log.w(TAG, "Failed to getKeys. message =" + err.message);
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