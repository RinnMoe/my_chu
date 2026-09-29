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

export default class JavaScriptBridgeJS {
  public static JAVASCRIPT_BRIDGE_NAME: string = "flutter_inappwebview";

  public static JAVASCRIPT_BRIDGE_JS_PLUGIN_SCRIPT_GROUP_NAME: string = "IN_APP_WEBVIEW_JAVASCRIPT_BRIDGE_JS_PLUGIN_SCRIPT";


  public static JAVASCRIPT_UTIL_VAR_NAME: string = "window." + this.JAVASCRIPT_BRIDGE_NAME + "._Util";

  public static WEB_MESSAGE_CHANNELS_VARIABLE_NAME: string = "window." + this.JAVASCRIPT_BRIDGE_NAME + "._webMessageChannels";

  public static UTIL_JS_SOURCE: string = this.JAVASCRIPT_UTIL_VAR_NAME + " = {" +
    "    support: {" +
    "        searchParams: 'URLSearchParams' in window," +
    "        iterable: 'Symbol' in window && 'iterator' in Symbol," +
    "        blob:" +
    "            'FileReader' in window &&" +
    "            'Blob' in window &&" +
    "            (function() {" +
    "              try {" +
    "                new Blob();" +
    "                return true;" +
    "              } catch (e) {" +
    "                return false;" +
    "              }" +
    "            })()," +
    "        formData: 'FormData' in window," +
    "        arrayBuffer: 'ArrayBuffer' in window" +
    "    }," +
    "    isDataView: function(obj) {" +
    "        return obj && DataView.prototype.isPrototypeOf(obj);" +
    "    }," +
    "    fileReaderReady: function(reader) {" +
    "          return new Promise(function(resolve, reject) {" +
    "                reader.onload = function() {" +
    "                    resolve(reader.result);" +
    "                };" +
    "                reader.onerror = function() {" +
    "                    reject(reader.error);" +
    "                };" +
    "          });" +
    "    }," +
    "    readBlobAsArrayBuffer: function(blob) {" +
    "        var reader = new FileReader();" +
    "        var promise = " + this.JAVASCRIPT_UTIL_VAR_NAME + ".fileReaderReady(reader);" +
    "        reader.readAsArrayBuffer(blob);" +
    "        return promise;" +
    "    }," +
    "    convertBodyToArrayBuffer: function(body) {" +
    "        var viewClasses = [" +
    "            '[object Int8Array]'," +
    "            '[object Uint8Array]'," +
    "            '[object Uint8ClampedArray]'," +
    "            '[object Int16Array]'," +
    "            '[object Uint16Array]'," +
    "            '[object Int32Array]'," +
    "            '[object Uint32Array]'," +
    "            '[object Float32Array]'," +
    "            '[object Float64Array]'" +
    "        ];" +
    "        var isArrayBufferView = null;" +
    "        if (" + this.JAVASCRIPT_UTIL_VAR_NAME + ".support.arrayBuffer) {" +
    "            isArrayBufferView =" +
    "                ArrayBuffer.isView ||" +
    "                function(obj) {" +
    "                    return obj && viewClasses.indexOf(Object.prototype.toString.call(obj)) > -1;" +
    "                };" +
    "        }" +
    "        var bodyUsed = false;" +
    "        this._bodyInit = body;" +
    "        if (!body) {" +
    "            this._bodyText = '';" +
    "        } else if (typeof body === 'string') {" +
    "            this._bodyText = body;" +
    "        } else if (" + this.JAVASCRIPT_UTIL_VAR_NAME + ".support.blob && Blob.prototype.isPrototypeOf(body)) {" +
    "            this._bodyBlob = body;" +
    "        } else if (" + this.JAVASCRIPT_UTIL_VAR_NAME + ".support.formData && FormData.prototype.isPrototypeOf(body)) {" +
    "            this._bodyFormData = body;" +
    "        } else if (" + this.JAVASCRIPT_UTIL_VAR_NAME + ".support.searchParams && URLSearchParams.prototype.isPrototypeOf(body)) {" +
    "            this._bodyText = body.toString();" +
    "        } else if (" + this.JAVASCRIPT_UTIL_VAR_NAME + ".support.arrayBuffer && " + this.JAVASCRIPT_UTIL_VAR_NAME + ".support.blob && " + this.JAVASCRIPT_UTIL_VAR_NAME + ".isDataView(body)) {" +
    "            this._bodyArrayBuffer = bufferClone(body.buffer);" +
    "            this._bodyInit = new Blob([this._bodyArrayBuffer]);" +
    "        } else if (" + this.JAVASCRIPT_UTIL_VAR_NAME + ".support.arrayBuffer && (ArrayBuffer.prototype.isPrototypeOf(body) || isArrayBufferView(body))) {" +
    "            this._bodyArrayBuffer = bufferClone(body);" +
    "        } else {" +
    "            this._bodyText = body = Object.prototype.toString.call(body);" +
    "        }" +
    "        this.blob = function () {" +
    "            if (bodyUsed) {" +
    "                return Promise.reject(new TypeError('Already read'));" +
    "            }" +
    "            bodyUsed = true;" +
    "            if (this._bodyBlob) {" +
    "                return Promise.resolve(this._bodyBlob);" +
    "            } else if (this._bodyArrayBuffer) {" +
    "                return Promise.resolve(new Blob([this._bodyArrayBuffer]));" +
    "            } else if (this._bodyFormData) {" +
    "                throw new Error('could not read FormData body as blob');" +
    "            } else {" +
    "                return Promise.resolve(new Blob([this._bodyText]));" +
    "            }" +
    "        };" +
    "        if (this._bodyArrayBuffer) {" +
    "            if (bodyUsed) {" +
    "                return Promise.reject(new TypeError('Already read'));" +
    "            }" +
    "            bodyUsed = true;" +
    "            if (ArrayBuffer.isView(this._bodyArrayBuffer)) {" +
    "                return Promise.resolve(" +
    "                  this._bodyArrayBuffer.buffer.slice(" +
    "                    this._bodyArrayBuffer.byteOffset," +
    "                    this._bodyArrayBuffer.byteOffset + this._bodyArrayBuffer.byteLength" +
    "                  )" +
    "                );" +
    "            } else {" +
    "                return Promise.resolve(this._bodyArrayBuffer);" +
    "            }" +
    "        }" +
    "        return this.blob().then(" + this.JAVASCRIPT_UTIL_VAR_NAME + ".readBlobAsArrayBuffer);" +
    "    }," +
    "    isString: function(variable) {" +
    "        return typeof variable === 'string' || variable instanceof String;" +
    "    }," +
    "    convertBodyRequest: function(body) {" +
    "        if (body == null) {" +
    "            return new Promise(function(resolve, reject) { resolve(null); });" +
    "        }" +
    "        if (" + this.JAVASCRIPT_UTIL_VAR_NAME + ".isString(body) || (" + this.JAVASCRIPT_UTIL_VAR_NAME + ".support.searchParams && body instanceof URLSearchParams)) {" +
    "            return new Promise(function(resolve, reject) { resolve(body.toString()); });" +
    "        }" +
    "        if (window.Response != null) {" +
    "            return new Response(body).arrayBuffer().then(function(arrayBuffer) {" +
    "                return Array.from(new Uint8Array(arrayBuffer));" +
    "            });" +
    "        }" +
    "        return " + this.JAVASCRIPT_UTIL_VAR_NAME + ".convertBodyToArrayBuffer(body).then(function(arrayBuffer) {" +
    "            return Array.from(new Uint8Array(arrayBuffer));" +
    "        });" +
    "    }," +
    "    arrayBufferToString: function(arrayBuffer) {" +
    "        var uint8Array = new Uint8Array(arrayBuffer);" +
    "        return uint8Array.reduce(function(acc, i) { return acc += String.fromCharCode.apply(null, [i]); }, '');" +
    "    }," +
    "    isBodyFormData: function(bodyString) {" +
    "        return bodyString.indexOf('------WebKitFormBoundary') >= 0;" +
    "    }," +
    "    getFormDataContentType: function(bodyString) {" +
    "        var boundary = bodyString.substr(2, 40);" +
    "        return 'multipart/form-data; boundary=' + boundary;" +
    "    }," +
    "    convertHeadersToJson: function(headers) {" +
    "        var headersObj = {};" +
    "        for (var header of headers.keys()) {" +
    "          var value = headers.get(header);" +
    "          headersObj[header] = value;" +
    "        }" +
    "        return headersObj;" +
    "    }," +
    "    convertJsonToHeaders: function(headersJson) {" +
    "        return new Headers(headersJson);" +
    "    }," +
    "    convertCredentialsToJson: function(credentials) {" +
    "        var credentialsObj = {};" +
    "        if (window.FederatedCredential != null && credentials instanceof FederatedCredential) {" +
    "          credentialsObj.type = credentials.type;" +
    "          credentialsObj.id = credentials.id;" +
    "          credentialsObj.name = credentials.name;" +
    "          credentialsObj.protocol = credentials.protocol;" +
    "          credentialsObj.provider = credentials.provider;" +
    "          credentialsObj.iconURL = credentials.iconURL;" +
    "        } else if (window.PasswordCredential != null && credentials instanceof PasswordCredential) {" +
    "          credentialsObj.type = credentials.type;" +
    "          credentialsObj.id = credentials.id;" +
    "          credentialsObj.name = credentials.name;" +
    "          credentialsObj.password = credentials.password;" +
    "          credentialsObj.iconURL = credentials.iconURL;" +
    "        } else {" +
    "          credentialsObj.type = 'default';" +
    "          credentialsObj.value = credentials;" +
    "        }" +
    "        return credentialsObj;" +
    "    }," +
    "    convertJsonToCredential: function(credentialsJson) {" +
    "        var credentials;" +
    "        if (window.FederatedCredential != null && credentialsJson.type === 'federated') {" +
    "          credentials = new FederatedCredential({" +
    "            id: credentialsJson.id," +
    "            name: credentialsJson.name," +
    "            protocol: credentialsJson.protocol," +
    "            provider: credentialsJson.provider," +
    "            iconURL: credentialsJson.iconURL" +
    "          });" +
    "        } else if (window.PasswordCredential != null && credentialsJson.type === 'password') {" +
    "          credentials = new PasswordCredential({" +
    "            id: credentialsJson.id," +
    "            name: credentialsJson.name," +
    "            password: credentialsJson.password," +
    "            iconURL: credentialsJson.iconURL" +
    "          });" +
    "        } else {" +
    "          credentials = credentialsJson.value == null ? undefined : credentialsJson.value;" +
    "        }" +
    "        return credentials;" +
    "    }" +
    "};";

