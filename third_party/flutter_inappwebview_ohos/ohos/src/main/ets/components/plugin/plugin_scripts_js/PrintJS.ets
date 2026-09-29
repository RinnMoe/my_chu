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

import PluginScript from '../types/PluginScript';
import { UserScriptInjectionTime } from '../types/UserScriptInjectionTime';
import JavaScriptBridgeJS from './JavaScriptBridgeJS';

export default class PrintJS {
  public static PRINT_JS_PLUGIN_SCRIPT_GROUP_NAME = "IN_APP_WEBVIEW_PRINT_JS_PLUGIN_SCRIPT";
  public static PRINT_JS_SOURCE = "window.print = function() {" +
    "  if (window.top == null || window.top === window) {" +
    "     window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler('onPrintRequest', window.location.href);" +
    "  } else {" +
    "     window.top.print();" +
    "  }" +
    "};";
  public static PRINT_JS_PLUGIN_SCRIPT = new PluginScript(
    PrintJS.PRINT_JS_PLUGIN_SCRIPT_GROUP_NAME,
    PrintJS.PRINT_JS_SOURCE,
    UserScriptInjectionTime.AT_DOCUMENT_START,
    null,
    false,
    null
  );
}