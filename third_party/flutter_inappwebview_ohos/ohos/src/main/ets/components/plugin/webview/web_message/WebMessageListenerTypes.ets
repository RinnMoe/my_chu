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

import WebMessageCompatExt from '../../types/WebMessageCompatExt';

/** Payload sent from JS via FlutterInAppWebViewWebMessageListener.postMessage. */
export interface WebMessageListenerJsMessage {
  data: string | number[] | null;
  type: number;
}

/** Arguments array element for onWebMessageListenerPostMessageReceived callHandler. */
export interface WebMessageListenerPostMessagePayload {
  jsObjectName: string;
  message: WebMessageListenerJsMessage;
}

export function webMessageCompatFromJsMessage(message: WebMessageListenerJsMessage): WebMessageCompatExt {
  let type: number = Number(message.type);
  if (isNaN(type)) {
    type = 0;
  }
  return new WebMessageCompatExt(message.data, type, null);
}
