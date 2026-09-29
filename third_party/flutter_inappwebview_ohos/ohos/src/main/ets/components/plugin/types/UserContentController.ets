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

import InAppWebView from '../webview/in_app_webview/InAppWebView';
import ContentWorld from './ContentWorld';
import { Disposable } from './Disposable';
import PluginScript from './PluginScript';
import UserScript from './UserScript';
import { UserScriptInjectionTime } from './UserScriptInjectionTime';
import { HashMap, HashSet, List } from '@kit.ArkTS';
import Util from '../Util';
import PluginScriptsUtil from '../plugin_scripts_js/PluginScriptsUtil';
import JavaScriptBridgeJS from '../plugin_scripts_js/JavaScriptBridgeJS';
import { common } from '@kit.AbilityKit';
import EventConstant from '../EventConstant'

const DOCUMENT_READY_WRAPPER_JS_SOURCE = "if (document.readyState === 'interactive' || document.readyState === 'complete') { " +
  "  " + PluginScriptsUtil.VAR_PLACEHOLDER_VALUE +
  "}";

const USER_SCRIPTS_AT_DOCUMENT_START_WRAPPER_JS_SOURCE = "if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + " != null && (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "._userScriptsAtDocumentStartLoaded == null || !window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "._userScriptsAtDocumentStartLoaded)) {" +
  "  window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "._userScriptsAtDocumentStartLoaded = true;" +
  "  " + PluginScriptsUtil.VAR_PLACEHOLDER_VALUE +
  "}";

const USER_SCRIPTS_AT_DOCUMENT_END_WRAPPER_JS_SOURCE = "if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + " != null && (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "._userScriptsAtDocumentEndLoaded == null || !window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "._userScriptsAtDocumentEndLoaded)) {" +
  "  window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "._userScriptsAtDocumentEndLoaded = true;" +
  "  " + PluginScriptsUtil.VAR_PLACEHOLDER_VALUE +
  "}";

const CONTENT_WORLD_WRAPPER_JS_SOURCE = "(function() {" +
  "  var iframeId = '" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "_" + PluginScriptsUtil.VAR_CONTENT_WORLD_NAME + "';" +
  "  var sourceCode = " + PluginScriptsUtil.VAR_JSON_SOURCE_ENCODED + ";" +
  "  function tryInject() {" +
  "    if (document.body == null) {return false;}" +
  "    var iframe = document.getElementById(iframeId);" +
  "    if (iframe == null) {" +
  "      iframe = document.createElement('iframe');" +
  "      iframe.id = iframeId;" +
  "      iframe.style = 'display: none; z-index: 0; position: absolute; width: 0px; height: 0px';" +
  "      document.body.append(iframe);" +
  "    }" +
  "    if (iframe.contentWindow.document.querySelector('#" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "_plugin_scripts') == null) {" +
  "      return false;" +
  "    }" +
  "    var script = iframe.contentWindow.document.createElement('script');" +
  "    script.innerHTML = sourceCode;" +
  "    iframe.contentWindow.document.body.append(script);" +
  "    return true;" +
  "  }" +
  "  if (!tryInject()) {" +
  "    var interval = setInterval(function() {" +
  "      if (tryInject()) { clearInterval(interval); }" +
  "    });" +
  "  }" +
  "})();";

const CONTENT_WORLDS_GENERATOR_JS_SOURCE = "(function() {" +
  "  var contentWorldNames = [" + PluginScriptsUtil.VAR_CONTENT_WORLD_NAME_ARRAY + "];" +
  "  var pluginSource = " + PluginScriptsUtil.VAR_JSON_SOURCE_ENCODED + ";" +
  "  function tryCreate() {" +
  "    if (document.body == null) {return false;}" +
  "    for (var contentWorldName of contentWorldNames) {" +
  "      var iframeId = '" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "_' + contentWorldName;" +
  "      var iframe = document.getElementById(iframeId);" +
  "      if (iframe == null) {" +
  "        iframe = document.createElement('iframe');" +
  "        iframe.id = iframeId;" +
  "        iframe.style = 'display: none; z-index: 0; position: absolute; width: 0px; height: 0px';" +
  "        document.body.append(iframe);" +
  "      }" +
  "      if (iframe.contentWindow.document.getElementById('" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "_plugin_scripts') == null) {" +
  "        var script = iframe.contentWindow.document.createElement('script');" +
  "        script.id = '" + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "_plugin_scripts';" +
  "        script.innerHTML = pluginSource;" +
  "        iframe.contentWindow.document.body.append(script);" +
  "      }" +
  "    }" +
  "    return true;" +
  "  }" +
  "  if (!tryCreate()) {" +
  "    var interval = setInterval(function() {" +
  "      if (tryCreate()) { clearInterval(interval); }" +
  "    });" +
  "  }" +
  "})();";

export default class UserContentController implements Disposable {
  protected static LOG_TAG: string = "UserContentController";
  private contentWorlds: Set<ContentWorld> = new Set<ContentWorld>().add(ContentWorld.PAGE);
  private inAppWebView: InAppWebView | null
  private userOnlyScripts = new HashMap<UserScriptInjectionTime, HashSet<UserScript>>();
  private pluginScripts = new HashMap<UserScriptInjectionTime, HashSet<PluginScript>>()
  private isSupportedDocumentStartScript = false
  private allStartScriptItem = new List<ScriptItem>()
  private contentWorldsCreatorScript: ScriptItem | null = null
  private scriptHandlerMap = new HashMap<UserScript, ScriptItem>()

  constructor(inAppWebView: InAppWebView) {
    this.inAppWebView = inAppWebView;
    this.userOnlyScripts.set(UserScriptInjectionTime.AT_DOCUMENT_START, new HashSet<UserScript>())
    this.userOnlyScripts.set(UserScriptInjectionTime.AT_DOCUMENT_END, new HashSet<UserScript>())

    this.pluginScripts.set(UserScriptInjectionTime.AT_DOCUMENT_START, new HashSet<PluginScript>());
    this.pluginScripts.set(UserScriptInjectionTime.AT_DOCUMENT_END, new HashSet<PluginScript>());
  }

  generateWrappedCodeForDocumentStart(): string {
    return Util.replaceAll(
      DOCUMENT_READY_WRAPPER_JS_SOURCE,
      PluginScriptsUtil.VAR_PLACEHOLDER_VALUE,
      this.generateCodeForDocumentStart())
  }

  generateCodeForDocumentStart(): string {
    let injectionTime = UserScriptInjectionTime.AT_DOCUMENT_START;
    let js = "";
    js += this.generatePluginScriptsCodeAt(injectionTime);
    js += this.generateContentWorldsCreatorCode();
    js += this.generateUserOnlyScriptsCodeAt(injectionTime);
    js = USER_SCRIPTS_AT_DOCUMENT_START_WRAPPER_JS_SOURCE.replace(PluginScriptsUtil.VAR_PLACEHOLDER_VALUE, js);
    return js;
  }

  generatePluginScriptsCodeAt(injectionTime: UserScriptInjectionTime) {
    let js = "";
    let scripts = this.getPluginScriptsAt(injectionTime);
    for (let script of scripts) {
      let source = ";" + script.getSource();
      source = this.wrapSourceCodeInContentWorld(script.getContentWorld(), source);
      js += source;
    }
    return js;
  }

  generateUserOnlyScriptsCodeAt(injectionTime: UserScriptInjectionTime): string {
    let js = "";
    let scripts = this.getUserOnlyScriptsAt(injectionTime);
    for (let script of scripts) {
      let source = ";" + script.getSource();
      source = this.wrapSourceCodeInContentWorld(script.getContentWorld(), source);
      js += source;
    }
    return js;
  }

  getPluginScriptsAt(injectionTime: UserScriptInjectionTime): HashSet<PluginScript> {
    return this.pluginScripts.get(injectionTime);
  }

  getUserOnlyScriptsAt(injectionTime: UserScriptInjectionTime): HashSet<UserScript> {
    return this.userOnlyScripts.get(injectionTime);
  }

  wrapSourceCodeInContentWorld(contentWorld: ContentWorld, source: string): string {
    let sourceWrapped = contentWorld == null || contentWorld.equals(ContentWorld.PAGE) ? source :
    CONTENT_WORLD_WRAPPER_JS_SOURCE
      .replace(PluginScriptsUtil.VAR_CONTENT_WORLD_NAME, UserContentController.escapeContentWorldName(contentWorld.getName()))
      .replace(PluginScriptsUtil.VAR_JSON_SOURCE_ENCODED, UserContentController.escapeCode(source));

    return sourceWrapped;
  }

  static escapeContentWorldName(name: string): string {
    return Util.replaceAll(name, "'", "\\\\'");
  }

  generateWrappedCodeForDocumentEnd(): string {
    let injectionTime = UserScriptInjectionTime.AT_DOCUMENT_END;
    let js = "";
    if (!this.isSupportedDocumentStartScript) {
      // try to reload scripts if they were not loaded during the AT_DOCUMENT_START event
      js += this.generateCodeForDocumentStart();
    }
    js += this.generatePluginScriptsCodeAt(injectionTime);
    js += this.generateUserOnlyScriptsCodeAt(injectionTime);
    js = USER_SCRIPTS_AT_DOCUMENT_END_WRAPPER_JS_SOURCE.replace(PluginScriptsUtil.VAR_PLACEHOLDER_VALUE, js);
    return js;
  }

  public static escapeCode(code: string): string {
    let escapedCode = JSON.stringify(code);
    // escapedCode = escapedCode.substring(1, escapedCode.length() - 1);
    return escapedCode;
  }

  private updateContentWorldsCreatorScript(): void {
    let source: string = this.generateContentWorldsCreatorCode();
    if (this.contentWorldsCreatorScript != null) {
      this.allStartScriptItem.remove(this.contentWorldsCreatorScript)
    }
    if (source && source.length > 0) {
      this.contentWorldsCreatorScript = this.addDocumentStartJavaScript(source, ["*"]);
    }
  }

  public generateContentWorldsCreatorCode(): string {
    if (this.contentWorlds.size == 1) {
      return "";
    }

    let source = "";
    let pluginScriptsRequired = this.getPluginScriptsRequiredInAllContentWorlds();
    for (let script of pluginScriptsRequired) {
      source += script.getSource();
    }
    let contentWorldsNames = new Array<string>();
    for (let contentWorld of this.contentWorlds) {
      if (contentWorld.equals(ContentWorld.PAGE)) {
        continue;
      }
      contentWorldsNames.push("'" + UserContentController.escapeContentWorldName(contentWorld.getName()) + "'");
    }

    return CONTENT_WORLDS_GENERATOR_JS_SOURCE
      .replace(PluginScriptsUtil.VAR_CONTENT_WORLD_NAME_ARRAY, contentWorldsNames.join(", "))
      .replace(PluginScriptsUtil.VAR_JSON_SOURCE_ENCODED, UserContentController.escapeCode(source.toString()));
  }

  public addPluginScript(pluginScript: PluginScript): boolean {
    let injectionTime = pluginScript.getInjectionTime();
    let scripts = this.pluginScripts.get(injectionTime);
    for (let existing of scripts) {
      if (existing.equals(pluginScript)) {
        return false;
      }
    }
    scripts.add(pluginScript);

    let contentWorld: ContentWorld = pluginScript.getContentWorld();
    if (contentWorld != null) {
      this.contentWorlds.add(contentWorld);
    }
    this.updateContentWorldsCreatorScript();
    if (pluginScript.getInjectionTime() == UserScriptInjectionTime.AT_DOCUMENT_START) {
      let scriptHandler = this.addDocumentStartJavaScript(
        this.wrapSourceCodeInContentWorld(pluginScript.getContentWorld(), pluginScript.getSource()),
        pluginScript.getAllowedOriginRulesArray()
      );
      this.scriptHandlerMap.set(pluginScript, scriptHandler);
    }
    this.onDocumentStartChanged()
    return true;
  }

  addPluginScripts(pluginScripts: Array<PluginScript>) {
    for (let pluginScript of pluginScripts) {
      this.addPluginScript(pluginScript);
    }
  }

  removePluginScript(pluginScript: PluginScript) {
    let scriptHandler = this.scriptHandlerMap.get(pluginScript);
    if (scriptHandler != null) {
      this.allStartScriptItem.remove(scriptHandler);
      this.scriptHandlerMap.remove(pluginScript);
      this.updateContentWorldsCreatorScript();
      this.onDocumentStartChanged()
    }
    return this.pluginScripts.get(pluginScript.getInjectionTime()).remove(pluginScript);
  }

  public removeAllUserOnlyScripts(): void {
    for (let userOnlyScript of this.userOnlyScripts.get(UserScriptInjectionTime.AT_DOCUMENT_START)) {
      let scriptHandler = this.scriptHandlerMap.get(userOnlyScript);
      if (scriptHandler != null) {
        this.allStartScriptItem.remove(scriptHandler);
        this.scriptHandlerMap.remove(userOnlyScript);
      }
    }
    this.onDocumentStartChanged()
    this.userOnlyScripts.get(UserScriptInjectionTime.AT_DOCUMENT_START).clear();
    this.userOnlyScripts.get(UserScriptInjectionTime.AT_DOCUMENT_END).clear();
  }

  public removeAllPluginScripts(): void {
    for (let pluginScript of this.pluginScripts.get(UserScriptInjectionTime.AT_DOCUMENT_START)) {
      let scriptHandler = this.scriptHandlerMap.get(pluginScript);
      if (scriptHandler != null) {
        this.allStartScriptItem.remove(scriptHandler);
        this.scriptHandlerMap.remove(pluginScript);
      }
    }
    this.onDocumentStartChanged()
    this.pluginScripts.get(UserScriptInjectionTime.AT_DOCUMENT_START).clear();
    this.pluginScripts.get(UserScriptInjectionTime.AT_DOCUMENT_END).clear();
  }

  public addUserOnlyScript(userOnlyScript: UserScript): boolean {
    let contentWorld: ContentWorld = userOnlyScript.getContentWorld()
    if (contentWorld != null) {
      this.contentWorlds.add(contentWorld);
    }
    this.updateContentWorldsCreatorScript();
    if (userOnlyScript.getInjectionTime() == UserScriptInjectionTime.AT_DOCUMENT_START) {
      let scriptHandler = this.addDocumentStartJavaScript(
        this.wrapSourceCodeInContentWorld(userOnlyScript.getContentWorld(), userOnlyScript.getSource()),
        userOnlyScript.getAllowedOriginRulesArray()
      );
      this.scriptHandlerMap.set(userOnlyScript, scriptHandler);
    }
    this.onDocumentStartChanged()
    return this.userOnlyScripts.get(userOnlyScript.getInjectionTime()).add(userOnlyScript);
  }

  getUserOnlyScriptAsList(): HashSet<UserScript> {
    let userOnlyScripts = new HashSet<UserScript>();
    let collection = this.userOnlyScripts.values();
    for (let list of collection) {
      for (let listElement of list) {
        userOnlyScripts.add(listElement);
      }
    }
    return userOnlyScripts;
  }

  getPluginScriptAsList(): HashSet<PluginScript> {
    let pluginScripts = new HashSet<PluginScript>();
    let collection = this.pluginScripts.values();
    for (let list of collection) {
      for (let listElement of list) {
        pluginScripts.add(listElement);
      }
    }
    return pluginScripts;
  }

  private findStoredUserOnlyScript(userOnlyScript: UserScript): UserScript | null {
    let scripts = this.userOnlyScripts.get(userOnlyScript.getInjectionTime());
    for (let script of scripts) {
      if (script.equals(userOnlyScript)) {
        return script;
      }
    }
    return null;
  }

  removeUserOnlyScript(userOnlyScript: UserScript): boolean {
    let scriptToRemove = this.findStoredUserOnlyScript(userOnlyScript);
    if (scriptToRemove == null) {
      return false;
    }
    let scriptHandler = this.scriptHandlerMap.get(scriptToRemove);
    if (scriptHandler != null) {
      this.allStartScriptItem.remove(scriptHandler);
      this.scriptHandlerMap.remove(scriptToRemove);
      this.updateContentWorldsCreatorScript();
      this.onDocumentStartChanged()
    }
    return this.userOnlyScripts.get(scriptToRemove.getInjectionTime()).remove(scriptToRemove);
  }

  public removeUserOnlyScriptAt(index: number, injectionTime: UserScriptInjectionTime): boolean {
    let scripts = this.userOnlyScripts.get(injectionTime);
    let currentIndex = 0;
    for (let userOnlyScript of scripts) {
      if (currentIndex === index) {
        return this.removeUserOnlyScript(userOnlyScript);
      }
      currentIndex++;
    }
    return false;
  }

  public removeUserOnlyScriptsByGroupName(groupName: string): void {
    let userOnlyScripts = this.getUserOnlyScriptAsList();
    for (let userOnlyScript of userOnlyScripts) {
      if (groupName == userOnlyScript.getGroupName()) {
        this.removeUserOnlyScript(userOnlyScript);
      }
    }
  }

  addUserOnlyScripts(userOnlyScripts: Array<UserScript>) {
    for (let userOnlyScript of userOnlyScripts) {
      this.addUserOnlyScript(userOnlyScript);
    }
  }

  resetContentWorlds() {
    this.contentWorlds.clear();
    this.contentWorlds.add(ContentWorld.PAGE);

    let pluginScripts = this.getPluginScriptAsList();
    for (let pluginScript of pluginScripts) {
      let contentWorld = pluginScript.getContentWorld();
      this.contentWorlds.add(contentWorld);
    }

    let userOnlyScripts = this.getUserOnlyScriptAsList();
    for (let userOnlyScript of userOnlyScripts) {
      let contentWorld = userOnlyScript.getContentWorld();
      this.contentWorlds.add(contentWorld);
    }
  }

  getPluginScriptsRequiredInAllContentWorlds(): HashSet<PluginScript> {
    let pluginScriptsRequired = new HashSet<PluginScript>();
    let scripts = this.getPluginScriptsAt(UserScriptInjectionTime.AT_DOCUMENT_START);
    for (let script of scripts) {
      if (script.isRequiredInAllContentWorlds()) {
        pluginScriptsRequired.add(script);
      }
    }
    return pluginScriptsRequired;
  }

  generateCodeForScriptEvaluation(source: string, contentWorld: ContentWorld | null): string {
    if (contentWorld != null && !contentWorld.equals(ContentWorld.PAGE)) {
      let sourceWrapped = "";
      if (!this.hasContentWorld(contentWorld)) {
        this.contentWorlds.add(contentWorld);

        let pluginScriptsSource = "";
        let pluginScriptsRequired = this.getPluginScriptsRequiredInAllContentWorlds();
        for (let script of pluginScriptsRequired) {
          pluginScriptsSource += script.getSource();
        }
        let contentWorldCreatorCode = CONTENT_WORLDS_GENERATOR_JS_SOURCE
          .replace(PluginScriptsUtil.VAR_CONTENT_WORLD_NAME_ARRAY, "'" + UserContentController.escapeContentWorldName(contentWorld.getName()) + "'")
          .replace(PluginScriptsUtil.VAR_JSON_SOURCE_ENCODED, UserContentController.escapeCode(pluginScriptsSource.toString()));
        sourceWrapped += (contentWorldCreatorCode + ";")
      }
      sourceWrapped += this.wrapSourceCodeInContentWorld(contentWorld, source)
      return sourceWrapped;
    }
    return source;
  }

  private hasContentWorld(contentWorld: ContentWorld) {
    for (let contentWorldsElement of this.contentWorlds) {
      if (contentWorld.equals(contentWorldsElement)) {
        return true;
      }
    }
    return false;
  }

  public dispose(): void {
    if (this.contentWorldsCreatorScript != null) {
      this.allStartScriptItem.remove(this.contentWorldsCreatorScript)
      this.contentWorldsCreatorScript = null;
    }
    this.removeAllUserOnlyScripts();
    this.removeAllPluginScripts();
    this.scriptHandlerMap.clear();
    this.allStartScriptItem.clear();
    this.contentWorlds.clear();
    this.contentWorlds.add(ContentWorld.PAGE);
    this.inAppWebView = null;
  }

  private addDocumentStartJavaScript(source: string, scriptRule: Array<string>): ScriptItem {
    let scriptItem: ScriptItem = {
      script: source, scriptRules: scriptRule
    }
    this.allStartScriptItem.add(scriptItem)
    return scriptItem;
  }

  getStartScripts() {
    return this.allStartScriptItem.convertToArray()
  }

  private onDocumentStartChanged(){
    if (this.inAppWebView == null) {
      return;
    }
    let context = this.inAppWebView.context as common.UIAbilityContext;
    context.eventHub.emit(EventConstant.EVENT_UPDATE_STARTSCRIPTS, this.allStartScriptItem.convertToArray())
  }
}