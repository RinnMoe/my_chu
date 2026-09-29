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

export default class OnJsBeforeUnloadJS {
  public static HANDLER_NAME: string = 'onBeforeUnloadHandlerRegistered';
  public static ON_JS_BEFORE_UNLOAD_JS_PLUGIN_SCRIPT_GROUP_NAME =
    'IN_APP_WEBVIEW_ON_JS_BEFORE_UNLOAD_JS_PLUGIN_SCRIPT';
  public static ON_JS_BEFORE_UNLOAD_JS_SOURCE = '(function() {' +
    "  var bridgeName = '" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "';" +
    '  function notifyRegistered() {' +
    '    try {' +
    '      var bridge = window[bridgeName];' +
    '      if (bridge != null && bridge.callHandler != null) {' +
    "        bridge.callHandler('" + OnJsBeforeUnloadJS.HANDLER_NAME + "');" +
    '      }' +
    '    } catch (e) {}' +
    '  }' +
    '  var originalAddEventListener = EventTarget.prototype.addEventListener;' +
    '  EventTarget.prototype.addEventListener = function(type, listener, options) {' +
    "    if (type === 'beforeunload') {" +
    '      notifyRegistered();' +
    '    }' +
    '    return originalAddEventListener.call(this, type, listener, options);' +
    '  };' +
    '  try {' +
    '    var existingHandler = window.onbeforeunload;' +
    "    Object.defineProperty(window, 'onbeforeunload', {" +
    '      configurable: true,' +
    '      enumerable: true,' +
    '      get: function() { return window.__fiv_onbeforeunload; },' +
    '      set: function(handler) {' +
    '        window.__fiv_onbeforeunload = handler;' +
    '        if (handler != null) { notifyRegistered(); }' +
    '      }' +
    '    });' +
    '    if (existingHandler != null) { window.onbeforeunload = existingHandler; }' +
    '  } catch (e) {}' +
    '})();';
  public static ON_JS_BEFORE_UNLOAD_JS_PLUGIN_SCRIPT = new PluginScript(
    OnJsBeforeUnloadJS.ON_JS_BEFORE_UNLOAD_JS_PLUGIN_SCRIPT_GROUP_NAME,
    OnJsBeforeUnloadJS.ON_JS_BEFORE_UNLOAD_JS_SOURCE,
    UserScriptInjectionTime.AT_DOCUMENT_START,
    null,
    false,
    null
  );
}