  public static JAVASCRIPT_BRIDGE_JS_SOURCE: string = "if (window." + this.JAVASCRIPT_BRIDGE_NAME + " != null) {" +
    "  window." + this.JAVASCRIPT_BRIDGE_NAME + ".callHandler = function() {" +
    "    var _callHandlerID = setTimeout(function(){});" +
    "    window." + this.JAVASCRIPT_BRIDGE_NAME + "._callHandler(arguments[0], _callHandlerID, JSON.stringify(Array.prototype.slice.call(arguments, 1)));" +
    "    return new Promise(function(resolve, reject) {" +
    "      window." + this.JAVASCRIPT_BRIDGE_NAME + "[_callHandlerID] = {resolve: resolve, reject: reject};" +
    "    });" +
    "  };" +
    "}"+
    "if (window.top != null && window.top !== window && window." + this.JAVASCRIPT_BRIDGE_NAME + " == null) {" +
    "  window." + this.JAVASCRIPT_BRIDGE_NAME + " = {};" +
    "  window." + this.JAVASCRIPT_BRIDGE_NAME + ".callHandler = function() {" +
    "    var _callHandlerID = setTimeout(function(){});" +
    "    try {" +
    "      window.top." + this.JAVASCRIPT_BRIDGE_NAME + "._callHandler(arguments[0], _callHandlerID, JSON.stringify(Array.prototype.slice.call(arguments, 1)));" +
    "      return new Promise(function(resolve, reject) {" +
    "        window.top." + this.JAVASCRIPT_BRIDGE_NAME + "[_callHandlerID] = {resolve: resolve, reject: reject};" +
    "      });" +
    "    } catch (error) {" +
    "      return new Promise(function(resolve, reject) { reject(error); });" +
    "    }" +
    "  };" +
    "}" +
    "if (window." + this.JAVASCRIPT_BRIDGE_NAME + " != null) {" +
    "  " + this.UTIL_JS_SOURCE +
    "}";

