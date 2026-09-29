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

import { Any } from '@ohos/flutter_ohos'
import SslCertificateExt from './SslCertificateExt'
import SslErrorExt from './SslErrorExt'
import { cert } from '@kit.DeviceCertificateKit'

export default class URLProtectionSpace {
  private id: number | null = null
  private host: string
  private protocol: string
  private realm: string | null
  private port: number
  private sslCertificate: cert.X509Cert | null = null
  private sslError: SslError | null = null

  constructor(host: string, protocol: string, realm: string | null, port: number, id?: number | null,
    sslCertificate?: cert.X509Cert | null, sslError?: SslError | null) {
    this.host = host
    this.protocol = protocol
    this.realm = realm
    this.port = port
    if (id) {
      this.id = id;
    }
    if (sslCertificate) {
      this.sslCertificate = sslCertificate;
    }
    if (sslError) {
      this.sslError = sslError
    }
  }

  public async toMap() {
    let urlProtectionSpaceMap: Map<string, Any> = new Map<string, Any>();
    urlProtectionSpaceMap.set('host', this.host);
    urlProtectionSpaceMap.set('protocol', this.protocol);
    urlProtectionSpaceMap.set('realm', this.realm);
    urlProtectionSpaceMap.set('port', this.port);
    urlProtectionSpaceMap.set('sslCertificate',  await SslCertificateExt.toMap(this.sslCertificate));
    urlProtectionSpaceMap.set('sslCertificate', null);
    urlProtectionSpaceMap.set('sslError', SslErrorExt.toMap(this.sslError));
    urlProtectionSpaceMap.set('sslError', null);
    urlProtectionSpaceMap.set('authenticationMethod', null);
    urlProtectionSpaceMap.set('distinguishedNames', null);
    urlProtectionSpaceMap.set('receivesCredentialSecurely', null);
    urlProtectionSpaceMap.set('isProxy', null);
    urlProtectionSpaceMap.set('proxyType', null);
    return urlProtectionSpaceMap;
  }

  /** Synchronous map for callbacks that must block the WebView network thread. */
  public toSyncMap(): Map<string, Any> {
    let urlProtectionSpaceMap: Map<string, Any> = new Map<string, Any>();
    urlProtectionSpaceMap.set('host', this.host);
    urlProtectionSpaceMap.set('protocol', this.protocol);
    urlProtectionSpaceMap.set('realm', this.realm);
    urlProtectionSpaceMap.set('port', this.port);
    urlProtectionSpaceMap.set('sslCertificate', null);
    urlProtectionSpaceMap.set('sslError', SslErrorExt.toMap(this.sslError));
    urlProtectionSpaceMap.set('authenticationMethod', null);
    urlProtectionSpaceMap.set('distinguishedNames', null);
    urlProtectionSpaceMap.set('receivesCredentialSecurely', null);
    urlProtectionSpaceMap.set('isProxy', null);
    urlProtectionSpaceMap.set('proxyType', null);
    return urlProtectionSpaceMap;
  }

  public getId(): number | null {
    return this.id;
  }

  public setId(id: number | null): void {
    this.id = id;
  }

  public getHost(): string {
    return this.host;
  }

  public setHost(host: string): void {
    this.host = host;
  }

  public getProtocol(): string {
    return this.protocol;
  }

  public setProtocol(protocol: string): void {
    this.protocol = protocol;
  }

  public getRealm(): string | null {
    return this.realm;
  }

  public setRealm(realm: string): void {
    this.realm = realm;
  }

  public getPort(): number {
    return this.port;
  }

  public setPort(port: number): void {
    this.port = port;
  }

  public getSslCertificate(): cert.X509Cert | null {
    return this.sslCertificate;
  }

  public setSslCertificate(sslCertificateExt: cert.X509Cert | null): void {
    this.sslCertificate = sslCertificateExt;
  }

  public getSslError(): SslError | null {
    return this.sslError;
  }

  public setSslError(sslError: SslError | null): void {
    this.sslError = sslError;
  }

  public toString(): string {
    return "URLProtectionSpace{" +
      "host='" + this.host + '\'' +
      ", protocol='" + this.protocol + '\'' +
      ", realm='" + this.realm + '\'' +
      ", port=" + this.port +
      ", sslCertificate=" + this.sslCertificate +
      ", sslError=" + this.sslError +
      '}';
  }
}