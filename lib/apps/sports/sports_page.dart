import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../capabilities/stuh5_request_keep_alive.dart';
import '../../services/service_endpoints.dart';

/// 长大体育：宿主播种统一身份根会话，站点自行完成根页到 OAuth 回调登录。
class SportsPage extends StatelessWidget {
  const SportsPage({super.key});

  /// 迁移前的长大体育页面把登录令牌和用户摘要写入 Local Storage。
  /// 仅在当前 WebView 会话的首次长大体育文档中清理这些旧状态；跨域 OAuth
  /// 回调回到长大体育时保留本次新建立的会话。回调参数及登录请求均由站点
  /// SPA 处理，下面只负责旧状态清理、授权页辅助点击和会话 readiness 标记。
  static final UnmodifiableListView<UserScript> _initialUserScripts =
      UnmodifiableListView([
        Stuh5RequestKeepAlive.userScript,
        UserScript(
          groupName: 'stuh5-legacy-auth-cleanup',
          source: r'''
(() => {
    const hostname = location.hostname.toLowerCase();
    if (hostname === 'ids.chd.edu.cn' || hostname === 'identity.chd.edu.cn') {
      let authorizationTriggered = false;
      const normalizedText = (value) => String(value || '')
        .replace(/\s+/g, '')
        .trim();
      const isVisible = (element) => {
        if (!element || element.disabled) return false;
        const style = window.getComputedStyle(element);
        return style.display !== 'none' &&
          style.visibility !== 'hidden' &&
          element.getClientRects().length > 0;
      };
      const tryAuthorize = () => {
        if (authorizationTriggered) return;
        const bodyText = document.body?.innerText || '';
        if (!bodyText.includes('授权申请') ||
            !bodyText.includes('申请获得以下授权')) return;
        const candidate = Array.from(document.querySelectorAll(
          'button, a, input, [role="button"], div, span'
        )).find((element) => {
          const label = normalizedText(
            element.innerText ||
              element.value ||
              element.getAttribute('aria-label')
          );
          return label === '授权' && isVisible(element);
        });
        if (!candidate) return;
        authorizationTriggered = true;
        try {
          candidate.click();
        } catch (_) {
          authorizationTriggered = false;
        }
      };
      window.setInterval(tryAuthorize, 100);
      tryAuthorize();
      return;
    }
    if (hostname !== 'stuh5.chd.edu.cn') return;
    const marker = '__mychu_sports_unified_auth_v1__';
    const identityEpochMarker = '__mychu_sports_unified_auth_epoch_v1__';
    const oauthLandingMarker = '__mychu_sports_oauth_landing_v1__';
    const identityEpoch = typeof window.__mychuWebViewIdentityEpoch === 'string'
      ? window.__mychuWebViewIdentityEpoch
      : '';
    let oauthLandingRequested = false;
    const storageRemove = (storage, key) => {
      try { storage.removeItem(key); } catch (_) {}
    };
    const storageGet = (storage, key) => {
      try { return storage.getItem(key); } catch (_) { return null; }
    };
    const storageSet = (storage, key, value) => {
      try { storage.setItem(key, value); } catch (_) {}
    };
    const routePath = () => (location.hash || '').split('?')[0];
    const clearOAuthLandingMarkers = () => {
      storageRemove(localStorage, oauthLandingMarker);
      storageRemove(sessionStorage, oauthLandingMarker);
    };
    const clearLegacyStorage = () => {
      localStorage.removeItem('ACCESS_TOKEN');
      localStorage.removeItem('REFRESH_TOKEN');
      localStorage.removeItem('tenantId');
      localStorage.removeItem('storage_data');
      for (const key of Object.keys(localStorage)) {
        if (key.startsWith('vuex_')) localStorage.removeItem(key);
      }
      clearOAuthLandingMarkers();
    };
    try {
      const cleanupDone = identityEpoch
        ? storageGet(localStorage, identityEpochMarker) === identityEpoch
        : storageGet(sessionStorage, marker) === '1' ||
          storageGet(localStorage, marker) === '1';
      if (!cleanupDone) {
        clearLegacyStorage();
        if (identityEpoch) {
          storageSet(localStorage, identityEpochMarker, identityEpoch);
        }
        storageSet(localStorage, marker, '1');
        storageSet(sessionStorage, marker, '1');
      }
    } catch (_) {}
    const maybeLandOnExistingSession = () => {
      const path = routePath();
      if (path !== '#/' && path !== '#/pages/index') return;
      if (storageGet(localStorage, oauthLandingMarker) !== 'completed') return;
      // This is a host-only readiness signal. It contains no token or cookie;
      // it lets the generic WebView gate reveal an already authenticated SPA
      // when this document does not need to visit IDS again.
      try {
        document.documentElement.dataset.mychuAuthenticationReady = '1';
      } catch (_) {}
    };
    const installOAuthLanding = () => {
      if (typeof window.uni?.switchTab !== 'function' ||
          window.__mychuSportsOAuthLandingInstalled) return;
      const originalSwitchTab = window.uni.switchTab;
      window.uni.switchTab = function (options) {
        const requestedRoute = String(options?.url || '').split('?')[0];
        const isOAuthCallback = routePath() === '#/pages/oauth/callback';
        const callbackSucceeded =
          !!document.querySelector('.status-success') ||
          (document.body?.innerText || '').includes('登录成功');
        if (!isOAuthCallback || requestedRoute !== '/pages/index' ||
            !callbackSucceeded ||
            oauthLandingRequested) {
          return originalSwitchTab.apply(this, arguments);
        }
        oauthLandingRequested = true;
        storageSet(localStorage, oauthLandingMarker, 'completed');
        storageSet(sessionStorage, oauthLandingMarker, 'completed');
        try {
          document.documentElement.dataset.mychuAuthenticationReady = '1';
        } catch (_) {}
        return originalSwitchTab.apply(this, arguments);
      };
      window.__mychuSportsOAuthLandingInstalled = true;
    };
    const tick = () => {
      maybeLandOnExistingSession();
      installOAuthLanding();
    };
    window.addEventListener('hashchange', tick);
    window.setInterval(tick, 200);
    tick();
})();
''',
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return AuthenticatedWebViewCapability.pageForService(
      title: '长大体育',
      url: CampusServiceEndpoints.sportsPortalHomeUri.toString(),
      serviceId: CampusServices.sportsPortal,
      showBottomBar: false,
      waitForAuthenticationPage: true,
      autoCompleteAuthentication: true,
      initialUserScripts: _initialUserScripts,
    );
  }
}