  public static PLATFORM_READY_JS_SOURCE: string = "(function() {" +
    "  if ((window.top == null || window.top === window) && window." + this.JAVASCRIPT_BRIDGE_NAME + " != null && window." + this.JAVASCRIPT_BRIDGE_NAME + "._platformReady == null) {" +
    "    window.dispatchEvent(new Event('flutterInAppWebViewPlatformReady'));" +
    "    window." + this.JAVASCRIPT_BRIDGE_NAME + "._platformReady = true;" +
    "  }" +
    "})();";

  /** Fallback for InAppBrowser overlay navigations where bridge injection can lag a frame. */
  public static PLATFORM_READY_IN_APP_BROWSER_JS_SOURCE: string = "(function() {" +
    "  if (window.top != null && window.top !== window) { return; }" +
    "  if (window.__flutterInAppWebViewPlatformReadyDispatched) { return; }" +
    "  window.__flutterInAppWebViewPlatformReadyDispatched = true;" +
    "  if (window." + this.JAVASCRIPT_BRIDGE_NAME + " != null) {" +
    "    window." + this.JAVASCRIPT_BRIDGE_NAME + "._platformReady = true;" +
    "  }" +
    "  window.dispatchEvent(new Event('flutterInAppWebViewPlatformReady'));" +
    "})();";

  public static JAVASCRIPT_BRIDGE_JS_PLUGIN_SCRIPT: PluginScript = new PluginScript(
    JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_JS_PLUGIN_SCRIPT_GROUP_NAME,
    JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_JS_SOURCE,
    UserScriptInjectionTime.AT_DOCUMENT_START,
    null,
    true,
    null
  )
}