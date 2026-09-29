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

export default class PluginScriptsUtil {
  public static VAR_PLACEHOLDER_VALUE: string = "$IN_APP_WEBVIEW_PLACEHOLDER_VALUE";
  public static VAR_CONTENT_WORLD_NAME_ARRAY: string = "$IN_APP_WEBVIEW_CONTENT_WORLD_NAME_ARRAY";
  public static VAR_CONTENT_WORLD_NAME: string = "$IN_APP_WEBVIEW_CONTENT_WORLD_NAME";
  public static VAR_JSON_SOURCE_ENCODED: string = "$IN_APP_WEBVIEW_JSON_SOURCE_ENCODED";
  public static VAR_FUNCTION_ARGUMENT_NAMES: string = "$IN_APP_WEBVIEW_FUNCTION_ARGUMENT_NAMES";
  public static VAR_FUNCTION_ARGUMENT_VALUES: string = "$IN_APP_WEBVIEW_FUNCTION_ARGUMENT_VALUES";
  public static VAR_FUNCTION_ARGUMENTS_OBJ: string = "$IN_APP_WEBVIEW_FUNCTION_ARGUMENTS_OBJ";
  public static VAR_FUNCTION_BODY: string = "$IN_APP_WEBVIEW_FUNCTION_BODY";
  public static VAR_RESULT_UUID: string = "$IN_APP_WEBVIEW_RESULT_UUID";
  public static VAR_RANDOM_NAME: string = "$IN_APP_WEBVIEW_VARIABLE_RANDOM_NAME";

  public static CALL_ASYNC_JAVA_SCRIPT_WRAPPER_JS_SOURCE: string = "(function(obj) {" +
    "  (async function(" + this.VAR_FUNCTION_ARGUMENT_NAMES + ") {" +
    "    \n" + this.VAR_FUNCTION_BODY + "\n" +
    "  })(" + this.VAR_FUNCTION_ARGUMENT_VALUES + ").then(function(value) {" +
    "    window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler('callAsyncJavaScript', {'value': value, 'error': null, 'resultUuid': '" + this.VAR_RESULT_UUID + "'});" +
    "  }).catch(function(error) {" +
    "    window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler('callAsyncJavaScript', {'value': null, 'error': error + '', 'resultUuid': '" + this.VAR_RESULT_UUID + "'});" +
    "  });" +
    "  return null;" +
    "})(" + this.VAR_FUNCTION_ARGUMENTS_OBJ + ");";

  public static EVALUATE_JAVASCRIPT_WITH_CONTENT_WORLD_WRAPPER_JS_SOURCE: string = "var $IN_APP_WEBVIEW_VARIABLE_RANDOM_NAME = null;" +
    "try {" +
    "  $IN_APP_WEBVIEW_VARIABLE_RANDOM_NAME = eval(" + this.VAR_PLACEHOLDER_VALUE + ");" +
    "} catch(e) {" +
    "  console.error(e);" +
    "}" +
    "window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler('evaluateJavaScriptWithContentWorld', {'value': $IN_APP_WEBVIEW_VARIABLE_RANDOM_NAME, 'resultUuid': '" + this.VAR_RESULT_UUID + "'});";

  public static IS_ACTIVE_ELEMENT_INPUT_EDITABLE_JS_SOURCE: string =
    "var activeEl = document.activeElement;" +
      "var nodeName = (activeEl != null) ? activeEl.nodeName.toLowerCase() : '';" +
      "var isActiveElementInputEditable = activeEl != null && " +
      "(activeEl.nodeType == 1 && (nodeName == 'textarea' || (nodeName == 'input' && /^(?:text|email|number|search|tel|url|password)$/i.test(activeEl.type != null ? activeEl.type : 'text')))) && " +
      "!activeEl.disabled && !activeEl.readOnly;" +
      "var isActiveElementEditable = isActiveElementInputEditable || (activeEl != null && activeEl.isContentEditable) || document.designMode === 'on';";

  // android Workaround to hide context menu when selected text is empty
  // and the document active element is not an input element.
  public static CHECK_CONTEXT_MENU_SHOULD_BE_HIDDEN_JS_SOURCE: string = "(function(){" +
    "  var txt;" +
    "  if (window.getSelection) {" +
    "    txt = window.getSelection().toString();" +
    "  } else if (window.document.getSelection) {" +
    "    txt = window.document.getSelection().toString();" +
    "  } else if (window.document.selection) {" +
    "    txt = window.document.selection.createRange().text;" +
    "  }" +
  this.IS_ACTIVE_ELEMENT_INPUT_EDITABLE_JS_SOURCE +
    "  return txt === '' && !isActiveElementEditable;" +
    "})();";

  public static GET_SELECTED_TEXT_JS_SOURCE: string = "(function(){" +
    "  var txt;" +
    "  if (window.getSelection) {" +
    "    txt = window.getSelection().toString();" +
    "  } else if (window.document.getSelection) {" +
    "    txt = window.document.getSelection().toString();" +
    "  } else if (window.document.selection) {" +
    "    txt = window.document.selection.createRange().text;" +
    "  }" +
    "  return txt;" +
    "})();";

  public static CHECK_GLOBAL_KEY_DOWN_EVENT_TO_HIDE_CONTEXT_MENU_JS_PLUGIN_SCRIPT_GROUP_NAME: string = "CHECK_GLOBAL_KEY_DOWN_EVENT_TO_HIDE_CONTEXT_MENU_JS_PLUGIN_SCRIPT";

  public static CHECK_GLOBAL_KEY_DOWN_EVENT_TO_HIDE_CONTEXT_MENU_JS_SOURCE: string = "(function(){" +
    "  document.addEventListener('keydown', function(e) {" +
    "    window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "._hideContextMenu();" +
    "  });" +
    "})();";

  public static CHECK_GLOBAL_KEY_DOWN_EVENT_TO_HIDE_CONTEXT_MENU_JS_PLUGIN_SCRIPT: PluginScript = new PluginScript(
    PluginScriptsUtil.CHECK_GLOBAL_KEY_DOWN_EVENT_TO_HIDE_CONTEXT_MENU_JS_PLUGIN_SCRIPT_GROUP_NAME,
    PluginScriptsUtil.CHECK_GLOBAL_KEY_DOWN_EVENT_TO_HIDE_CONTEXT_MENU_JS_SOURCE,
    UserScriptInjectionTime.AT_DOCUMENT_START,
    null,
    false,
    null
  );

}