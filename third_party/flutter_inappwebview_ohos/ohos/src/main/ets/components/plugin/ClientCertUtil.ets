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

import fs from '@ohos.file.fs';
import util from '@ohos.util';
import InAppWebViewFlutterPlugin from './InAppWebViewFlutterPlugin';
import common from '@ohos.app.ability.common';
import { Log } from '@ohos/flutter_ohos';

const TAG = 'ClientCertUtil';

export interface ClientCertConfirmPaths {
  priKeyFile: string;
  certChainFile: string;
}

export interface ClientCertHttpPaths {
  certPath: string;
  keyPath: string;
  caPath: string | null;
  /** 'PEM' (default) or 'P12' for @ohos.net.http CertType. */
  certType: string;
  keyPassword: string;
}

export default class ClientCertUtil {
  static resolveClientCertConfirmPaths(
    plugin: InAppWebViewFlutterPlugin,
    context: common.Context,
    certificatePath: string,
    certificatePassword: string | null,
    keyStoreType: string
  ): ClientCertConfirmPaths | null {
    try {
      if (keyStoreType != null && keyStoreType.toUpperCase() === 'PKCS12') {
        let companionPaths = ClientCertUtil.resolvePkcs12CompanionPaths(
          plugin, context, certificatePath);
        if (companionPaths != null) {
          return companionPaths;
        }
      }

      if (ClientCertUtil.looksLikePemPrivateKeyPath(certificatePath)) {
        let chainPath = ClientCertUtil.companionChainPathFor(certificatePath);
        let keyPem = ClientCertUtil.readFlutterAssetText(plugin, context, certificatePath);
        let chainPem = ClientCertUtil.readFlutterAssetText(plugin, context, chainPath);
        if (keyPem != null && chainPem != null) {
          return ClientCertUtil.writeConfirmPaths(context, certificatePath, keyPem, chainPem);
        }
      }

      Log.e(TAG, 'Unable to resolve client certificate files for ' + certificatePath);
      return null;
    } catch (e) {
      Log.e(TAG, 'resolveClientCertConfirmPaths failed: ' + JSON.stringify(e));
      return null;
    }
  }

  static resolveHttpClientCertPaths(
    plugin: InAppWebViewFlutterPlugin,
    context: common.Context,
    certificatePath: string,
    keyStoreType: string,
    certificatePassword: string | null = null
  ): ClientCertHttpPaths | null {
    // Prefer native P12/PFX for @ohos.net.http when the Flutter asset is PKCS12.
    if (keyStoreType != null && keyStoreType.toUpperCase() === 'PKCS12') {
      let p12Path = ClientCertUtil.copyFlutterAssetBinary(plugin, context, certificatePath);
      if (p12Path != null) {
        let caAssetPath = ClientCertUtil.companionCaPathFor(certificatePath);
        let caPath: string | null = null;
        if (ClientCertUtil.readFlutterAssetText(plugin, context, caAssetPath) != null) {
          let caPem = ClientCertUtil.readFlutterAssetText(plugin, context, caAssetPath)!;
          caPath = ClientCertUtil.writeSinglePemFile(context, certificatePath + '.ca', caPem);
        }
        return {
          certPath: p12Path,
          keyPath: '',
          caPath: caPath,
          certType: 'P12',
          keyPassword: certificatePassword ?? '',
        };
      }
    }

    let confirmPaths = ClientCertUtil.resolveClientCertConfirmPaths(
      plugin, context, certificatePath, certificatePassword, keyStoreType);
    if (confirmPaths == null) {
      return null;
    }
    let caAssetPath = ClientCertUtil.companionCaPathFor(certificatePath);
    let caPath: string | null = null;
    if (ClientCertUtil.readFlutterAssetText(plugin, context, caAssetPath) != null) {
      let caPem = ClientCertUtil.readFlutterAssetText(plugin, context, caAssetPath)!;
      caPath = ClientCertUtil.writeSinglePemFile(context, certificatePath + '.ca', caPem);
    }
    return {
      certPath: confirmPaths.certChainFile,
      keyPath: confirmPaths.priKeyFile,
      caPath: caPath,
      certType: 'PEM',
      keyPassword: certificatePassword ?? '',
    };
  }

  private static companionCaPathFor(certificatePath: string): string {
    if (certificatePath.toLowerCase().endsWith('.pfx') ||
      certificatePath.toLowerCase().endsWith('.p12')) {
      let dotIndex = certificatePath.lastIndexOf('.');
      return certificatePath.substring(0, dotIndex) + '-ca.pem';
    }
    return certificatePath + '.ca.pem';
  }

  private static writeSinglePemFile(context: common.Context, cacheKey: string, pem: string): string {
    let safeName = cacheKey.replace(/[^a-zA-Z0-9._-]/g, '_');
    let path = `${context.filesDir}/inappwebview_client_${safeName}.pem`;
    ClientCertUtil.writeTextFile(path, pem.endsWith('\n') ? pem : pem + '\n');
    return path;
  }

