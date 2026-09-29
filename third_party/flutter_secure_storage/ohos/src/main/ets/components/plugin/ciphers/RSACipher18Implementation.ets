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
import KeyCipher from './KeyCipher';
import { huks } from '@kit.UniversalKeystoreKit';

const TAG = 'SecureStorage::RSACipher18Implementation';

export default class RSACipher18Implementation implements KeyCipher {
  private SECRET_RSA_KEY_ALIAS: string = 'FlutterSecureRSAKeyAlias';
  protected context: Context | null = null;

  constructor(context: Context) {
    this.context = context;
  }

  async RSAEncrypt(key: cryptoFramework.Key): Promise<Uint8Array> {
    await this.createRSAKeysIfNeeded();
    let data: Uint8Array = key.getEncoded().data;
    let options: huks.HuksOptions = {
      properties: this.getRsaEncryptProperties(),
      inData: data,
    }
    return this.dataEncrypt(options);
  }

  protected async dataEncrypt(options: huks.HuksOptions): Promise<Uint8Array> {
    // 调用initSession获取handle
    let handle: number | null = null;
    await huks.initSession(this.SECRET_RSA_KEY_ALIAS, options)
      .then((data) => {
        handle = data.handle;
      }).catch((error: Error) => {
        console.error(TAG, `promise: init EncryptDataRsa failed, ${JSON.stringify(error)}`);
      });

    // 调用finishSession获取加密后的密文
    let outData: Uint8Array | null = null;
    if (handle != null) {
      await huks.finishSession(handle, options)
        .then((data) => {
          outData = data.outData as Uint8Array;
        }).catch((error: Error) => {
          console.error(TAG, `promise: encrypt data failed, ${JSON.stringify(error)}`);
        });
      if (outData != null) {
        return outData;
      }
    }
    throw new Error(`${TAG} -> RSAEncrypt: 加密失败`);
  }

  async RSADecrypt(wrappedKey: Uint8Array, algorithm: string): Promise<cryptoFramework.Key> {
    await this.createRSAKeysIfNeeded();
    let options: huks.HuksOptions = {
      properties: this.getRsaDecryptProperties(),
      inData: wrappedKey,
    }
    return this.dataDecrypt(options, algorithm);
  }

  protected async dataDecrypt(options: huks.HuksOptions, algorithm: string): Promise<cryptoFramework.Key> {
    // 调用initSession获取handle
    let handle: number | null = null;
    await huks.initSession(this.SECRET_RSA_KEY_ALIAS, options)
      .then((data) => {
        handle = data.handle;
      }).catch((error: Error) => {
        console.error(TAG, `promise: init DecryptDataRsa failed, ${JSON.stringify(error)}`);
      });

    if (handle === null) {
      throw new Error(`${TAG} -> RSADecrypt: 初始化解密失败`);
    }

    // 调用finishSession获取解密后的数据
    let outData: Uint8Array | null = null;
    await huks.finishSession(handle, options)
      .then((data) => {
        outData = data.outData as Uint8Array;
      }).catch((error: Error) => {
        console.error(TAG, `promise: decrypt data failed, ${JSON.stringify(error)}`);
      })

    if (outData != null) {
      return this.getKey({
        data: outData
      }, algorithm);
    }
    throw new Error(`${TAG} -> RSADecrypt: 解密失败`);
  }

  // 把 DataBlob 转为 Key
  protected getKey(keyBlob: cryptoFramework.DataBlob, algorithm: string): cryptoFramework.Key {
    let symKeyGenerator = cryptoFramework.createSymKeyGenerator(algorithm);
    let symKey: cryptoFramework.Key = symKeyGenerator.convertKeySync(keyBlob);
    return symKey;
  }

  protected async createRSAKeysIfNeeded() {
    let huksOptions: huks.HuksOptions = {
      properties: []
    }

    // 判断密钥是否存在
    await huks.hasKeyItem(this.SECRET_RSA_KEY_ALIAS, huksOptions).then(async (data) => {
      if (data) {
      } else {
        await this.generateKeyItem();
      }
    }).catch(async (error: Error) => {
      console.error(TAG, `callback: hasKeyItem input arg invalid, ` + JSON.stringify(error));
      await this.generateKeyItem();
    });
  }

  async removePreferencesKey() {
    let huksOptions: huks.HuksOptions = {
      properties: []
    }

    try {
      huks.deleteKeyItem(this.SECRET_RSA_KEY_ALIAS, huksOptions, (error, data) => {
        if (error) {
          console.error(TAG, `deleteKeyItem: ` + JSON.stringify(error));
        } else {
        }
      });
    } catch (error) {
      console.error(TAG, `removePreferencesKey: ` + JSON.stringify(error));
    }
  }

  /////////////////////////////////////////ohos.security.huks//////////////////////////////////////

  protected getRsaGenerateProperties(): Array<huks.HuksParam> {
    let properties: Array<huks.HuksParam> = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_RSA
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_RSA_KEY_SIZE_2048
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    }];
    return properties;
  }

  protected getRsaEncryptProperties(): Array<huks.HuksParam> {
    let properties: Array<huks.HuksParam> = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_RSA
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_RSA_KEY_SIZE_2048
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT
    }, {
      tag: huks.HuksTag.HUKS_TAG_PADDING,
      value: huks.HuksKeyPadding.HUKS_PADDING_PKCS1_V1_5
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_ECB
    }, {
      tag: huks.HuksTag.HUKS_TAG_DIGEST,
      value: huks.HuksKeyDigest.HUKS_DIGEST_NONE
    }];
    return properties;
  }

  protected getRsaDecryptProperties(): Array<huks.HuksParam> {
    let properties: Array<huks.HuksParam> = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_RSA
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_RSA_KEY_SIZE_2048
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    }, {
      tag: huks.HuksTag.HUKS_TAG_PADDING,
      value: huks.HuksKeyPadding.HUKS_PADDING_PKCS1_V1_5
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_ECB
    }, {
      tag: huks.HuksTag.HUKS_TAG_DIGEST,
      value: huks.HuksKeyDigest.HUKS_DIGEST_NONE
    }];
    return properties;
  }

  /**
   * 生成密钥
   */
  protected async generateKeyItem() {
    let genProperties = this.getRsaGenerateProperties();
    let options: huks.HuksOptions = {
      properties: genProperties
    }

    await huks.generateKeyItem(this.SECRET_RSA_KEY_ALIAS, options)
      .then(() => {
      }).catch((error: Error) => {
        console.error(TAG, `promise: generate RSA Key failed, ${JSON.stringify(error)}`);
      });
  }
}
