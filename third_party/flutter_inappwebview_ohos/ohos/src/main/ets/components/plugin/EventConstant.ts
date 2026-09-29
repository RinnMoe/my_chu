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

export default class EventConstant {
    public static readonly EVENT_PULL_SETREFRESHING = "pull_setRefreshing";
    public static readonly EVENT_PULL_UPDATE_APPEARANCE = "pull_updateAppearance";
    public static readonly EVENT_UPDATE_STARTSCRIPTS = "update_startScripts";
    public static readonly EVENT_UPDATE_CACHEENABLE = "update_cacheEnable";
    public static readonly EVENT_UPDATE_TRANSPARENT_BACKGROUND = "update_transparentBackground";
    /** InAppWebView 销毁前通知 OhosWebView 从 ArkUI 树移除 Web 组件，释放 web-surface GPU 缓冲 */
    public static readonly EVENT_UNMOUNT_WEB_COMPONENT = "unmount_web_component";
    /** 通知 OhosWebView 将 Web 组件重新挂载到 ArkUI 树 */
    public static readonly EVENT_MOUNT_WEB_COMPONENT = "mount_web_component";
}