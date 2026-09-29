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

export default class URLCredentialContract {
  constructor() {}

  public static _ID: string = "_id"

  public static _COUNT: string = "_count";

  public static TABLE_NAME: string = "credential";

  public static COLUMN_NAME_USERNAME: string = "username";

  public static COLUMN_NAME_PASSWORD: string = "password";

  public static COLUMN_NAME_PROTECTION_SPACE_ID: string = "protection_space_id";
}