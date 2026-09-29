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

/**
 * Hook window.open(about:blank) when ArkWeb skips onWindowNew.
 * console.log is primary (works in isolation / after multi-window tests).
 * Deferred _callHandler covers cases where ConsoleMessage.getMessage() is empty
 * after a prior non-multi-window WebView (must not call proxy synchronously).
 */
export default class WindowOpenAboutBlankJS {
  public static HANDLER_NAME: string = '__windowOpenAboutBlank';
  public static CONSOLE_PREFIX: string = '__FLUTTER_IAW_WINDOW_OPEN__:';
  public static NAV_MARKER: string = '__iaw_window_open_about_blank__';
  public static GROUP_NAME: string = 'IN_APP_WEBVIEW_WINDOW_OPEN_ABOUT_BLANK_JS_PLUGIN_SCRIPT';
  public static SOURCE: string = '(function(){' +
    '  if (window.__flutterIAWWindowOpenHooked) { return; }' +
    '  window.__flutterIAWWindowOpenHooked = true;' +
    "  var bridgeName = '" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "';" +
    '  var _open = window.open;' +
    '  window.open = function(url, name, specs) {' +
    '    var u = (url == null || url === \'\') ? \'about:blank\' : String(url);' +
    '    if (u === \'about:blank\') {' +
    "      try { console.log('" + WindowOpenAboutBlankJS.CONSOLE_PREFIX + "' + u); } catch (_e0) {}" +
    '      try {' +
    '        setTimeout(function() {' +
    '          try {' +
    '            var b = window[bridgeName];' +
    '            if (b != null && b._callHandler != null) {' +
    "              b._callHandler('" + WindowOpenAboutBlankJS.HANDLER_NAME + "', '0', '[]');" +
    '            }' +
    '          } catch (_e2) {}' +
    '        }, 0);' +
    '      } catch (_e1) {}' +
    '      return { closed: false, close: function(){}, focus: function(){}, blur: function(){} };' +
    '    }' +
    '    return _open.apply(this, arguments);' +
    '  };' +
    '})();';
  public static PLUGIN_SCRIPT: PluginScript = new PluginScript(
    WindowOpenAboutBlankJS.GROUP_NAME,
    WindowOpenAboutBlankJS.SOURCE,
    UserScriptInjectionTime.AT_DOCUMENT_START,
    null,
    false,
    null
  );
}
