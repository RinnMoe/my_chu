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

import cert from '@ohos.security.cert';
import { Any } from '@ohos/flutter_ohos';

export default class SslCertificateExt {
  constructor() {
  }

  public static async toMap(x509Cert: cert.X509Cert | null) {
    if (x509Cert == null) {
      return null
    }

    let issuerName = x509Cert.getIssuerName();
    let issuedByName = extractFields(uint8ArrayToString(issuerName.data))
    let issuedBy: Map<string, Any> | null = null;
    if (issuedByName != null) {
      issuedBy = new Map<string, Any>();
      issuedBy.set("CName", issuedByName.cName);
      issuedBy.set("DName", issuedByName.dName);
      issuedBy.set("OName", issuedByName.oName);
      issuedBy.set("UName", issuedByName.uName);
    }

    let subjectName = x509Cert.getSubjectName();
    let issuedToName = extractFields(uint8ArrayToString(subjectName.data))
    let issuedTo: Map<string, Any> | null = null;
    if (issuedToName != null) {
      issuedTo = new Map<string, Any>();
      issuedTo.set("CName", issuedToName.cName);
      issuedTo.set("DName", issuedToName.dName);
      issuedTo.set("OName", issuedToName.oName);
      issuedTo.set("UName", issuedToName.uName);
    }

    let sslCertificateMap: Map<string, Any> = new Map<string, Any>();

    let x509CertificateData = await x509Cert.getEncoded()
    let validNotAfterDate: string = x509Cert.getNotAfterTime()
    let validNotBeforeDate: string = x509Cert.getNotBeforeTime()

    sslCertificateMap.set("issuedBy", issuedBy);
    sslCertificateMap.set("issuedTo", issuedTo);
    sslCertificateMap.set("validNotAfterDate", asn1TimeToTimestamp(validNotAfterDate));
    sslCertificateMap.set("validNotBeforeDate", asn1TimeToTimestamp(validNotBeforeDate));
    sslCertificateMap.set("x509Certificate", x509CertificateData.data);

    return sslCertificateMap;
  }
}

interface DName {
  cName: string
  dName: string
  oName: string
  uName: string
}

function extractFields(subjectName: string): DName {
  const subject = subjectName.split(', ');
  const fields: Record<string, string> = {};
  subject.forEach(attr => {
    const values = attr.split('=');
    fields[values[0]] = values[1].trim();
  });
  return {
    cName: fields['CN'] || '',
    dName: subjectName || '',
    oName: fields['O'] || '',
    uName: fields['OU'] || ''
  };
}

function uint8ArrayToString(dataArray: Uint8Array): string {
  let dataString = ''
  for (let i = 0; i < dataArray.length; i++) {
    dataString += String.fromCharCode(dataArray[i])
  }
  return dataString
}

/**
 * 将ASN.1时间字符串转换为时间戳
 * @param {string} asn1Time - ASN.1时间字符串
 * @returns {number} 时间戳（毫秒）
 */
function asn1TimeToTimestamp(asn1Time: string): number {
  let year: number = 0;
  let month: number = 0;
  let day: number = 0;
  let hours: number = 0;
  let minutes: number = 0;
  let seconds: number = 0;

  if (asn1Time.length === 13) {
    // UTC Time格式 (YYMMDDHHMMSSZ)
    year = parseInt(asn1Time.slice(0, 2), 10);
    year += year < 50 ? 2000 : 1900;
    month = parseInt(asn1Time.slice(2, 4), 10) - 1;
    day = parseInt(asn1Time.slice(4, 6), 10);
    hours = parseInt(asn1Time.slice(6, 8), 10);
    minutes = parseInt(asn1Time.slice(8, 10), 10);
    seconds = parseInt(asn1Time.slice(10, 12), 10);
  } else if (asn1Time.length === 15) {
    // Generalized Time格式 (YYYYMMDDHHMMSSZ)
    year = parseInt(asn1Time.slice(0, 4), 10);
    month = parseInt(asn1Time.slice(4, 6), 10) - 1;
    day = parseInt(asn1Time.slice(6, 8), 10);
    hours = parseInt(asn1Time.slice(8, 10), 10);
    minutes = parseInt(asn1Time.slice(10, 12), 10);
    seconds = parseInt(asn1Time.slice(12, 14), 10);
  } else {
    throw new Error('Unsupported ASN.1 time format');
  }
  // 创建Date对象并返回时间戳
  const date = new Date(Date.UTC(year, month, day, hours, minutes, seconds));
  return date.getTime();
}
