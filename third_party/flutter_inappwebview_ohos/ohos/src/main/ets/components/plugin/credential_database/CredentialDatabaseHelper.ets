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

import URLCredentialContract from './URLCredentialContract';
import URLProtectionSpaceContract from './URLProtectionSpaceContract';
import CredentialDatabase from  './CredentialDatabase';
import { Context } from '@kit.AbilityKit';
import data_rdb from '@ohos.data.relationalStore'
import { Log } from '@ohos/flutter_ohos';

const TAG = 'CredentialDatabaseHelper'

export default class CredentialDatabaseHelper {
  private static SQL_CREATE_PROTECTION_SPACE_TABLE: string =
    "CREATE TABLE IF NOT EXISTS " + URLProtectionSpaceContract.TABLE_NAME + " (" +
    URLProtectionSpaceContract._ID + " INTEGER PRIMARY KEY," +
    URLProtectionSpaceContract.COLUMN_NAME_HOST + " TEXT NOT NULL," +
    URLProtectionSpaceContract.COLUMN_NAME_PROTOCOL + " TEXT," +
    URLProtectionSpaceContract.COLUMN_NAME_REALM + " TEXT," +
    URLProtectionSpaceContract.COLUMN_NAME_PORT + " INTEGER," +
      "UNIQUE(" + URLProtectionSpaceContract.COLUMN_NAME_HOST + ", " + URLProtectionSpaceContract.COLUMN_NAME_PROTOCOL + ", " +
    URLProtectionSpaceContract.COLUMN_NAME_REALM + ", " + URLProtectionSpaceContract.COLUMN_NAME_PORT +
      ")" +
      ");";

  private static SQL_CREATE_CREDENTIAL_TABLE: string =
    "CREATE TABLE IF NOT EXISTS " + URLCredentialContract.TABLE_NAME + " (" +
    URLCredentialContract._ID + " INTEGER PRIMARY KEY," +
    URLCredentialContract.COLUMN_NAME_USERNAME + " TEXT NOT NULL," +
    URLCredentialContract.COLUMN_NAME_PASSWORD + " TEXT NOT NULL," +
    URLCredentialContract.COLUMN_NAME_PROTECTION_SPACE_ID + " INTEGER NOT NULL," +
      "UNIQUE(" + URLCredentialContract.COLUMN_NAME_USERNAME + ", " + URLCredentialContract.COLUMN_NAME_PASSWORD + ", " +
    URLCredentialContract.COLUMN_NAME_PROTECTION_SPACE_ID +
      ")," +
      "FOREIGN KEY (" + URLCredentialContract.COLUMN_NAME_PROTECTION_SPACE_ID + ") REFERENCES " +
    URLProtectionSpaceContract.TABLE_NAME + " (" + URLProtectionSpaceContract._ID + ") ON DELETE CASCADE" +
      ");";

  private static SQL_DELETE_PROTECTION_SPACE_TABLE: string =
    'DROP TABLE IF EXISTS ' + URLProtectionSpaceContract.TABLE_NAME;

  private static SQL_DELETE_CREDENTIAL_TABLE: string =
    'DROP TABLE IF EXISTS ' + URLCredentialContract.TABLE_NAME;

  private rdbStore: data_rdb.RdbStore | null = null;
  private context : Context;

  constructor(context: Context) {
    this.context = context;
  }

  private async initRdb() {
    if (this.rdbStore != null) {
      return
    }
    try {
      this.rdbStore = await data_rdb.getRdbStore(this.context, {
        name: CredentialDatabase.DATABASE_NAME, securityLevel: data_rdb.SecurityLevel.S1
      })
      await this.rdbStore.executeSql(CredentialDatabaseHelper.SQL_CREATE_PROTECTION_SPACE_TABLE);
      await this.rdbStore.executeSql(CredentialDatabaseHelper.SQL_CREATE_CREDENTIAL_TABLE);
    } catch (e) {
      let err: Error = e as Error;
      this.rdbStore = null;
      Log.e(TAG, 'initRdb failed: ' + JSON.stringify(err));
      throw new Error(err.message);
    }
  }

  async clearAllTables() {
    try {
      await this.initRdb();
      await this.rdbStore?.executeSql('DELETE FROM ' + URLCredentialContract.TABLE_NAME);
      await this.rdbStore?.executeSql('DELETE FROM ' + URLProtectionSpaceContract.TABLE_NAME);
    } catch (e) {
      let err: Error = e as Error;
      Log.e(TAG, 'clearAllTables failed: ' + JSON.stringify(err));
      throw new Error(err.message);
    }
  }

  async getRdbStore() {
    await this.initRdb();
    if (this.rdbStore == null) {
      throw new Error('CredentialDatabase RdbStore is not initialized');
    }
    return this.rdbStore;
  }

  async close(): Promise<void> {
    if (this.rdbStore != null) {
      try {
        await this.rdbStore.close();
      } catch (e) {
        Log.e(TAG, 'close rdbStore failed: ' + JSON.stringify(e));
      }
      this.rdbStore = null;
    }
  }
}