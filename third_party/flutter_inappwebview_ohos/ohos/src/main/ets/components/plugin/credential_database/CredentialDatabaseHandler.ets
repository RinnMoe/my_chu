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

import { Any, MethodCall, MethodChannel } from '@ohos/flutter_ohos';
import InAppWebViewFlutterPlugin from '../InAppWebViewFlutterPlugin';
import ChannelDelegateImpl from '../types/ChannelDelegateImpl';
import ChannelResultUtil from '../types/ChannelResultUtil';
import CredentialDatabase from './CredentialDatabase';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import List from '@ohos.util.List';
import web_webview from '@ohos.web.webview'

const TAG = "CredentialDatabaseHandler"
const METHOD_CHANNEL_NAME = "com.pichillilorenzo/flutter_inappwebview_credential_database"

export default class CredentialDatabaseHandler extends ChannelDelegateImpl {
  public credentialDatabase: CredentialDatabase | null = null
  public plugin: InAppWebViewFlutterPlugin | null

  constructor(plugin: InAppWebViewFlutterPlugin) {
    if (plugin.messenger == null) {
      throw new Error('CredentialDatabaseHandler: plugin.messenger is null');
    }
    super(new MethodChannel(plugin.messenger, METHOD_CHANNEL_NAME))
    this.plugin = plugin
  }

  public init(plugin: InAppWebViewFlutterPlugin): void {
    if (this.credentialDatabase == null) {
      this.credentialDatabase = CredentialDatabase.getInstance(plugin.applicationContext!);
    }
  }

  public onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      if (this.plugin != null) {
        this.init(this.plugin);
      }

      switch (call.method) {
        case "getAllAuthCredentials":
          if (this.credentialDatabase != null) {
            this.getAllAuthCredentials(result).catch((e: Error) =>
            result.error("getAllAuthCredentials", e?.message ?? String(e), null));
          } else {
            result.success([]);
          }
          break;
        case "getHttpAuthCredentials":
          if (this.credentialDatabase != null) {
            this.getHttpAuthCredentials(call, result).catch((e: Error) =>
            result.error("getHttpAuthCredentials", e?.message ?? String(e), null));
          } else {
            result.success([]);
          }
          break;
        case "setHttpAuthCredential":
          if (this.credentialDatabase != null) {
            this.setHttpAuthCredential(call, result).catch((e: Error) =>
            result.error("setHttpAuthCredential", e?.message ?? String(e), null));
          } else {
            result.success(false);
          }
          break;
        case "removeHttpAuthCredential":
          if (this.credentialDatabase != null) {
            this.removeHttpAuthCredential(call, result).catch((e: Error) =>
            result.error("removeHttpAuthCredential", e?.message ?? String(e), null));
          } else {
            result.success(false);
          }
          break;
        case "removeHttpAuthCredentials":
          if (this.credentialDatabase != null) {
            this.removeHttpAuthCredentials(call, result).catch((e: Error) =>
            result.error("removeHttpAuthCredentials", e?.message ?? String(e), null));
          } else {
            result.success(false);
          }
          break;
        case "clearAllAuthCredentials":
          if (this.credentialDatabase != null) {
            this.clearAllAuthCredentials(result).catch((e: Error) =>
            result.error("clearAllAuthCredentials", e?.message ?? String(e), null));
          } else {
            result.success(false);
          }
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      let err: Error = e as Error;
      ChannelResultUtil.reportError(TAG, call.method, result, err as Object);
    }
  }

  private async getAllAuthCredentials(result: MethodResult){
    let allCredentials: List<Map<string, Any>> = new List<Map<string, Any>>();
    if (this.credentialDatabase != null) {
      let protectionSpaces = await this.credentialDatabase!.protectionSpaceDao.getAll();
      for (const item of protectionSpaces) {
        let credentials: List<Map<string, Any>> = new List<Map<string, Any>>();
        let urlCredentials = await this.credentialDatabase!.credentialDao.getAllByProtectionSpaceId(item.getId()!)
        const protectionSpaceMap: Map<string, Any> = await item.toMap();
        urlCredentials.forEach(credential => {
          credentials.add(credential.toMap());
        })
        let obj : Map<string, Any> = new Map<string, Any>();
        obj.set("protectionSpace", protectionSpaceMap);
        obj.set("credentials", credentials);
        allCredentials.add(obj);
      }
    }
    result.success(allCredentials);
  }

  private async setHttpAuthCredential(call: MethodCall, result: MethodResult) {
    let host: string = call.argument("host") as string;
    let protocol: string = call.argument("protocol") as string;
    let realm: string | null = call.argument("realm") as string | null;
    let port: number = call.argument("port") as number;
    let username: string = call.argument("username") as string;
    let password: string = call.argument("password") as string;
    await this.credentialDatabase!.setHttpAuthCredential(host, protocol, realm, port, username, password);
    result.success(true);
  }

  private async removeHttpAuthCredential(call: MethodCall, result: MethodResult) {
    let host: string = call.argument("host") as string;
    let protocol: string = call.argument("protocol") as string;
    let realm: string | null = call.argument("realm") as string | null;
    let port: number = call.argument("port") as number;
    let username: string = call.argument("username") as string;
    let password: string = call.argument("password") as string;
    await this.credentialDatabase!.removeHttpAuthCredential(host, protocol, realm, port, username, password);
    result.success(true);
  }

  private async removeHttpAuthCredentials(call: MethodCall, result: MethodResult) {
    let host: string = call.argument("host") as string;
    let protocol: string = call.argument("protocol") as string;
    let realm: string | null = call.argument("realm") as string | null;
    let port: number = call.argument("port") as number;
    await this.credentialDatabase!.removeHttpAuthCredentials(host, protocol, realm, port);
    result.success(true);
  }

  private async clearAllAuthCredentials(result: MethodResult) {
    await this.credentialDatabase!.clearAllAuthCredentials();
    if (this.plugin != null && this.plugin.applicationContext != null) {
      web_webview.WebDataBase.deleteHttpAuthCredentials();
    }
    result.success(true);
  }

  private async getHttpAuthCredentials(call: MethodCall, result: MethodResult) {
    let credentials: List<Map<string, Any>> = new List<Map<string, Any>>();
    if (this.credentialDatabase != null) {
      let host: string = call.argument("host") as string;
      let protocol: string = call.argument("protocol") as string;
      let realm: string | null = call.argument("realm") as string | null;
      let port: number = call.argument("port") as number;
      let urlCredentials = await this.credentialDatabase!.getHttpAuthCredentials(host, protocol, realm, port);
      urlCredentials.forEach(credential => {
        credentials.add(credential.toMap());
      })
    }
    result.success(credentials);
  }

  public dispose(): void {
    super.dispose();
    this.plugin = null;
    this.credentialDatabase = null;
  }
}
