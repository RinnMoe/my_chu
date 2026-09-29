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

export default class WebMessageListenerJS {
  public static WEB_MESSAGE_LISTENER_HELPER_NAME: string = '__flutter_inappwebview_wml';

  public static WEB_MESSAGE_LISTENER_JS_SOURCE: string =
    "if (window." + WebMessageListenerJS.WEB_MESSAGE_LISTENER_HELPER_NAME + " == null) {" +
    "  window." + WebMessageListenerJS.WEB_MESSAGE_LISTENER_HELPER_NAME + " = {};" +
    "}" +
    "function FlutterInAppWebViewWebMessageListener(jsObjectName) {" +
    "  this.jsObjectName = jsObjectName;" +
    "  this.listeners = [];" +
    "  this.onmessage = null;" +
    "}" +
    "FlutterInAppWebViewWebMessageListener.prototype.postMessage = function(data) {" +
    "  var isArrayBuffer = window.ArrayBuffer != null && (" +
    "    data instanceof ArrayBuffer || Object.prototype.toString.call(data) === '[object ArrayBuffer]'" +
    "  );" +
    "  var message = {" +
    "    \"data\": isArrayBuffer ? Array.from(new Uint8Array(data)) : (data != null ? data.toString() : null)," +
    "    \"type\": isArrayBuffer ? 1 : 0" +
    "  };" +
    "  if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + " != null && window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler != null) {" +
    "    window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + ".callHandler('onWebMessageListenerPostMessageReceived', {jsObjectName: this.jsObjectName, message: message});" +
    "  }" +
    "};" +
    "FlutterInAppWebViewWebMessageListener.prototype.addEventListener = function(type, listener) {" +
    "  if (listener == null) { return; }" +
    "  this.listeners.push(listener);" +
    "};" +
    "FlutterInAppWebViewWebMessageListener.prototype.removeEventListener = function(type, listener) {" +
    "  if (listener == null) { return; }" +
    "  var index = this.listeners.indexOf(listener);" +
    "  if (index >= 0) { this.listeners.splice(index, 1); }" +
    "};" +
    "window." + WebMessageListenerJS.WEB_MESSAGE_LISTENER_HELPER_NAME + "._normalizeIPv6 = function(ip_string) {" +
    "  var ipv4 = ip_string.match(/(.*:)([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$)/);" +
    "  if (ipv4) {" +
    "    ip_string = ipv4[1];" +
    "    ipv4 = ipv4[2].match(/[0-9]+/g);" +
    "    for (var i = 0; i < 4; i++) {" +
    "      var byte = parseInt(ipv4[i], 10);" +
    "      ipv4[i] = ('0' + byte.toString(16)).substr(-2);" +
    "    }" +
    "    ip_string += ipv4[0] + ipv4[1] + ':' + ipv4[2] + ipv4[3];" +
    "  }" +
    "  ip_string = ip_string.replace(/^:|:$/g, '');" +
    "  var ipv6 = ip_string.split(':');" +
    "  for (var j = 0; j < ipv6.length; j++) {" +
    "    var hex = ipv6[j];" +
    "    if (hex != '') { ipv6[j] = ('0000' + hex).substr(-4); }" +
    "    else {" +
    "      hex = [];" +
    "      for (var k = ipv6.length; k <= 8; k++) { hex.push('0000'); }" +
    "      ipv6[j] = hex.join(':');" +
    "    }" +
    "  }" +
    "  return ipv6.join(':');" +
    "};" +
    "window." + WebMessageListenerJS.WEB_MESSAGE_LISTENER_HELPER_NAME + "._isOriginAllowed = function(allowedOriginRules, scheme, host, port) {" +
    "  for (var rule of allowedOriginRules) {" +
    "    if (rule === '*') { return true; }" +
    "    if (scheme == null || scheme === '') { continue; }" +
    "    var rulePort = rule.port == null || rule.port === 0 ? (rule.scheme == 'https' ? 443 : 80) : rule.port;" +
    "    var currentPort = port === 0 || port === '' || port == null ? (scheme == 'https' ? 443 : 80) : port;" +
    "    var IPv6 = null;" +
    "    if (rule.host != null && rule.host[0] === '[') {" +
    "      try { IPv6 = window." + WebMessageListenerJS.WEB_MESSAGE_LISTENER_HELPER_NAME + "._normalizeIPv6(rule.host.substring(1, rule.host.length - 1)); } catch (e) {}" +
    "    }" +
    "    var hostIPv6 = null;" +
    "    try { hostIPv6 = window." + WebMessageListenerJS.WEB_MESSAGE_LISTENER_HELPER_NAME + "._normalizeIPv6(host); } catch (e) {}" +
    "    var schemeAllowed = scheme == rule.scheme;" +
    "    var hostAllowed = rule.host == null || rule.host === '' || host === rule.host ||" +
    "      (rule.host[0] === '*' && host != null && host.indexOf(rule.host.split('*')[1]) >= 0) ||" +
    "      (hostIPv6 != null && IPv6 != null && hostIPv6 === IPv6);" +
    "    var portAllowed = rulePort === currentPort;" +
    "    if (schemeAllowed && hostAllowed && portAllowed) { return true; }" +
    "  }" +
    '  return false;' +
    '};';

  public static WEB_MESSAGE_LISTENER_JS_PLUGIN_SCRIPT: PluginScript = new PluginScript(
    'WebMessageListenerJS',
    WebMessageListenerJS.WEB_MESSAGE_LISTENER_JS_SOURCE,
    UserScriptInjectionTime.AT_DOCUMENT_START,
    null,
    true,
    null
  );
}
