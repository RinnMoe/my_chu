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

import URLProtectionSpace from '../types/URLProtectionSpace';
import CredentialDatabaseHelper from './CredentialDatabaseHelper';
import URLProtectionSpaceContract from './URLProtectionSpaceContract';
import { relationalStore } from '@kit.ArkData';

export default class URLProtectionSpaceDao {
  credentialDatabaseHelper: CredentialDatabaseHelper
  projection: Array<string> = [
    URLProtectionSpaceContract._ID,
    URLProtectionSpaceContract.COLUMN_NAME_HOST,
    URLProtectionSpaceContract.COLUMN_NAME_PROTOCOL,
    URLProtectionSpaceContract.COLUMN_NAME_REALM,
    URLProtectionSpaceContract.COLUMN_NAME_PORT
  ];

  constructor(credentialDatabaseHelper: CredentialDatabaseHelper) {
    this.credentialDatabaseHelper = credentialDatabaseHelper
  }

  public async getAll() {
    let urlProtectionSpaces: Array<URLProtectionSpace> = new Array<URLProtectionSpace>();

    let predicates = new relationalStore.RdbPredicates(URLProtectionSpaceContract.TABLE_NAME);
    let rdbStore = await this.credentialDatabaseHelper.getRdbStore();
    let resultSet = await rdbStore.query(predicates, this.projection);

    try {
      while (resultSet.goToNextRow()) {
        const rowId = resultSet.getLong(resultSet.getColumnIndex(URLProtectionSpaceContract._ID));
        const rowHost = resultSet.getString(resultSet.getColumnIndex(URLProtectionSpaceContract.COLUMN_NAME_HOST));
        const rowProtocol = resultSet.getString(resultSet.getColumnIndex(URLProtectionSpaceContract.COLUMN_NAME_PROTOCOL));
        const rowRealm = resultSet.getString(resultSet.getColumnIndex(URLProtectionSpaceContract.COLUMN_NAME_REALM));
        const rowPort = resultSet.getLong(resultSet.getColumnIndex(URLProtectionSpaceContract.COLUMN_NAME_PORT));
        urlProtectionSpaces.push(new URLProtectionSpace(rowHost, rowProtocol, rowRealm, rowPort, rowId));
      }
    } finally {
      resultSet.close();
    }
    return urlProtectionSpaces;
  }

  public async find(host: string, protocol: string, realm: string | null, port: number) {
    let predicates = new relationalStore.RdbPredicates(URLProtectionSpaceContract.TABLE_NAME);
    predicates.equalTo(URLProtectionSpaceContract.COLUMN_NAME_HOST, host);
    predicates.and();
    predicates.equalTo(URLProtectionSpaceContract.COLUMN_NAME_PROTOCOL, protocol);
    predicates.and();
    if (realm == null) {
      predicates.isNull(URLProtectionSpaceContract.COLUMN_NAME_REALM);
    } else {
      predicates.equalTo(URLProtectionSpaceContract.COLUMN_NAME_REALM, realm);
    }
    predicates.and();
    predicates.equalTo(URLProtectionSpaceContract.COLUMN_NAME_PORT, port.toString());

    let dbStore = await this.credentialDatabaseHelper.getRdbStore();
    let resultSet = await dbStore.query(predicates);

    let urlProtectionSpace: URLProtectionSpace | null = null;
    try {
      if (resultSet.goToNextRow()) {
        const rowId = resultSet.getLong(resultSet.getColumnIndex(URLProtectionSpaceContract._ID));
        const rowHost = resultSet.getString(resultSet.getColumnIndex(URLProtectionSpaceContract.COLUMN_NAME_HOST));
        const rowProtocol = resultSet.getString(resultSet.getColumnIndex(URLProtectionSpaceContract.COLUMN_NAME_PROTOCOL));
        const rowRealm = resultSet.getString(resultSet.getColumnIndex(URLProtectionSpaceContract.COLUMN_NAME_REALM));
        const rowPort = resultSet.getLong(resultSet.getColumnIndex(URLProtectionSpaceContract.COLUMN_NAME_PORT));
        urlProtectionSpace = new URLProtectionSpace(rowHost, rowProtocol, rowRealm, rowPort, rowId);
      }
    } finally {
      resultSet.close();
    }
    return urlProtectionSpace;
  }

  public async insert(protectionSpace: URLProtectionSpace) {
    const valueBucket: relationalStore.ValuesBucket = {};
    valueBucket[URLProtectionSpaceContract.COLUMN_NAME_HOST] = protectionSpace.getHost();
    valueBucket[URLProtectionSpaceContract.COLUMN_NAME_PROTOCOL] = protectionSpace.getProtocol();
    valueBucket[URLProtectionSpaceContract.COLUMN_NAME_REALM] = protectionSpace.getRealm();
    valueBucket[URLProtectionSpaceContract.COLUMN_NAME_PORT] = protectionSpace.getPort();
    let rdbStore = await this.credentialDatabaseHelper.getRdbStore();
    return await rdbStore.insert(URLProtectionSpaceContract.TABLE_NAME, valueBucket);
  }

  public async delete(protectionSpace: URLProtectionSpace) {
    let predicates = new relationalStore.RdbPredicates(URLProtectionSpaceContract.TABLE_NAME);
    predicates.equalTo(URLProtectionSpaceContract._ID, protectionSpace.getId()?.toString());
    let rdbStore = await this.credentialDatabaseHelper.getRdbStore();
    return await rdbStore.delete(predicates);
  }
}
