// ==UserScript==
// @name         CHUSYXKhelper
// @namespace    CHUSYXKhelper
// @version      2.1.0
// @author       Rinn
// @description  实验选课：解除同步 XHR 造成的整页卡死；列表缓存与等待提示
// @match        http://chdsyxk.chd.edu.cn/*
// @match        https://chdsyxk.chd.edu.cn/*
// @include      http://chdsyxk.chd.edu.cn:8088/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(() => {
  'use strict';

  const KEY = '__CHUSYXKHELPER__';
  if (window[KEY]) return;

  const CONFIG = Object.assign({
    forceAsync: true,

    keepSync: ['Handshake', 'GetUIToken', 'IoControl'],

    // 移动端反过来：默认保持同步，只有确认"结果只在 success 里使用"的才转异步。
    // 移动端页面普遍存在 $.ajax 之后同步读回调变量的写法，按名字黑名单兜不住。
    asyncSafeMobile: [
      'getPdXmSl', 'getBgTjXs', 'getBgSc',   // 结果只用于跳转 / 分支
      'addDownjl',                          // success 里只做 UI 动作
    ],

    asyncSafePostFunctions: ['GetUserNewMessage'],

    disableMessagePoll: true,

    waitNoticeAfterMs: 1000,

    listPageSize: 200,

    suppressBrokenWeekList: true,

    cacheLists: true,
    cacheTtlMs: 10 * 60 * 1000,

    greeting: 'CHDSYXKhelper霓裳实验选课助手 by Rinn 已加载',

    // 视频播放页右下角提供「一键完成」：按视频总时长补报一次进度。
    oneClickVideoComplete: true,

    // 资料列表页右下角提供「一键完成」：按项目逐个补报资料查看记录。
    oneClickMaterialComplete: true,

    // 答题提交去重：同一次提交还在路上时，忽略重复点击。
    dedupeAnswerSubmit: true,

    // 允许修改已答题目的答案：给已答的选项补上点击处理，重新提交一次 tjks。
    allowAnswerChange: true,

    // 关闭"选工位"弹窗后不刷新课表：站点在 end 回调里调 AddSYKB(1) 重拉整个列表，
    // 而 Getxkkbbyxmid 是同步请求，一拉就把页面冻住。
    keepListAfterChooseGW: true,

    verbose: true,
  }, window.__CHUSYXKHELPER_CONFIG__ || {});

  const CACHE_PREFIX = '__CHUSYXKHELPER_RESP__:';
  const STACK_ID = 'chusyxk-toasts';
  const MAX_TOASTS = 4;

  const api = (window[KEY] = {
    version: '2.1.0',
    config: CONFIG,
    coerced: 0,
    pageSizeExpanded: 0,
    suppressed: 0,
    submitDeduped: 0,
    cacheHits: 0,
    cacheWrites: 0,
    reportedAjax: false,
    reportedPost: false,
    pending: new Set(),
    install,
    clearResponseCache,
    formatElapsed,
  });

  const log = (...args) => CONFIG.verbose && console.info('[CHUSYXKhelper]', ...args);

  // ---------------------------------------------------------------- 提示气泡
  const NOTICE_SKIP = /\/IoControl\b|\/Handshake\b/i;
  const MIN_WAIT_TOAST_MS = 800;
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
    } catch (_) { /* 跨域 */ }
    return document;
  }

  function ensureStack() {
    if (stack) return stack;
    const doc = hostDocument();
    if (!doc || !doc.body) return null;
    const existing = doc.getElementById(STACK_ID);
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
    const dup = [...host.children].find(el => el.children[0] && el.children[0].textContent === text);
    if (dup) return null;
    const handle = createToast(text, action, onClose);
    owned.add(handle);
    host.appendChild(handle.el);
    const items = [...host.children];
    while (items.length > MAX_TOASTS) removeEl({ el: items.shift() });
    return handle;
  }

  function paint() {
    const now = Date.now();
    const slow = [...api.pending].filter(item => now - item.started >= CONFIG.waitNoticeAfterMs);

    if (!slow.length) {
      waitDismissed = false;
      if (!waitToast) return;
      const remain = MIN_WAIT_TOAST_MS - (now - waitShownAt);
      if (remain > 0) {
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
    if (waitToast && !waitToast.el.parentNode) waitToast = null;
    const oldest = slow.reduce((a, b) => (a.started <= b.started ? a : b));
    const text = `正在等待服务端响应 ${formatElapsed(now - oldest.started)}（${oldest.label}）。`
      + '服务端较慢时可能要等数分钟，刷新会从头再等，请不要刷新。';
    if (waitToast) {
      waitToast.span.textContent = text;
      return;
    }
    waitToast = pushToast(text, null, () => {
      waitToast = null;
      waitDismissed = true;
    });
    if (waitToast) {
      waitToast.el.__chusyxkWait = true;
      waitShownAt = now;
    }
  }

  // ---------------------------------------------------------------- 启动提示
  function greetOnce() {
    if (!CONFIG.greeting) return;
    let topWin = window;
    try { topWin = window.top || window; } catch (_) { /* 跨域 */ }
    try {
      if (topWin.__CHUSYXKHELPER_GREETED__) return;
      topWin.__CHUSYXKHELPER_GREETED__ = true;
    } catch (_) { /* 跨域无法标记 */ }

    const show = () => pushToast(CONFIG.greeting);
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', show, { once: true });
    } else {
      show();
    }
  }

  // ---------------------------------------------------------- 一键完成（视频）
  // 播放器页把总时长写在全局 spsc 里（durationHandler 赋值），上报接口是全局 addspjl。
  // 这里按同样的请求体补报一次 time = 总时长，等价于把进度条拖到结尾。
  function isVideoPage() {
    try {
      return String(window.location.pathname || '').toLowerCase().endsWith('syyx_playvideo.html');
    } catch (_) {
      return false;
    }
  }

  function videoDuration() {
    const fromPlayer = Number(window.spsc);
    if (fromPlayer > 0) return fromPlayer;
    const el = document.querySelector && document.querySelector('video');
    if (el && isFinite(el.duration) && el.duration > 0) return el.duration;
    return 0;
  }

  function submitVideoComplete(total) {
    const $ = window.jQuery;
    if (!$ || typeof $.ajax !== 'function') return;
    const params = new URLSearchParams(window.location.search);
    const jxrwid = params.get('jxrwid');
    const xmid = params.get('xmid');
    if (!jxrwid || !xmid) return;

    const value = String(total);
    const busy = pushToast('正在上报视频进度…');
    $.ajax({
      url: '../../../wxInterface/update/AppInterface.asmx/addspjl',
      type: 'POST',
      dataType: 'json',
      contentType: 'application/json',
      cache: false,
      timeout: 30000,
      data: `{jxrwid:'${jxrwid}',xmid:'${xmid}',spzsc:'${value}',time:'${value}'}`,
      beforeSend(xhr) {
        xhr.setRequestHeader('Token', window.localStorage.getItem('Token') || '');
      },
    }).done(() => {
      removeEl(busy);
      pushToast(`已上报完成（视频）：${value} 秒`);
    }).fail(() => {
      removeEl(busy);
      pushToast('上报失败，请重试');
    });
  }

  function offerVideoComplete() {
    if (!CONFIG.oneClickVideoComplete || !isVideoPage()) return;
    let tries = 0;
    const timer = setInterval(() => {
      const total = videoDuration();
      if (total > 0) {
        clearInterval(timer);
        let handle = null;
        handle = pushToast('本任务可一键完成（视频）', {
          label: '一键完成',
          run: () => {
            removeEl(handle);
            submitVideoComplete(total);
          },
        });
        return;
      }
      if (++tries > 60) clearInterval(timer);   // 30 秒还没拿到时长就放弃
    }, 500);
  }

  // ------------------------------------------------------ 答题提交去重
  // tjks（逐题提交）和 PaperSubmit（交卷）都没有 timeout，服务端慢时要等几分钟；
  // 站点在此期间没有任何反馈（alertLoading 被注释掉），onclick 也只在成功后才清除，
  // 用户会反复点同一题，服务端于是收到一串相同请求并回"请勿重复提交"。
  // 这里在发出去之前拦掉重复的，第一个请求完成（无论成败）后自动解锁。
  const SUBMIT_MARKS = ['AppInterface.asmx/tjks', 'AppInterface.asmx/PaperSubmit'];
  const inflightSubmits = new Set();

  function isSubmitUrl(url) {
    const text = String(url || '');
    return SUBMIT_MARKS.some(mark => text.indexOf(mark) !== -1);
  }

  function submitKey(url, data) {
    const body = typeof data === 'string' ? data : JSON.stringify(data === undefined ? '' : data);
    return String(url) + '|' + body;
  }

  // ------------------------------------------------------ 修改已答题目
  // 站点在 flagIsTrue == 1（StuAnSwer 非空）时不给选项绑 onclick，答过的题就改不了了。
  // 这里把站点原本会生成的那句 onclick 补回去，点击后走站点自己的提交逻辑。
  function isExamPage() {
    try {
      return String(window.location.pathname || '').toLowerCase().endsWith('syyx_6.html');
    } catch (_) {
      return false;
    }
  }

  function scoreOf(tmtype) {
    const id = tmtype === 'A' ? 'AScore' : tmtype === 'C' ? 'CScore' : 'BScore';
    const el = document.getElementById(id);
    return el ? String(el.innerHTML || '').trim() : '';
  }

  function bindAnswerChange() {
    if (!CONFIG.allowAnswerChange || !isExamPage()) return;
    const layouts = document.querySelectorAll('.daan_layout');
    if (!layouts || !layouts.length) return;
    [...layouts].forEach(layout => {
      if (layout.onclick) return;                      // 未答的题站点自己绑了，别抢
      const box = layout.parentElement;
      if (!box || !box.id) return;
      const parts = String(box.id).split('_');
      if (parts.length !== 3) return;
      const ksid = parts[0];
      const tmid = parts[1];
      const tmtype = parts[2];
      if (tmtype !== 'A' && tmtype !== 'C') return;    // 多选要走"勾选 + 提交按钮"，另算
      if (!box.querySelector('span.tjdx')) return;     // 只接管已答的题
      const span = layout.querySelector('span[id]');
      if (!span) return;
      const letter = String(span.id).split('-').pop();
      layout.setAttribute('onclick',
        `tjks('${ksid}','${tmid}','${tmtype}','${letter}','${scoreOf(tmtype)}')`);
      layout.style.cursor = 'pointer';
    });
  }

  // ---------------------------------------------------------- 一键完成（资料）
  // addDownjl 的请求体是 {jxrwid, ID}，其中 ID 取的是列表行的 XMID（整个项目），
  // 不是资料行自己的 ID —— 所以一页资料通常只需要一次上报。
  const MATERIAL_MARK = 'GetSYXMKeJian';
  let materialIds = null;
  let materialOffered = false;

  function captureMaterialRows(data) {
    try {
      const outer = typeof data === 'string' ? JSON.parse(data) : data;
      const inner = JSON.parse(outer.d);
      const ids = [...new Set((inner.data || []).map(r => r.XMID)
        .filter(v => v !== undefined && v !== null))];
      if (!ids.length) return;
      materialIds = ids;
      offerMaterialComplete();
    } catch (_) { /* 结构不符就跳过 */ }
  }

  function offerMaterialComplete() {
    if (!CONFIG.oneClickMaterialComplete || materialOffered) return;
    if (!materialIds || !materialIds.length) return;
    materialOffered = true;
    let handle = null;
    handle = pushToast('本任务可一键完成（资料）', {
      label: '一键完成',
      run: () => {
        removeEl(handle);
        submitMaterialComplete(materialIds.slice());
      },
    });
  }

  function submitMaterialComplete(ids) {
    const $ = window.jQuery;
    if (!$ || typeof $.ajax !== 'function') return;
    const params = new URLSearchParams(window.location.search);
    const jxrwid = params.get('jxrwid');
    if (!jxrwid) return;

    const progress = pushToast(`正在上报资料进度 0/${ids.length}…`);
    let index = 0;
    let ok = 0;
    let failed = 0;

    const step = () => {
      if (index >= ids.length) {
        removeEl(progress);
        pushToast(failed
          ? `资料上报完成：成功 ${ok} 项，失败 ${failed} 项`
          : `已上报完成（资料）：${ok} 项`);
        return;
      }
      const id = ids[index++];
      if (progress) progress.span.textContent = `正在上报资料进度 ${index}/${ids.length}…`;
      $.ajax({
        url: '../../../wxInterface/update/AppInterface.asmx/addDownjl',
        type: 'POST',
        dataType: 'json',
        contentType: 'application/json',
        cache: false,
        timeout: 30000,
        data: `{jxrwid:'${jxrwid}',ID:'${id}'}`,
        beforeSend(xhr) {
          xhr.setRequestHeader('Token', window.localStorage.getItem('Token') || '');
        },
      }).done(() => { ok += 1; step(); })
        .fail(() => { failed += 1; step(); });
    };
    step();
  }

  // 同步请求不登记：jQuery 在 $.ajax 返回前就已 resolve，always 会立刻执行把条目删掉，
  // 1 秒阈值永远走不到；何况同步 XHR 期间定时器也不会跑。登记了也显示不出来。
  function track(jqXHR, url, sync) {
    if (sync) return;
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
        paint();
      } else {
        paint();
      }
    });
  }

  // --------------------------------------------------------- 响应缓存
  const CACHEABLE = /\/getItemTime\b|\/getRuleItem\b|\/GetSyyxRwlistXK\b|\/GetSyyxRwXMlistXK\b|\/Getxkkbbyxmid\b/i;

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
    } catch (_) { /* 配额满或隐私模式 */ }
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

  // 移动端请求用的是相对路径（../../../wxInterface/...），URL 里看不出 /apk/，
  // 所以按页面地址判断。
  const MOBILE_PAGE = (() => {
    try {
      if (String(window.location.port) === '8088') return true;
      return /\/apk\//i.test(String(window.location.pathname || ''));
    } catch (_) {
      return false;
    }
  })();

  // 移动端里同步消费回调的写法很普遍，未验证过的端点一律保持同步。
  function canCoerce(url) {
    const text = String(url || '');
    if (mustStaySync(text)) return false;
    if (!MOBILE_PAGE && !/\/apk\//i.test(text)) return true;
    return CONFIG.asyncSafeMobile.some(name => text.indexOf(name) !== -1);
  }

  const LIST_PAGE_SIZE_TARGET = /\/getItemTime\b/i;
  const LIST_PAGESIZE_TARGET = /\/Getxkkbbyxmid\b/i;
  const LIMIT_KEY = /([,{]\s*['"]?limit['"]?\s*:\s*['"]?)(\d+)/i;
  const PAGESIZE_KEY = /([,{]\s*['"]?PageSize['"]?\s*:\s*['"]?)(\d+)/i;

  const BROKEN_WEEK_LIST = /\/syjx\.asmx\/miniYEARDATELIST\b/i;

  function expandLimit(body, target, pattern) {
    if (typeof body !== 'string') return body;
    return body.replace(pattern, (match, prefix, digits) =>
      (Number(digits) < target ? prefix + target : match));
  }

  function wrapAjax($) {
    if ($.ajax.__chusyxk) return true;

    const native = $.ajax;
    const wrapped = function (first, second) {
      // jQuery 有 $.ajax(options) 与 $.ajax(url, options) 两种签名
      const settings = typeof first === 'string' ? second : first;
      const url = (settings && settings.url) || (typeof first === 'string' ? first : '');

      let submitKeyValue = null;
      if (CONFIG.dedupeAnswerSubmit && isSubmitUrl(url)) {
        submitKeyValue = submitKey(url, settings && settings.data);
        if (inflightSubmits.has(submitKeyValue)) {
          api.submitDeduped += 1;
          if (api.submitDeduped === 1) log('这次提交还在进行中，已忽略重复点击');
          return noopXHR();
        }
        inflightSubmits.add(submitKeyValue);
      }

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
          canCoerce(url)) {
        settings.async = true;              // 原地改，避免复制丢回调
        api.coerced += 1;
        if (api.coerced === 1) log('已把同步请求改为异步：页面不再因接口慢而整页卡死');
      }

      const sizePattern = LIST_PAGE_SIZE_TARGET.test(String(url)) ? LIMIT_KEY
        : LIST_PAGESIZE_TARGET.test(String(url)) ? PAGESIZE_KEY : null;
      if (CONFIG.listPageSize > 0 &&
          settings && typeof settings === 'object' &&
          sizePattern) {
        const expanded = expandLimit(settings.data, CONFIG.listPageSize, sizePattern);
        if (expanded !== settings.data) {
          settings.data = expanded;
          api.pageSizeExpanded += 1;
        }
      }

      // 缓存键用放宽分页后的最终请求体，保证回放与网络请求同键
      const cacheable = CONFIG.cacheLists && CACHEABLE.test(String(url));
      const key = cacheable ? cacheKey(settings && settings.method, url, settings && settings.data) : null;

      if (cacheable) {
        const hit = readResponseCache(key);
        if (hit) {
          api.cacheHits += 1;
          const replayed = noopXHR();
          let payload;
          try {
            payload = JSON.parse(hit.text);
          } catch (_) {
            payload = null;
          }
          if (payload !== null) {
            const replay = () => {
              try {
                if (typeof settings.success === 'function') settings.success(payload, 'success', replayed);
                if (typeof settings.complete === 'function') settings.complete(replayed, 'success');
              } catch (error) {
                console.warn('[CHUSYXKhelper] 回放缓存数据时出错：', error);
              }
            };
            // 被同步消费的端点必须同步回放，否则调用方在回调之外读到的还是旧值
            if (canCoerce(url)) setTimeout(replay, 0);
            else replay();
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
      track(jqXHR, url, !!(settings && typeof settings === 'object' && settings.async === false));
      if (submitKeyValue && jqXHR && typeof jqXHR.always === 'function') {
        jqXHR.always(() => inflightSubmits.delete(submitKeyValue));
      }

      if (cacheable && jqXHR && typeof jqXHR.done === 'function') {
        jqXHR.done(data => {
          try {
            writeResponseCache(key, JSON.stringify(data));
          } catch (_) { /* 循环引用等，放弃缓存 */ }
        });
      }

      if (/\/Addksxmtu\b/i.test(String(url)) && jqXHR && typeof jqXHR.done === 'function') {
        jqXHR.done(() => {
          const removed = clearResponseCache();
          if (removed) log(`选课成功，已清除 ${removed} 条列表缓存`);
        });
      }

      if (String(url).indexOf('GetPaperExamLabNew') !== -1 && jqXHR && typeof jqXHR.done === 'function') {
        jqXHR.done(() => setTimeout(bindAnswerChange, 0));
      }

      if (String(url).indexOf(MATERIAL_MARK) !== -1 && jqXHR && typeof jqXHR.done === 'function') {
        jqXHR.done(data => captureMaterialRows(data));
      }

      return jqXHR;
    };
    wrapped.__chusyxk = true;
    $.ajax = wrapped;
    return true;
  }

  // -------------------------------------------------- 选工位弹窗关窗不刷新
  const GW_POPUP_MARK = 'chooseGW.html';

  function layerContentUrl(options) {
    const content = options && options.content;
    const first = Array.isArray(content) ? content[0] : content;
    return typeof first === 'string' ? first : '';
  }

  function installLayer() {
    const layer = window.layer;
    if (!layer || typeof layer.open !== 'function') return false;
    if (layer.open.__chusyxk) return true;

    const native = layer.open;
    const wrapped = function (first) {
      let arg = first;
      if (CONFIG.keepListAfterChooseGW &&
          arg && typeof arg === 'object' &&
          typeof arg.end === 'function' &&
          layerContentUrl(arg).indexOf(GW_POPUP_MARK) !== -1) {
        arg = Object.assign({}, arg);
        delete arg.end;
        log('关闭选工位弹窗，跳过课表刷新');
      }
      return arguments.length === 1 ? native.call(this, arg) : native.apply(this, arguments);
    };
    wrapped.__chusyxk = true;
    layer.open = wrapped;
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
        options.async = true;               // $Post 据此把 async 传给内部 $.ajax
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

  // jQuery 可能晚于 document-start 加载，短轮询接管；拿到 $.ajax 即停。
  let attempts = 0;
  const watcher = setInterval(() => {
    install();
    installLayer();
    if (api.reportedAjax || ++attempts > 1500) clearInterval(watcher);
  }, 20);
  // 收尾上一个 frame 残留的等待气泡
  try {
    const topDoc = window.top && window.top.document;
    const oldStack = topDoc && topDoc.getElementById(STACK_ID);
    if (oldStack) {
      [...oldStack.children].filter(el => el.__chusyxkWait).forEach(el => {
        if (el.parentNode) el.parentNode.removeChild(el);
      });
    }
  } catch (_) { /* 跨域或顶层还没有 body */ }

  install();
  installLayer();
  greetOnce();
  offerVideoComplete();

  window.addEventListener('pagehide', dropAllToasts);
  window.addEventListener('beforeunload', dropAllToasts);

  // 站点重载 jQuery 后需重新接管
  document.addEventListener('load', event => {
    if (event.target && event.target.tagName === 'SCRIPT') {
      install();
      installLayer();
    }
  }, true);
  document.addEventListener('DOMContentLoaded', () => {
    install();
    installLayer();
  }, { once: true });
})();