  private static resolvePkcs12CompanionPaths(
    plugin: InAppWebViewFlutterPlugin,
    context: common.Context,
    certificatePath: string
  ): ClientCertConfirmPaths | null {
    let chainAssetPath = ClientCertUtil.companionChainPathFor(certificatePath);
    let chainPem = ClientCertUtil.readFlutterAssetText(plugin, context, chainAssetPath);
    // Prefer PKCS#8 private key for ArkWeb / @ohos.net.http PEM client cert.
    let keyPkcs8Path = ClientCertUtil.companionPkcs8KeyPathFor(certificatePath);
    let keyPem = ClientCertUtil.readFlutterAssetText(plugin, context, keyPkcs8Path);
    if (keyPem == null) {
      let keyAssetPath = ClientCertUtil.companionKeyPathFor(certificatePath);
      keyPem = ClientCertUtil.readFlutterAssetText(plugin, context, keyAssetPath);
    }
    if (keyPem == null || chainPem == null) {
      return null;
    }
    return ClientCertUtil.writeConfirmPaths(context, certificatePath, keyPem, chainPem);
  }

  private static companionPkcs8KeyPathFor(certificatePath: string): string {
    if (certificatePath.toLowerCase().endsWith('.pfx') ||
      certificatePath.toLowerCase().endsWith('.p12')) {
      let dotIndex = certificatePath.lastIndexOf('.');
      return certificatePath.substring(0, dotIndex) + '-client.key.pkcs8.pem';
    }
    return certificatePath + '.pkcs8.pem';
  }

  private static companionKeyPathFor(certificatePath: string): string {
    if (certificatePath.toLowerCase().endsWith('.pfx') ||
      certificatePath.toLowerCase().endsWith('.p12')) {
      let dotIndex = certificatePath.lastIndexOf('.');
      return certificatePath.substring(0, dotIndex) + '-client.key.pem';
    }
    return certificatePath;
  }

  private static companionChainPathFor(certificatePath: string): string {
    if (certificatePath.toLowerCase().endsWith('.pfx') ||
      certificatePath.toLowerCase().endsWith('.p12')) {
      let dotIndex = certificatePath.lastIndexOf('.');
      return certificatePath.substring(0, dotIndex) + '-client.chain.pem';
    }
    if (certificatePath.endsWith('.key.pem')) {
      return certificatePath.replace(/\.key\.pem$/, '.chain.pem');
    }
    return certificatePath + '.chain.pem';
  }

  private static looksLikePemPrivateKeyPath(certificatePath: string): boolean {
    return certificatePath.endsWith('.key.pem') || certificatePath.endsWith('.pem');
  }

  private static readFlutterAssetText(
    plugin: InAppWebViewFlutterPlugin,
    context: common.Context,
    assetPath: string
  ): string | null {
    if (plugin.flutterAssets == null) {
      return null;
    }
    try {
      let rawPath = plugin.flutterAssets.getAssetFilePathByName(assetPath);
      let content = context.resourceManager.getRawFileContentSync(rawPath);
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(content.buffer));
    } catch (e) {
      Log.w(TAG, 'readFlutterAssetText failed for ' + assetPath + ': ' + JSON.stringify(e));
      return null;
    }
  }

  private static copyFlutterAssetBinary(
    plugin: InAppWebViewFlutterPlugin,
    context: common.Context,
    assetPath: string
  ): string | null {
    if (plugin.flutterAssets == null) {
      return null;
    }
    try {
      let rawPath = plugin.flutterAssets.getAssetFilePathByName(assetPath);
      let content = context.resourceManager.getRawFileContentSync(rawPath);
      let bytes = new Uint8Array(content.buffer);
      let safeName = assetPath.replace(/[^a-zA-Z0-9._-]/g, '_');
      let outPath = `${context.filesDir}/inappwebview_client_${safeName}`;
      let file: fs.File | null = null;
      try {
        file = fs.openSync(outPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, bytes.buffer);
      } finally {
        if (file != null) {
          fs.closeSync(file);
        }
      }
      return outPath;
    } catch (e) {
      Log.w(TAG, 'copyFlutterAssetBinary failed for ' + assetPath + ': ' + JSON.stringify(e));
      return null;
    }
  }

  private static writeConfirmPaths(
    context: common.Context,
    cacheKey: string,
    keyPem: string,
    chainPem: string
  ): ClientCertConfirmPaths {
    let safeName = cacheKey.replace(/[^a-zA-Z0-9._-]/g, '_');
    let baseDir = context.filesDir;
    let priKeyFile = `${baseDir}/inappwebview_client_${safeName}.key.pem`;
    let certChainFile = `${baseDir}/inappwebview_client_${safeName}.chain.pem`;
    ClientCertUtil.writeTextFile(priKeyFile, keyPem.endsWith('\n') ? keyPem : keyPem + '\n');
    ClientCertUtil.writeTextFile(certChainFile, chainPem.endsWith('\n') ? chainPem : chainPem + '\n');
    return { priKeyFile: priKeyFile, certChainFile: certChainFile };
  }

  private static writeTextFile(path: string, content: string): void {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'writeTextFile failed: ' + path + ', ' + JSON.stringify(err));
      throw new Error(err.message);
    } finally {
      if (file != null) {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          let closeError: Error = closeErr as Error;
          Log.e(TAG, 'writeTextFile close failed: ' + path + ', ' + JSON.stringify(closeError));
        }
      }
    }
  }
}
