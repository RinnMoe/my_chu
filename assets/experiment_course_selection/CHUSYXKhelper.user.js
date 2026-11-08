// ==UserScript==
// @name         CHUSYXKhelper
// @namespace    CHUSYXKhelper
// @version      2.0.0
// @author       Rinn
// @description  实验选课：解除同步 XHR 造成的整页卡死；列表缓存与等待提示
// @match        http://chdsyxk.chd.edu.cn/*
// @match        https://chdsyxk.chd.edu.cn/*
// @include      http://chdsyxk.chd.edu.cn:8088/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

/*
 * 站点用 async:false 发请求（同步 XHR）。服务端一慢，渲染主线程就被锁死，
 * 连 timeout 都不生效，整页跟着假死。本脚本在 document-start 接管 jQuery.ajax
 * 与 $Post，把确认安全的同步请求改成异步；另外少等几轮、少发几个没用的请求、
 * 把列表结果缓存起来。
 */

(() => {
  'use strict';

  const KEY = '__CHUSYXKHELPER__';
  if (window[KEY]) return;

  const CONFIG = Object.assign({
    // 核心开关：把白名单内的同步请求改成异步。
    forceAsync: true,

    // 必须保持同步的请求（按 URL 子串匹配）。
    //   Handshake   —— 返回加密密钥，$Post 拿到后立刻用它加密请求体，异步会拿空密钥。
    //   GetUIToken  —— 返回的 token 会被写进 $.ajaxSetup 的默认请求头，后续请求依赖它。
    //   IoControl   —— $Post 的加密隧道，具体功能在 $.ajax 层已无法区分，交给下面按功能名放行。
    //   移动端三个列表查询 —— 站点代码在 $.ajax 之后直接同步读回调里赋的值：
    //       $.ajax({async:false, success: function(json){ lis.push(h); count = json.length; }});
    //       next(lis.join(''), page < count);        // ← 转异步会拿到空列表、分页判断失效
    //     所以它们必须保持同步，否则列表会渲染成空白。
    //   移动端选课提交 / 取消选课 —— 没有同步依赖，但同步 XHR 冻住界面正好挡住连点重复提交。
    keepSync: [
      'Handshake', 'GetUIToken', 'IoControl',
      'GetSyyxRwlistXK', 'GetSyyxRwXMlistXK', 'Getxkkbbyxmid',
      'AppInterface.asmx/Addksxmtu', 'N_QXXK',
    ],

    // 允许转异步的 $Post 功能名（$Post 的 options.f）。
    // 只收"结果只在 success 回调里使用"的功能；有同步 return 依赖的一律不加。
    asyncSafePostFunctions: ['GetUserNewMessage'],

    // 停掉每 60 秒一次的 newmsg() 消息轮询（$Post 的 IoControl 心跳）。
    // 它只是个"有没有新消息"的空查询，却要长期占用一个服务端工作线程。
    // 代价是收不到站内新消息红点和 layim 推送。
    disableMessagePoll: true,

    // 单个请求超过这个时长就显示等待提示，避免用户误以为卡住而刷新。
    // 设成 1 秒：多数请求都会短暂触发一次提示。
    waitNoticeAfterMs: 1000,

    // 只对 getItemTime 放宽分页大小。服务端每次都算完整个结果集再切片，
    // limit 小并不会更快，只会让你多等几轮。设为 0 可关闭。
    listPageSize: 200,

    // 拦掉 syjx.asmx/miniYEARDATELIST：该端点会抛异常，而页面没有 error 回调，
    // 失败完全静默。拦掉不改变任何现有行为，学校修好后设为 false 即可恢复。
    suppressBrokenWeekList: true,

    // 把 getItemTime / getRuleItem 的响应缓存到 sessionStorage，切页面回来直接回放。
    // 缓存里带着 RS/GW 这类实时名额，回放的是旧数据，所以只存 sessionStorage、
    // 有 TTL、选课成功后立刻清空、命中时右下角会提示是几分钟前的数据。
    cacheLists: true,
    cacheTtlMs: 10 * 60 * 1000,

    // 页面加载完成后在右下角弹一次署名提示；设为空字符串可关闭。
    greeting: 'CHDSYXKhelper霓裳实验选课助手 by Rinn 已加载',

    verbose: true,
  }, window.__CHUSYXKHELPER_CONFIG__ || {});

  const CACHE_PREFIX = '__CHUSYXKHELPER_RESP__:';
  const STACK_ID = 'chusyxk-toasts';
  const MAX_TOASTS = 4;

  const api = (window[KEY] = {
    version: '2.0.0',
    config: CONFIG,
    coerced: 0,          // 被改成异步的请求数
    pageSizeExpanded: 0, // 被放宽分页的请求数
    suppressed: 0,       // 被跳过的无效请求数
    cacheHits: 0,          // 命中响应缓存的次数
    cacheWrites: 0,        // 写入响应缓存的次数
    reportedAjax: false,   // 是否已接管 $.ajax
    reportedPost: false,   // 是否已接管 $Post
    pending: new Set(),
    install,
    clearResponseCache,
    formatElapsed,
  });

  const log = (...args) => CONFIG.verbose && console.info('[CHUSYXKhelper]', ...args);

  // ---------------------------------------------------------------- 提示气泡
  // 站点在 global.js 里把内容 iframe 的高度设成内容高度（main.height($(obj).height()+50)），
  // 所以 iframe 内的 position:fixed 是相对那个很高的 iframe 盒子，而不是用户屏幕。
  // 提示统一挂到顶层文档，fixed 才真正相对视口；跨域时退回本页。
  //
  // 一条提示 = 一个元素，新的加在下面、旧的被顶上去，互不重叠；每条都有 × 手动关闭，
  // 不再自动消失。等待进度独占一条，原地更新文字，请求结束后自动撤掉。
  const NOTICE_SKIP = /\/IoControl\b|\/Handshake\b/i;   // 后台轮询不打扰用户
  const MIN_WAIT_TOAST_MS = 800;   // 等待气泡一旦出现至少停留这么久，避免一闪而过
  let stack = null;
  let ticker = null;
  let waitToast = null;
  let waitShownAt = 0;
  let waitHideTimer = null;
  let waitDismissed = false;

  function formatElapsed(ms) {
    const total = Math.floor(ms / 1000);
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
  }

  function hostDocument() {
    try {
      const topDoc = window.top && window.top.document;
      if (topDoc && topDoc.body) return topDoc;
    } catch (_) { /* 跨域：退回本页 */ }
    return document;
  }

  function ensureStack() {
    if (stack) return stack;
    const doc = hostDocument();
    if (!doc || !doc.body) return null;
    const existing = doc.getElementById(STACK_ID);   // iframe 重载后复用，避免两个容器
    if (existing) { stack = existing; return stack; }

    stack = doc.createElement('div');
    stack.id = STACK_ID;
    stack.style.cssText = [
      'position:fixed', 'right:16px', 'bottom:16px', 'z-index:2147483647',
      'display:flex', 'flex-direction:column', 'align-items:flex-end', 'gap:8px',
      'pointer-events:none',
    ].join(';');
    doc.body.appendChild(stack);
    return stack;
  }

  // 本实例创建的气泡。气泡挂在顶层文档上，会比创建它的 iframe 活得久；
  // frame 一卸载，它挂的那些 click 监听器就随 realm 一起失效——元素还在但点不动。
  // 所以卸载时主动把自己创建的气泡撤掉。
  const owned = new Set();

  function removeEl(handle) {
    if (!handle || !handle.el) return;
    const el = handle.el;
    owned.delete(handle);
    if (typeof el.remove === 'function') el.remove();
    else if (el.parentNode) el.parentNode.removeChild(el);
  }

  function dropAllToasts() {
    [...owned].forEach(removeEl);
    owned.clear();
  }

  function createToast(text, action, onClose) {
    const doc = hostDocument();
    const el = doc.createElement('div');
    el.style.cssText = [
      'max-width:320px', 'padding:8px 12px', 'border-radius:6px',
      'font:12px/1.5 system-ui,-apple-system,sans-serif',
      'color:#fff', 'background:rgba(28,28,30,.9)',
      'box-shadow:0 2px 8px rgba(0,0,0,.35)',
      'pointer-events:auto', 'display:flex', 'align-items:center', 'gap:8px',
    ].join(';');

    const span = doc.createElement('span');
    span.textContent = text;
    el.appendChild(span);

    const handle = { el, span };

    if (action) {
      const button = doc.createElement('button');
      button.type = 'button';
      button.textContent = action.label;
      button.style.cssText = 'flex:none;padding:2px 8px;border:0;border-radius:4px;'
        + 'background:#fff;color:#1c1c1e;font:inherit;cursor:pointer';
      button.addEventListener('click', event => {
        if (event && typeof event.preventDefault === 'function') event.preventDefault();
        action.run();
      });
      el.appendChild(button);
    }

    const close = doc.createElement('button');
    close.type = 'button';
    close.textContent = '×';
    close.setAttribute('aria-label', '关闭');
    close.style.cssText = 'flex:none;padding:2px 6px;margin:-2px -4px -2px 0;border:0;'
      + 'border-radius:4px;background:transparent;color:#fff;font:inherit;font-size:15px;'
      + 'line-height:1;cursor:pointer;opacity:.75';
    close.addEventListener('click', () => {
      removeEl(handle);
      if (onClose) onClose(handle);
    });
    el.appendChild(close);

    return handle;
  }

  function pushToast(text, action, onClose) {
    const host = ensureStack();
    if (!host) return null;
    // 同样的文字不重复堆叠：连续几次命中缓存不该出现一排一模一样的气泡
    const dup = [...host.children].find(el => el.children[0] && el.children[0].textContent === text);
    if (dup) return null;
    const handle = createToast(text, action, onClose);
    owned.add(handle);
    host.appendChild(handle.el);
    // 超出上限时丢掉最旧的一条，避免一直点「刷新」把屏幕铺满
    const items = [...host.children];
    while (items.length > MAX_TOASTS) removeEl({ el: items.shift() });
    return handle;
  }

  function paint() {
    const now = Date.now();
    const slow = [...api.pending].filter(item => now - item.started >= CONFIG.waitNoticeAfterMs);

    if (!slow.length) {
      waitDismissed = false;              // 这一轮等完了，下一轮重新提示
      if (!waitToast) return;
      const remain = MIN_WAIT_TOAST_MS - (now - waitShownAt);
      if (remain > 0) {                   // 还没到最短停留时间，到点再撤
        if (!waitHideTimer) {
          const shown = waitToast;
          waitHideTimer = setTimeout(() => {
            waitHideTimer = null;
            if (waitToast !== shown) return;
            if ([...api.pending].some(i => Date.now() - i.started >= CONFIG.waitNoticeAfterMs)) return;
            removeEl(shown);
            waitToast = null;
          }, remain);
        }
        return;
      }
      if (waitHideTimer) { clearTimeout(waitHideTimer); waitHideTimer = null; }
      removeEl(waitToast);
      waitToast = null;
      return;
    }

    if (waitDismissed) return;
    if (waitToast && !waitToast.el.parentNode) waitToast = null;   // 被上限挤掉了
    const oldest = slow.reduce((a, b) => (a.started <= b.started ? a : b));
    const text = `正在等待服务端响应 ${formatElapsed(now - oldest.started)}（${oldest.label}）。`
      + '服务端较慢时可能要等数分钟，刷新会从头再等，请不要刷新。';
    if (waitToast) {
      waitToast.span.textContent = text;   // 原地更新，不重建节点
      return;
    }
    waitToast = pushToast(text, null, () => {
      waitToast = null;
      waitDismissed = true;               // 用户主动关了，本轮不再打扰
    });
    if (waitToast) {
      waitToast.el.__chusyxkWait = true;
      waitShownAt = now;
    }
  }

  // ---------------------------------------------------------------- 启动提示
  // 同一次页面加载只提示一次：标记记在顶层 window 上，iframe 里的实例会跳过，
  // 刷新后顶层 window 换新，标记自然失效。
  function greetOnce() {
    if (!CONFIG.greeting) return;
    let topWin = window;
    try { topWin = window.top || window; } catch (_) { /* 跨域，用本页 */ }
    try {
      if (topWin.__CHUSYXKHELPER_GREETED__) return;
      topWin.__CHUSYXKHELPER_GREETED__ = true;
    } catch (_) { /* 跨域无法标记，退化为每个框架都提示 */ }

    const show = () => pushToast(CONFIG.greeting);
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', show, { once: true });
    } else {
      show();
    }
  }

  function track(jqXHR, url) {
    if (!jqXHR || typeof jqXHR.always !== 'function') return;
    if (NOTICE_SKIP.test(String(url || ''))) return;
    const item = { label: labelOf(url), started: Date.now() };
    api.pending.add(item);
    if (!ticker) ticker = setInterval(paint, 1000);
    jqXHR.always(() => {
      api.pending.delete(item);
      if (!api.pending.size && ticker) {
        clearInterval(ticker);
        ticker = null;
        paint();                       // 走一遍"无等待"分支，撤掉进度条
      } else {
        paint();
      }
    });
  }

  // --------------------------------------------------------- 响应缓存
  // 存 JSON.stringify 后的响应对象，回放时 JSON.parse 回同样的值交给 layui 的 success，
  // 与真实请求走同一条代码路径（layui 内部就是 JSON.parse(res.d)）。
  const CACHEABLE = /\/getItemTime\b|\/getRuleItem\b/i;

  function cacheKey(method, url, data) {
    const body = typeof data === 'string' ? data : JSON.stringify(data === undefined ? '' : data);
    return `${String(method || 'GET').toUpperCase()} ${url} ${body}`;
  }

  function readResponseCache(key) {
    try {
      const raw = window.sessionStorage.getItem(CACHE_PREFIX + key);
      if (!raw) return null;
      const entry = JSON.parse(raw);
      if (!entry || typeof entry.text !== 'string') return null;
      const age = Date.now() - entry.at;
      if (!(age >= 0) || age > CONFIG.cacheTtlMs) return null;
      return { text: entry.text, age };
    } catch (_) {
      return null;
    }
  }

  function writeResponseCache(key, text) {
    try {
      window.sessionStorage.setItem(CACHE_PREFIX + key, JSON.stringify({ at: Date.now(), text }));
      api.cacheWrites += 1;
    } catch (_) { /* 配额满或隐私模式，忽略即可 */ }
  }

  function clearResponseCache() {
    try {
      const doomed = [];
      for (let i = 0; i < window.sessionStorage.length; i += 1) {
        const k = window.sessionStorage.key(i);
        if (k && k.indexOf(CACHE_PREFIX) === 0) doomed.push(k);
      }
      doomed.forEach(k => window.sessionStorage.removeItem(k));
      return doomed.length;
    } catch (_) {
      return 0;
    }
  }

  // 一个什么都不做的 jqXHR 替身：调用方链式挂 .done/.fail/.always 时不会报错。
  // 用于"请求被拦下"和"从缓存回放"两条不真正发请求的路径。
  function noopXHR() {
    const jqXHR = {};
    jqXHR.done = () => jqXHR;
    jqXHR.fail = () => jqXHR;
    jqXHR.always = () => jqXHR;
    jqXHR.then = () => jqXHR;
    return jqXHR;
  }

  // ------------------------------------------------------------- 同步转异步
  function labelOf(url) {
    const text = String(url || '');
    const tail = text.split('?')[0].split('/').filter(Boolean).pop();
    return tail || '请求';
  }

  function mustStaySync(url) {
    const text = String(url || '');
    return CONFIG.keepSync.some(name => text.indexOf(name) !== -1);
  }

  const LIST_PAGE_SIZE_TARGET = /\/getItemTime\b/i;

  const BROKEN_WEEK_LIST = /\/syjx\.asmx\/miniYEARDATELIST\b/i;

  function expandLimit(body, target) {
    if (typeof body !== 'string') return body;
    return body.replace(/(\blimit['"]?\s*:\s*['"]?)(\d+)/, (match, prefix, digits) => {
      const current = Number(digits);
      return current < target ? prefix + target : match;
    });
  }

  function wrapAjax($) {
    if ($.ajax.__chusyxk) return true;

    const native = $.ajax;
    const wrapped = function (first, second) {
      // jQuery 支持 $.ajax(options) 和 $.ajax(url, options) 两种签名
      const settings = typeof first === 'string' ? second : first;
      const url = (settings && settings.url) || (typeof first === 'string' ? first : '');

      if (CONFIG.suppressBrokenWeekList && BROKEN_WEEK_LIST.test(String(url))) {
        api.suppressed += 1;
        if (api.suppressed === 1) {
          log('已跳过 miniYEARDATELIST：该端点每次都在服务端抛异常，且页面没有 error 回调');
        }
        return noopXHR();
      }

      if (CONFIG.forceAsync &&
          settings && typeof settings === 'object' &&
          settings.async === false &&
          !mustStaySync(url)) {
        settings.async = true;              // 原地改，避免复制丢回调
        api.coerced += 1;
        if (api.coerced === 1) log('已把同步请求改为异步：页面不再因接口慢而整页卡死');
      }

      if (CONFIG.listPageSize > 0 &&
          settings && typeof settings === 'object' &&
          LIST_PAGE_SIZE_TARGET.test(String(url))) {
        const expanded = expandLimit(settings.data, CONFIG.listPageSize);
        if (expanded !== settings.data) {
          settings.data = expanded;
          api.pageSizeExpanded += 1;
        }
      }

      // 缓存键用"最终"的请求体，这样放宽分页后的请求和回放用的是同一个键。
      const cacheable = CONFIG.cacheLists && CACHEABLE.test(String(url));
      const key = cacheable ? cacheKey(settings && settings.method, url, settings && settings.data) : null;

      if (cacheable) {
        const hit = readResponseCache(key);
        if (hit) {
          api.cacheHits += 1;
          const replayed = noopXHR();
          let payload;
          try {
            payload = JSON.parse(hit.text);       // 与 jQuery 对 dataType:'json' 的解析一致
          } catch (_) {
            payload = null;
          }
          if (payload !== null) {
            // 异步回调，保持与真实 ajax 相同的时序（layui 会先显示 loading 再渲染）
            setTimeout(() => {
              try {
                if (typeof settings.success === 'function') settings.success(payload, 'success', replayed);
                if (typeof settings.complete === 'function') settings.complete(replayed, 'success');
              } catch (error) {
                console.warn('[CHUSYXKhelper] 回放缓存数据时出错：', error);
              }
            }, 0);
            const ageMin = Math.max(1, Math.round(hit.age / 60000));
            log(`${labelOf(url)} 命中缓存（${ageMin} 分钟前），不再请求服务端`);
            pushToast(`本次列表来自 ${ageMin} 分钟前的缓存，选课状态与名额可能已变化。`
              + '如需最新数据请点「刷新」。', {
                label: '刷新',
                run: () => {
                  const removed = clearResponseCache();
                  log(`已清除 ${removed} 条缓存，正在刷新页面重新查询…`);
                  window.location.reload();
                },
              });
            return replayed;
          }
        }
      }

      const jqXHR = native.apply(this, arguments);
      track(jqXHR, url);

      if (cacheable && jqXHR && typeof jqXHR.done === 'function') {
        jqXHR.done(data => {
          try {
            writeResponseCache(key, JSON.stringify(data));
          } catch (_) { /* 循环引用等极端情况，放弃缓存即可 */ }
        });
      }

      // 选课成功后立刻让缓存失效，否则刚抢到的名额会显示成旧数字。
      if (/\/Addksxmtu\b/i.test(String(url)) && jqXHR && typeof jqXHR.done === 'function') {
        jqXHR.done(() => {
          const removed = clearResponseCache();
          if (removed) log(`选课成功，已清除 ${removed} 条列表缓存`);
        });
      }

      return jqXHR;
    };
    wrapped.__chusyxk = true;
    $.ajax = wrapped;
    return true;
  }

  function wrapPost($) {
    const native = $.$Post;
    if (typeof native !== 'function') return false;
    if (native.__chusyxk) return true;

    const wrapped = function (options) {
      if (CONFIG.forceAsync &&
          options && typeof options === 'object' &&
          options.async === false &&
          CONFIG.asyncSafePostFunctions.indexOf(options.f) !== -1) {
        options.async = true;               // $Post 会据此把 async 传给内部的 $.ajax
        api.coerced += 1;
      }
      return native.apply(this, arguments);
    };
    wrapped.__chusyxk = true;
    $.$Post = wrapped;
    return true;
  }

  function install() {
    const $ = window.jQuery;
    if (!$ || typeof $.ajax !== 'function') return false;
    const ajaxReady = wrapAjax($);
    const postReady = wrapPost($);
    // 移动端前端（:8088）只用 $.ajax，没有 $Post，所以两者分开报告
    if (ajaxReady && !api.reportedAjax) {
      api.reportedAjax = true;
      log('已接管 jQuery.ajax');
    }
    if (postReady && !api.reportedPost) {
      api.reportedPost = true;
      log('已接管 $Post');
    }
    return ajaxReady && postReady;
  }

  // ------------------------------------------------------ 可选的轮询停用
  if (CONFIG.disableMessagePoll && typeof window.setInterval === 'function') {
    const nativeSetInterval = window.setInterval;
    window.setInterval = function (handler) {
      if (typeof handler === 'string' && handler.replace(/\s+/g, '') === 'newmsg()') {
        log('已停用 60 秒消息轮询');
        return 0;
      }
      return nativeSetInterval.apply(this, arguments);
    };
  }

  // jQuery 在 document-start 时通常还没加载，用短轮询接管，30 秒后放弃。
  // 接管到 $.ajax 就停：$Post 若稍后才定义，由下面的 SCRIPT load 监听补上。
  let attempts = 0;
  const watcher = setInterval(() => {
    install();
    if (api.reportedAjax || ++attempts > 1500) clearInterval(watcher);
  }, 20);
  // 上一个 iframe 被销毁时，它的等待进度条来不及撤，这里收尾。
  try {
    const topDoc = window.top && window.top.document;
    const oldStack = topDoc && topDoc.getElementById(STACK_ID);
    if (oldStack) {
      [...oldStack.children].filter(el => el.__chusyxkWait).forEach(el => {
        if (el.parentNode) el.parentNode.removeChild(el);
      });
    }
  } catch (_) { /* 跨域或顶层还没有 body，忽略 */ }

  install();
  greetOnce();

  // 本 frame 被销毁前，把它留在顶层文档里的气泡一起撤掉
  window.addEventListener('pagehide', dropAllToasts);
  window.addEventListener('beforeunload', dropAllToasts);

  // 站点若重新加载 jQuery，新实例需要重新接管。
  document.addEventListener('load', event => {
    if (event.target && event.target.tagName === 'SCRIPT') install();
  }, true);
  document.addEventListener('DOMContentLoaded', install, { once: true });
})();
