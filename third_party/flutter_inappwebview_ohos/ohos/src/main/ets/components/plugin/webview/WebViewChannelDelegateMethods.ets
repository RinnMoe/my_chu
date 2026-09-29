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

export enum WebViewChannelDelegateMethods {
  getUrl,
  getTitle,
  getProgress,
  loadUrl,
  postUrl,
  loadData,
  loadFile,
  evaluateJavascript,
  injectJavascriptFileFromUrl,
  injectCSSCode,
  injectCSSFileFromUrl,
  reload,
  goBack,
  canGoBack,
  goForward,
  canGoForward,
  goBackOrForward,
  canGoBackOrForward,
  stopLoading,
  isLoading,
  takeScreenshot,
  setSettings,
  getSettings,
  close,
  show,
  hide,
  isHidden,
  getCopyBackForwardList,
  startSafeBrowsing,
  /**
   * @deprecated
   */
  clearCache,
  clearSslPreferences,
  /**
   * @deprecated
   */
  findAll,
  findNext,
  clearMatches,
  scrollTo,
  scrollBy,
  pause,
  resume,
  pauseTimers,
  resumeTimers,
  printCurrentPage,
  getContentHeight,
  getContentWidth,
  zoomBy,
  getOriginalUrl,
  getZoomScale,
  getSelectedText,
  getHitTestResult,
  pageDown,
  pageUp,
  saveWebArchive,
  zoomIn,
  zoomOut,
  clearFocus,
  setContextMenu,
  requestFocusNodeHref,
  requestImageRef,
  getScrollX,
  getScrollY,
  getCertificate,
  clearHistory,
  addUserScript,
  removeUserScript,
  removeUserScriptsByGroupName,
  removeAllUserScripts,
  callAsyncJavaScript,
  isSecureContext,
  createWebMessageChannel,
  postWebMessage,
  addWebMessageListener,
  canScrollVertically,
  canScrollHorizontally,
  isInFullscreen,
  clearFormData,
  getMetaThemeColor,
  setAllMediaPlaybackSuspended,
  closeAllMediaPresentations,
  requestMediaPlaybackState,
}