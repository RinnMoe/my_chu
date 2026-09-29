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



import { DVModelParameters } from '@ohos/flutter_ohos/src/main/ets/view/DynamicView/dynamicView'



export class DynamicUtils {

  static getParams(params: DVModelParameters, element: string): string | Object {

    let params2 = params as Record<string, Object>;

    return params2[element];

  }



  static setParams(params: DVModelParameters, key: string, element: Object): void {

    let params2 = params as Record<string, Object>;

    params2[key] = element;

  }

}



export class DVModelJson {

  compType: string

  children: Array<Object>

  attributes: Record<string, Object>

  events: Record<string, Object>

  build: (() => void) | undefined



  constructor(compType: string, children: Array<Object>, attributes: Record<string, Object>,
  events: Record<string, Object>, build?: () => void) {

    this.compType = compType

    this.children = children

    this.attributes = attributes

    this.events = events;

    this.build = build;

  }

}
