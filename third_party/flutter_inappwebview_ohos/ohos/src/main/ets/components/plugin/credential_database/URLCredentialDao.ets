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

import URLCredential from '../types/URLCredential'
import CredentialDatabaseHelper from './CredentialDatabaseHelper'
import URLCredentialContract from './URLCredentialContract'
import List from '@ohos.util.List'
import { relationalStore } from '@kit.ArkData'

export default class URLCredentialDao {
  credentialDatabaseHelper: CredentialDatabaseHelper
  projection: string[] = [
    URLCredentialContract._ID,
    URLCredentialContract.COLUMN_NAME_USERNAME,
    URLCredentialContract.COLUMN_NAME_PASSWORD,
    URLCredentialContract.COLUMN_NAME_PROTECTION_SPACE_ID,
  ]

  constructor(credentialDatabaseHelper: CredentialDatabaseHelper) {
    this.credentialDatabaseHelper = credentialDatabaseHelper
  }

  public async getAllByProtectionSpaceId(protectionSpaceId: number) {
    let urlCredentials: List<URLCredential> = new List<URLCredential>();
    let predicates = new relationalStore.RdbPredicates(URLCredentialContract.TABLE_NAME);
    predicates.equalTo(URLCredentialContract.COLUMN_NAME_PROTECTION_SPACE_ID, protectionSpaceId.toString());
    let rdbStore = await this.credentialDatabaseHelper.getRdbStore();
    let resultSet = await rdbStore.query(predicates);
    try {
      while (resultSet.goToNextRow()) {
        const id = resultSet.getLong(resultSet.getColumnIndex(URLCredentialContract._ID));
        const username = resultSet.getString(resultSet.getColumnIndex(URLCredentialContract.COLUMN_NAME_USERNAME));
        const password = resultSet.getString(resultSet.getColumnIndex(URLCredentialContract.COLUMN_NAME_PASSWORD));
        urlCredentials.add(new URLCredential(id, username, password, protectionSpaceId));
      }
    } finally {
      resultSet.close();
    }
    return urlCredentials
  }

  public async find(username: string, password: string, protectionSpaceId: number){
    let predicates = new relationalStore.RdbPredicates(URLCredentialContract.TABLE_NAME);
    predicates.equalTo(URLCredentialContract.COLUMN_NAME_USERNAME, username);
    predicates.and();
    predicates.equalTo(URLCredentialContract.COLUMN_NAME_PASSWORD, password);
    predicates.and();
    predicates.equalTo(URLCredentialContract.COLUMN_NAME_PROTECTION_SPACE_ID, protectionSpaceId.toString());
    let dbStore = await this.credentialDatabaseHelper.getRdbStore();
    let resultSet = await dbStore.query(predicates);

    let urlCredential: URLCredential | null = null;
    try {
      if (resultSet.goToNextRow()) {
        const rowId = resultSet.getLong(resultSet.getColumnIndex(URLCredentialContract._ID));
        const rowUsername = resultSet.getString(resultSet.getColumnIndex(URLCredentialContract.COLUMN_NAME_USERNAME));
        const rowPassword = resultSet.getString(resultSet.getColumnIndex(URLCredentialContract.COLUMN_NAME_PASSWORD));
        urlCredential = new URLCredential(rowId, rowUsername, rowPassword, protectionSpaceId);
      }
    } finally {
      resultSet.close();
    }

    return urlCredential;
  }

  public async insert(urlCredential: URLCredential) {
    const valueBucket: relationalStore.ValuesBucket = {};
    valueBucket[URLCredentialContract.COLUMN_NAME_USERNAME] = urlCredential.getUsername();
    valueBucket[URLCredentialContract.COLUMN_NAME_PASSWORD] = urlCredential.getPassword();
    valueBucket[URLCredentialContract.COLUMN_NAME_PROTECTION_SPACE_ID] = urlCredential.getProtectionSpaceId();
    let rdbStore = await this.credentialDatabaseHelper.getRdbStore();
    return await rdbStore.insert(URLCredentialContract.TABLE_NAME, valueBucket);
  }

  public async update(urlCredential: URLCredential) {
    const valueBucket: relationalStore.ValuesBucket = {};
    valueBucket[URLCredentialContract.COLUMN_NAME_USERNAME] = urlCredential.getUsername();
    valueBucket[URLCredentialContract.COLUMN_NAME_PASSWORD] = urlCredential.getPassword();

    let predicates = new relationalStore.RdbPredicates(URLCredentialContract.TABLE_NAME);
    predicates.equalTo(URLCredentialContract.COLUMN_NAME_PROTECTION_SPACE_ID, urlCredential.getProtectionSpaceId()?.toString());

    let rdbStore = await this.credentialDatabaseHelper.getRdbStore();
    return await rdbStore.update(valueBucket, predicates);
  }

  public async delete( urlCredential: URLCredential) {
    let predicates = new relationalStore.RdbPredicates(URLCredentialContract.TABLE_NAME);
    predicates.equalTo(URLCredentialContract._ID, urlCredential.getId()?.toString());
    let rdbStore = await this.credentialDatabaseHelper.getRdbStore();
    return await rdbStore.delete(predicates);
  }
}
