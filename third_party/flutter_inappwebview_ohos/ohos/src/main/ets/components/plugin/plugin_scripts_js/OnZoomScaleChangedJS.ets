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

export default class OnZoomScaleChangedJS {
  public static ON_ZOOM_SCALE_CHANGED_JS_PLUGIN_SCRIPT_GROUP_NAME =
    "IN_APP_WEBVIEW_ON_ZOOM_SCALE_CHANGED_JS_PLUGIN_SCRIPT";
  public static HANDLER_NAME = "onZoomScaleChangedFallback";
  public static STATE_VARIABLE_NAME =
    "window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "._visualViewportScaleState";

  public static ON_ZOOM_SCALE_CHANGED_JS_SOURCE =
    "(function() {" +
    "  if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + " == null) { return; }" +
    "  var bridge = window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ";" +
    "  var state = " + OnZoomScaleChangedJS.STATE_VARIABLE_NAME + ";" +
    "  if (state != null && state.initialized) { return; }" +
    "  state = { initialized: true, lastScale: null, timer: null };" +
    "  " + OnZoomScaleChangedJS.STATE_VARIABLE_NAME + " = state;" +
    "  var getScale = function() {" +
    "    if (window.visualViewport == null || typeof window.visualViewport.scale !== 'number') {" +
    "      return null;" +
    "    }" +
    "    return window.visualViewport.scale;" +
    "  };" +
    "  var dispatchScaleChange = function() {" +
    "    var newScale = getScale();" +
    "    if (newScale == null) { return; }" +
    "    if (state.lastScale == null) {" +
    "      state.lastScale = newScale;" +
    "      return;" +
    "    }" +
    "    if (Math.abs(newScale - state.lastScale) < 0.01) { return; }" +
    "    var oldScale = state.lastScale;" +
    "    state.lastScale = newScale;" +
    "    bridge.callHandler('" + OnZoomScaleChangedJS.HANDLER_NAME + "', {" +
    "      oldScale: oldScale," +
    "      newScale: newScale" +
    "    }).catch(function() {});" +
    "  };" +
    "  var scheduleDispatch = function() {" +
    "    if (state.timer != null) {" +
    "      clearTimeout(state.timer);" +
    "    }" +
    "    state.timer = setTimeout(function() {" +
    "      state.timer = null;" +
    "      dispatchScaleChange();" +
    "    }, 50);" +
    "  };" +
    "  state.lastScale = getScale();" +
    "  if (window.visualViewport != null) {" +
    "    window.visualViewport.addEventListener('resize', scheduleDispatch);" +
    "    window.visualViewport.addEventListener('scroll', scheduleDispatch);" +
    "  }" +
    "  window.addEventListener('resize', scheduleDispatch);" +
    "  window.addEventListener('orientationchange', scheduleDispatch);" +
    "})();";

  public static ON_ZOOM_SCALE_CHANGED_JS_PLUGIN_SCRIPT = new PluginScript(
    OnZoomScaleChangedJS.ON_ZOOM_SCALE_CHANGED_JS_PLUGIN_SCRIPT_GROUP_NAME,
    OnZoomScaleChangedJS.ON_ZOOM_SCALE_CHANGED_JS_SOURCE,
    UserScriptInjectionTime.AT_DOCUMENT_START,
    null,
    false,
    null
  );
}
