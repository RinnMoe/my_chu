import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Keeps long-running HTTP requests made by the 长大体育 SPA alive.
///
/// The patch is deliberately scoped by the request target's hostname. It is
/// installed in the page world at document start so the SPA's first XHR/fetch
/// calls use it, while requests to every other host keep their native browser
/// cancellation semantics. Target GET/HEAD calls may use one delayed hedge,
/// except for the SPA's OAuth-start request; write requests are always
/// single-shot.
class Stuh5RequestKeepAlive {
  Stuh5RequestKeepAlive._();

  static const groupName = 'stuh5-request-keep-alive';

  static const source = r'''
(() => {
  'use strict';

  const TARGET_HOST = 'stuh5.chd.edu.cn';
  const PATCH_FLAG =
      typeof Symbol === 'function' && typeof Symbol.for === 'function'
          ? Symbol.for('mychu.stuh5.keepalive.installed')
          : '__mychu_stuh5_keepalive_installed_v1__';

  // A WebView can inject the same user script into the main document and
  // child frames. Keep one patch per JavaScript world.
  if (window[PATCH_FLAG]) return;
  window[PATCH_FLAG] = true;

  // The host privacy script disables console output before this script runs.
  // Keep the switch for local source-level debugging, but do not emit URLs,
  // headers, request bodies, or response data from the production script.
  const DEBUG = false;
  const log = (...args) => {
    if (!DEBUG) return;
    try { console.debug('[STUH5 KeepAlive]', ...args); } catch (_) {}
  };
  const warn = (...args) => {
    if (!DEBUG) return;
    try { console.warn('[STUH5 KeepAlive]', ...args); } catch (_) {}
  };

  function resolveUrl(rawUrl) {
    try {
      if (typeof URL === 'function' && rawUrl instanceof URL) {
        return rawUrl;
      }
      if (typeof URL !== 'function') return null;
      return new URL(String(rawUrl), location.href);
    } catch (_) {
      return null;
    }
  }

  function targetHttpUrl(rawUrl) {
    const url = resolveUrl(rawUrl);
    if (!url || url.hostname !== TARGET_HOST) return null;
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    return url;
  }

  // The live ba0d request wrapper delegates to uni.request. Patching that
  // stable lower boundary also covers already-cached ba0d imports without
  // depending on a brittle Webpack module-cache mutation.
  const LONG_TIMEOUT_MS = 24 * 60 * 60 * 1000;
  const HEDGE_MAX_ATTEMPTS = 2;
  const HEDGE_DELAY_MS = 1500;
  const UNI_PATCH_MARKER = '__mychu_stuh5_uni_request_patched_v2__';

  function normalizedMethod(method) {
    return String(method || 'GET').toUpperCase();
  }

  function normalizedPath(path) {
    return String(path || '/').replace(/^\/+/, '/').replace(/\/+$/, '') || '/';
  }

  function isOAuthStartRequest(url) {
    return normalizedPath(url?.pathname) ===
        '/admin-api/system/auth/social-auth-redirect';
  }

  function canHedge(method, url) {
    const normalized = normalizedMethod(method);
    return (normalized === 'GET' || normalized === 'HEAD') &&
        !isOAuthStartRequest(url);
  }

  function hasCallbackStyle(options) {
    return ['success', 'fail', 'complete'].some(
      (key) => typeof options?.[key] === 'function',
    );
  }

  function uniResultSucceeded(result) {
    // H5 uni.request resolves [error, response]. A non-tuple resolution is
    // treated as success to preserve the native promise contract for callers.
    return !Array.isArray(result) || !result[0];
  }

  function firstSuccessful(requestFactory) {
    return new Promise((resolve, reject) => {
      let settled = false;
      let launched = 0;
      let failures = 0;
      let hedgeTimer;
      const errors = [];

      const cleanup = () => {
        if (hedgeTimer !== undefined) clearTimeout(hedgeTimer);
      };

      const succeed = (value) => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve(value);
      };

      const fail = (error) => {
        failures += 1;
        errors.push(error);
        if (
          !settled &&
          launched >= HEDGE_MAX_ATTEMPTS &&
          failures >= HEDGE_MAX_ATTEMPTS
        ) {
          settled = true;
          cleanup();
          reject(errors[errors.length - 1]);
        }
      };

      const launch = (index) => {
        if (settled || launched > index || index >= HEDGE_MAX_ATTEMPTS) {
          return;
        }
        launched += 1;

        let request;
        try {
          // Call the first attempt synchronously so the original request is
          // issued immediately, rather than after a Promise microtask.
          request = requestFactory(index);
        } catch (error) {
          fail(error);
          if (!settled && launched < HEDGE_MAX_ATTEMPTS) launch(launched);
          return;
        }

        Promise.resolve(request).then(
          (result) => {
            if (uniResultSucceeded(result)) {
              succeed(result);
            } else {
              fail(result[0]);
              if (!settled && launched < HEDGE_MAX_ATTEMPTS) {
                launch(launched);
              }
            }
          },
          (error) => {
            fail(error);
            if (!settled && launched < HEDGE_MAX_ATTEMPTS) {
              launch(launched);
            }
          },
        );
      };

      hedgeTimer = setTimeout(() => launch(1), HEDGE_DELAY_MS);
      launch(0);
    });
  }

  function patchUniRequest(uniObject) {
    if (!uniObject || typeof uniObject.request !== 'function') return false;

    const current = uniObject.request;
    if (current[UNI_PATCH_MARKER]) return true;

    const original = current;
    const patched = function(options, ...rest) {
      const protectedUrl = options?.url == null
          ? null
          : targetHttpUrl(options.url);
      if (
        !options ||
        typeof options !== 'object' ||
        options.url == null ||
        !protectedUrl
      ) {
        return Reflect.apply(original, this, [options, ...rest]);
      }

      // ba0d defaults to 10 seconds when timeout is falsy, so use a finite
      // 24-hour value here. XHR itself is still forced to timeout=0 below.
      const protectedOptions = {
        ...options,
        timeout: LONG_TIMEOUT_MS,
      };

      const invoke = () =>
        Reflect.apply(original, this, [{...protectedOptions}, ...rest]);

      // Callback-style uni.request callers must not receive duplicate
      // callbacks. The page's ba0d promise path has no callbacks and can use
      // the bounded GET/HEAD hedge.
      if (!canHedge(protectedOptions.method, protectedUrl) ||
          hasCallbackStyle(options)) {
        return invoke();
      }

      return firstSuccessful(invoke);
    };

    try {
      Object.defineProperty(patched, UNI_PATCH_MARKER, { value: true });
      Object.assign(patched, original);
      uniObject.request = patched;
      if (uniObject.request !== patched) {
        Object.defineProperty(uniObject, 'request', {
          configurable: true,
          writable: true,
          value: patched,
        });
      }
      log('uni-request-protected');
      return true;
    } catch (_) {
      return false;
    }
  }

  function installUniRequestPatch() {
    try {
      return patchUniRequest(window.uni);
    } catch (_) {
      return false;
    }
  }

  // uni is created by the H5 runtime after document-start. Hook its first
  // assignment when possible, and keep a short bounded poll as a fallback.
  try {
    const currentUni = window.uni;
    if (!currentUni) {
      const descriptor = Object.getOwnPropertyDescriptor(window, 'uni');
      if (!descriptor || descriptor.configurable) {
        let storedUni = descriptor?.value;
        Object.defineProperty(window, 'uni', {
          configurable: true,
          enumerable: descriptor?.enumerable ?? true,
          get() {
            const value = descriptor?.get
              ? descriptor.get.call(window)
              : storedUni;
            patchUniRequest(value);
            return value;
          },
          set(value) {
            if (descriptor?.set) {
              descriptor.set.call(window, value);
            } else {
              storedUni = value;
            }
            patchUniRequest(value);
          },
        });
      }
    } else {
      patchUniRequest(currentUni);
    }
  } catch (_) {}

  let uniPatchAttempts = 0;
  const uniPatchTimer = setInterval(() => {
    uniPatchAttempts += 1;
    if (installUniRequestPatch() || uniPatchAttempts >= 6000) {
      clearInterval(uniPatchTimer);
    }
  }, 10);

  // ============================================================
  // XMLHttpRequest
  // ============================================================

  const NativeXHR = window.XMLHttpRequest;
  if (typeof NativeXHR === 'function') {
    const xhrMeta = new WeakMap();
    const nativeOpen = NativeXHR.prototype.open;
    const nativeSend = NativeXHR.prototype.send;
    const nativeAbort = NativeXHR.prototype.abort;
    const timeoutDescriptor = Object.getOwnPropertyDescriptor(
      NativeXHR.prototype,
      'timeout'
    );

    function forceNoTimeout(xhr) {
      const meta = xhrMeta.get(xhr);
      if (!meta?.protected) return;

      try {
        if (timeoutDescriptor?.set) {
          timeoutDescriptor.set.call(xhr, 0);
        } else {
          // Compatibility fallback for implementations without a prototype
          // descriptor. Modern Android System WebView uses the setter above.
          xhr.timeout = 0;
        }
      } catch (_) {
        warn('xhr-timeout-force-failed');
      }
    }

    NativeXHR.prototype.open = function(method, url) {
      const resolved = targetHttpUrl(url);
      const meta = {
        method: String(method || 'GET').toUpperCase(),
        url: resolved?.href ?? String(url),
        protected: !!resolved,
      };
      xhrMeta.set(this, meta);

      const result = nativeOpen.apply(this, arguments);
      if (meta.protected) {
        forceNoTimeout(this);
        log('xhr-protected', meta.method);
      }
      return result;
    };

    if (timeoutDescriptor?.get && timeoutDescriptor?.set) {
      try {
        Object.defineProperty(NativeXHR.prototype, 'timeout', {
          configurable: timeoutDescriptor.configurable,
          enumerable: timeoutDescriptor.enumerable,
          get: function() {
            return timeoutDescriptor.get.call(this);
          },
          set: function(value) {
            const meta = xhrMeta.get(this);
            if (meta?.protected) {
              if (Number(value) !== 0) warn('xhr-timeout-blocked');
              return timeoutDescriptor.set.call(this, 0);
            }
            return timeoutDescriptor.set.call(this, value);
          },
        });
      } catch (_) {
        // open()/send() still force timeout=0 when descriptor replacement is
        // unavailable on an older WebView implementation.
      }
    }

    NativeXHR.prototype.send = function() {
      const meta = xhrMeta.get(this);
      if (meta?.protected) forceNoTimeout(this);
      return nativeSend.apply(this, arguments);
    };

    NativeXHR.prototype.abort = function() {
      const meta = xhrMeta.get(this);
      if (meta?.protected) {
        // Strict keep-alive mode intentionally cannot distinguish a framework
        // timeout abort from a business-request abort. Do not replay the call.
        warn('xhr-abort-blocked');
        return;
      }
      return nativeAbort.apply(this, arguments);
    };
  }

  // ============================================================
  // fetch
  // ============================================================

  const NativeRequest = window.Request;
  if (typeof window.fetch === 'function' &&
      typeof window.AbortController === 'function') {
    const nativeFetch = window.fetch.bind(window);

    window.fetch = function(input, init) {
      let isRequest = false;
      try {
        isRequest = typeof NativeRequest === 'function' &&
            input instanceof NativeRequest;
      } catch (_) {}

      const rawUrl = isRequest ? input.url : input;
      if (!targetHttpUrl(rawUrl)) {
        return nativeFetch(input, init);
      }

      // The controller is intentionally not exposed to page code. Its signal
      // cannot be aborted by the caller that supplied the original signal.
      const immortalSignal = new window.AbortController().signal;

      try {
        if (isRequest) {
          const protectedRequest = new NativeRequest(input, {
            ...(init || {}),
            signal: immortalSignal,
          });
          log('fetch-protected', protectedRequest.method);
          return nativeFetch(protectedRequest);
        }

        const protectedInit = {
          ...(init || {}),
          signal: immortalSignal,
        };
        log(
          'fetch-protected',
          String(protectedInit.method || 'GET').toUpperCase(),
        );
        return nativeFetch(input, protectedInit);
      } catch (_) {
        // Request construction may fail for an already-consumed body. No
        // native request was sent yet, so this fallback does not retry.
        warn('fetch-protection-fallback');
        return nativeFetch(input, init);
      }
    };
  }

  log('installed');
})();
''';

  static UserScript get userScript => UserScript(
    groupName: groupName,
    source: source,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    contentWorld: ContentWorld.PAGE,
    forMainFrameOnly: false,
  );
}
