import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../capabilities/shuwei_request_proxy.dart';
import '../../services/academic_affairs_backend.dart';
import '../../services/campus_session.dart';
import '../../services/logger_service.dart';
import '../../services/service_endpoints.dart';
import '../academic_affairs/academic_affairs_models.dart';
import 'shuwei_schedule_parser.dart';

enum ShuweiScheduleImportAbortReason { background, cookieCommit }

/// Lifecycle and cleanup state for one short-lived WebView import attempt.
///
/// This type does not contain credentials or cookies. The testing hook uses it
/// to model the same cancellation boundary as the production WebView.
class ShuweiScheduleImportAttemptContext {
  ShuweiScheduleImportAttemptContext._();

  final Completer<ShuweiScheduleImportAbortReason> _abortCompleter =
      Completer<ShuweiScheduleImportAbortReason>.sync();
  ShuweiScheduleImportAbortReason? _abortReason;
  Future<void> Function()? _resourceDisposer;
  Future<void>? _disposeFuture;
  bool _disposeImmediatelyRequested = false;

  bool get isAborted => _abortReason != null;

  ShuweiScheduleImportAbortReason? get abortReason => _abortReason;

  Future<ShuweiScheduleImportAbortReason> get abortFuture =>
      _abortCompleter.future;

  void abort(
    ShuweiScheduleImportAbortReason reason, {
    bool disposeImmediately = false,
  }) {
    if (_abortReason == null) {
      _abortReason = reason;
      _abortCompleter.complete(reason);
    }
    if (disposeImmediately) {
      _disposeImmediatelyRequested = true;
      unawaited(disposeResources());
    }
  }

  void throwIfAborted() {
    final reason = _abortReason;
    if (reason != null) {
      throw _ShuweiScheduleImportAbortException(reason);
    }
  }

  void attachResourceDisposer(Future<void> Function() disposer) {
    if (_resourceDisposer != null) return;
    _resourceDisposer = disposer;
    if (_disposeImmediatelyRequested) unawaited(disposeResources());
  }

  Future<void> disposeResources() {
    final pending = _disposeFuture;
    if (pending != null) return pending;
    if (_resourceDisposer == null) return Future<void>.value();
    final future = _disposeResource();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeResource() async {
    final disposer = _resourceDisposer;
    if (disposer != null) await disposer();
  }
}

typedef ShuweiScheduleImportAttemptForTesting =
    Future<AcademicScheduleFetchResult> Function(
      String? semesterId,
      AcademicScheduleScope scope,
      ShuweiScheduleImportAttemptContext context,
    );

class _ShuweiScheduleImportLifecycle {
  static const resumeWaitTimeout = Duration(minutes: 2);

  final Set<ShuweiScheduleImportAttemptContext> _active = {};
  Completer<void>? _resumeCompleter;
  bool _backgrounded = false;

  bool get isBackgrounded => _backgrounded;

  ShuweiScheduleImportAttemptContext beginAttempt() {
    final context = ShuweiScheduleImportAttemptContext._();
    _active.add(context);
    if (_backgrounded) {
      context.abort(
        ShuweiScheduleImportAbortReason.background,
        disposeImmediately: true,
      );
    }
    return context;
  }

  void endAttempt(ShuweiScheduleImportAttemptContext context) {
    _active.remove(context);
  }

  void handle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_backgrounded) return;
        _backgrounded = true;
        _resumeCompleter ??= Completer<void>();
        for (final context in List<ShuweiScheduleImportAttemptContext>.of(
          _active,
        )) {
          context.abort(
            ShuweiScheduleImportAbortReason.background,
            disposeImmediately: true,
          );
        }
      case AppLifecycleState.resumed:
        _backgrounded = false;
        final completer = _resumeCompleter;
        _resumeCompleter = null;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      case AppLifecycleState.inactive:
      // Permission prompts and system overlays can be transiently inactive;
      // wait for a terminal background state before disposing WebView state.
    }
  }

  Future<void> waitForForeground() async {
    if (!_backgrounded) return;
    final completer = _resumeCompleter ??= Completer<void>();
    try {
      await completer.future.timeout(resumeWaitTimeout);
    } on TimeoutException {
      throw const _ShuweiScheduleImportResumeTimeoutException();
    }
  }

  @visibleForTesting
  void debugReset() {
    if (_active.isNotEmpty) {
      throw StateError('cannot reset active schedule import attempts');
    }
    _backgrounded = false;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}

class _ShuweiScheduleImportAbortException implements Exception {
  const _ShuweiScheduleImportAbortException(this.reason);

  final ShuweiScheduleImportAbortReason reason;
}

class _ShuweiScheduleImportResumeTimeoutException implements Exception {
  const _ShuweiScheduleImportResumeTimeoutException();
}

/// 按 WakeUp `shuwei` 分支的链路导入本科课表。
///
/// 首页菜单以 AJAX 插入树维查询页片段，页面初始化后调用其自身的
/// `searchTable()` 把课表渲染进 `contentDiv`，最后读取页面已生成的
/// `table0` 数据对象。不整页跳转、不重新请求课表接口、不解析课表 DOM。
class ShuweiScheduleImporter {
  static Future<void> _importTail = Future.value();
  static final Map<String, Future<AcademicScheduleFetchResult>> _inFlight = {};
  static final _lifecycle = _ShuweiScheduleImportLifecycle();

  static final _homeUri = CampusServiceEndpoints.academicAffairsHomeUri;
  static const _pollInterval = Duration(milliseconds: 250);
  static const _controllerTimeout = Duration(seconds: 8);
  static const _importTimeout = Duration(seconds: 30);
  static const _switchSettleDelay = Duration(milliseconds: 1200);
  static const _resumeSettleDelay = Duration(milliseconds: 300);
  static const _cookieRecoveryDelay = Duration(milliseconds: 250);

  ShuweiScheduleImporter() : _attemptForTesting = null;

  @visibleForTesting
  ShuweiScheduleImporter.forTesting(
    ShuweiScheduleImportAttemptForTesting attempt,
  ) : _attemptForTesting = attempt;

  final ShuweiScheduleImportAttemptForTesting? _attemptForTesting;

  static void handleAppLifecycleState(AppLifecycleState state) {
    _lifecycle.handle(state);
  }

  @visibleForTesting
  static void debugResetLifecycle() => _lifecycle.debugReset();

  Future<AcademicPersonalSchedule> importCurrent({
    AcademicScheduleScope scope = AcademicScheduleScope.personal,
  }) async => (await importSchedule(scope: scope)).schedule;

  Future<AcademicScheduleFetchResult> importSemester([String? semesterId]) =>
      importSchedule(semesterId: semesterId);

  Future<AcademicScheduleFetchResult> importSchedule({
    String? semesterId,
    AcademicScheduleScope scope = AcademicScheduleScope.personal,
  }) {
    final key = '${scope.name}|${semesterId?.trim() ?? ''}';
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _serialized(() => _importWithLifecycle(semesterId, scope));
    _inFlight[key] = future;
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }).ignore();
    return future;
  }

  Future<AcademicScheduleFetchResult> _importWithLifecycle(
    String? semesterId,
    AcademicScheduleScope scope,
  ) async {
    var automaticRestartCount = 0;
    while (true) {
      try {
        await _lifecycle.waitForForeground();
        final context = _lifecycle.beginAttempt();
        try {
          final attempt = _attemptForTesting;
          final future =
              attempt == null
                  ? _importSemester(semesterId, scope, context)
                  : attempt(semesterId, scope, context);
          return await _awaitAttemptOrAbort(future, context);
        } finally {
          _lifecycle.endAttempt(context);
          await context.disposeResources();
        }
      } on _ShuweiScheduleImportAbortException catch (error) {
        if (automaticRestartCount >= 1) {
          _debugLifecycleStage(
            'academic.schedule.restart_exhausted',
            '课表导入自动恢复次数已用尽',
            attempt: automaticRestartCount + 1,
          );
          throw _abortException(error.reason);
        }
        automaticRestartCount++;
        switch (error.reason) {
          case ShuweiScheduleImportAbortReason.background:
            _debugLifecycleStage(
              'academic.schedule.background_cancelled',
              '课表导入因后台状态取消',
              attempt: automaticRestartCount,
            );
          case ShuweiScheduleImportAbortReason.cookieCommit:
            _debugLifecycleStage(
              'academic.schedule.cookie_commit_restart',
              '课表导入因 Cookie 提交失败重建',
              attempt: automaticRestartCount,
            );
        }
        try {
          await _lifecycle.waitForForeground();
        } on _ShuweiScheduleImportResumeTimeoutException {
          throw const AcademicAffairsException('课表加载等待前台恢复超时，请稍后重试。');
        }
        _debugLifecycleStage(
          'academic.schedule.resume_restart',
          '课表导入重新创建 WebView',
          attempt: automaticRestartCount + 1,
        );
        await Future<void>.delayed(
          error.reason == ShuweiScheduleImportAbortReason.background
              ? _resumeSettleDelay
              : _cookieRecoveryDelay,
        );
      } on _ShuweiScheduleImportResumeTimeoutException {
        throw const AcademicAffairsException('课表加载等待前台恢复超时，请稍后重试。');
      }
    }
  }

  Future<T> _awaitAttemptOrAbort<T>(
    Future<T> attempt,
    ShuweiScheduleImportAttemptContext context,
  ) {
    if (context.isAborted) {
      unawaited(attempt.then<void>((_) {}, onError: (_, __) {}));
      return Future<T>.error(
        _ShuweiScheduleImportAbortException(context.abortReason!),
      );
    }
    final guardedAttempt = attempt.then<T>((value) {
      // A WebView future can complete synchronously while the lifecycle
      // callback is cancelling it. Once cancellation has been recorded, the
      // result belongs to the abandoned attempt and must not win the race.
      context.throwIfAborted();
      return value;
    });
    return Future.any<T>([
      guardedAttempt,
      context.abortFuture.then<T>((reason) {
        throw _ShuweiScheduleImportAbortException(reason);
      }),
    ]);
  }

  AcademicAffairsException _abortException(
    ShuweiScheduleImportAbortReason reason,
  ) {
    switch (reason) {
      case ShuweiScheduleImportAbortReason.background:
        return const AcademicAffairsException('课表加载被后台切换中断，请回到前台后重试。');
      case ShuweiScheduleImportAbortReason.cookieCommit:
        return const AcademicAffairsException('教务系统会话恢复失败，请稍后重试。');
    }
  }

  void _debugLifecycleStage(String code, String message, {int? attempt}) {
    if (!kDebugMode) return;
    AppLogger.event(
      level: 'INFO',
      code: code,
      message: message,
      domain: 'academic',
      attempt: attempt,
    );
  }

  /// 教务系统会为查询页维护会话上下文；并发开多个 WebView 会让其中一个
  /// 抢不到上下文。导入请求串行执行，保证切换稳定。
  static Future<T> _serialized<T>(Future<T> Function() task) {
    final run = _importTail.then((_) => task());
    _importTail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<AcademicScheduleFetchResult> _importSemester(
    String? semesterId,
    AcademicScheduleScope scope,
    ShuweiScheduleImportAttemptContext attemptContext,
  ) async {
    attemptContext.throwIfAborted();
    final requestedSemester = semesterId?.trim() ?? '';
    final backend = await AcademicAffairsBackendResolver.resolveCurrent();
    attemptContext.throwIfAborted();
    if (backend != AcademicAffairsBackend.undergraduate) {
      throw const AcademicAffairsException('当前身份不支持使用本科课表导入器');
    }

    try {
      await CampusSession.open();
    } catch (_) {
      throw const AcademicAffairsException('请先登录后查看我的课表');
    }

    final proxy = ShuweiRequestProxy(
      refreshBinding:
          (binding) => AuthenticatedWebViewCapability.refreshServiceSession(
            binding: binding,
            entryUri: _homeUri,
          ),
      onFailure: (stage) {
        if (stage == ShuweiRequestProxyFailureStage.cookieCommit) {
          attemptContext.abort(ShuweiScheduleImportAbortReason.cookieCommit);
        }
      },
    );
    HeadlessInAppWebView? headlessWebView;
    final controllerCompleter = Completer<InAppWebViewController>();
    Object? mainFrameError;
    Object? courseTableError;

    attemptContext.attachResourceDisposer(() async {
      await headlessWebView?.dispose();
      proxy.dispose();
    });

    try {
      attemptContext.throwIfAborted();
      final binding = await AuthenticatedWebViewCapability.seedServiceSession(
        serviceId: CampusServices.academicAffairs,
        entryUri: _homeUri,
      );
      attemptContext.throwIfAborted();
      proxy.bindSession(binding);

      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(_homeUri.toString())),
        initialSettings: _settings(),
        onWebViewCreated: (controller) {
          if (!controllerCompleter.isCompleted) {
            controllerCompleter.complete(controller);
          }
        },
        shouldInterceptRequest:
            (controller, request) => proxy.intercept(request),
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame == true) mainFrameError = error;
          if (_isCourseTableRequest(request.url)) courseTableError = error;
        },
        onReceivedHttpError: (controller, request, response) {
          final failed = (response.statusCode ?? 200) >= 400;
          if (request.isForMainFrame == true && failed) {
            mainFrameError = response;
          }
          if (failed && _isCourseTableRequest(request.url)) {
            courseTableError = response;
          }
        },
      );

      await headlessWebView.run();
      attemptContext.throwIfAborted();
      final controller = await controllerCompleter.future.timeout(
        _controllerTimeout,
        onTimeout:
            () => throw const AcademicAffairsException('教务系统页面启动超时，请稍后重试。'),
      );
      attemptContext.throwIfAborted();
      return await _readSchedule(
        controller,
        () => mainFrameError,
        () => courseTableError,
        requestedSemester,
        scope,
        attemptContext,
      );
    } finally {
      await attemptContext.disposeResources();
    }
  }

  Future<AcademicScheduleFetchResult> _readSchedule(
    InAppWebViewController controller,
    Object? Function() readMainFrameError,
    Object? Function() readCourseTableError,
    String requestedSemester,
    AcademicScheduleScope scope,
    ShuweiScheduleImportAttemptContext context,
  ) async {
    final deadline = DateTime.now().add(_importTimeout);
    Object? lastParseError;
    var navigationRequested = false;
    var submitGuardInstalled = false;
    var tableQuerySubmitted = false;
    DateTime? tableQueryAt;
    var semesters = const <AcademicSemesterOption>[];
    DateTime? contextSeenAt;

    while (DateTime.now().isBefore(deadline)) {
      context.throwIfAborted();
      if (!navigationRequested) {
        try {
          final result = await controller.evaluateJavascript(
            source: ShuweiScheduleExtractor.openCourseTableScript,
          );
          navigationRequested = result == true || '$result' == 'true';
        } catch (_) {
          // The home page may still be replacing its document.
        }
      }

      ShuweiSemesterContext? semesterContext;
      try {
        semesterContext = ShuweiScheduleExtractor.semesterContext(
          await controller.evaluateJavascript(
            source: ShuweiScheduleExtractor.semesterContextScript,
          ),
        );
        if (semesterContext != null && semesterContext.semesters.isNotEmpty) {
          semesters = semesterContext.semesters;
        }
      } catch (_) {
        // The timetable query view is still being inserted.
      }

      if (semesterContext == null) {
        await Future<void>.delayed(_pollInterval);
        continue;
      }
      contextSeenAt ??= DateTime.now();

      if (!submitGuardInstalled) {
        submitGuardInstalled = true;
        try {
          await controller.evaluateJavascript(
            source: ShuweiScheduleExtractor.installSubmitGuardScript,
          );
        } catch (_) {
          // The query page may still be replacing its document.
        }
      }

      if (!await _isPageReady(controller) ||
          DateTime.now().difference(contextSeenAt) < _switchSettleDelay) {
        await Future<void>.delayed(_pollInterval);
        continue;
      }

      if (!tableQuerySubmitted) {
        final targetSemester =
            requestedSemester.isNotEmpty
                ? requestedSemester
                : semesterContext.semesterId;
        if (targetSemester.isEmpty) {
          await Future<void>.delayed(_pollInterval);
          continue;
        }
        try {
          final result = await controller.evaluateJavascript(
            source: ShuweiScheduleExtractor.selectScheduleScript(
              targetSemester,
              scope: scope,
            ),
          );
          tableQuerySubmitted = result == true || '$result' == 'true';
          if (tableQuerySubmitted) {
            tableQueryAt = DateTime.now();
          }
        } catch (_) {
          // The query page may still be initializing.
        }
        await Future<void>.delayed(_pollInterval);
        continue;
      }

      final queryAt = tableQueryAt;
      if (queryAt != null &&
          DateTime.now().difference(queryAt) <
              const Duration(milliseconds: 500)) {
        await Future<void>.delayed(_pollInterval);
        continue;
      }

      try {
        final ready = await controller.evaluateJavascript(
          source: ShuweiScheduleExtractor.table0ReadyScript,
        );
        if (ready != true && '$ready' != 'true') {
          await Future<void>.delayed(_pollInterval);
          continue;
        }
      } catch (_) {
        await Future<void>.delayed(_pollInterval);
        continue;
      }

      try {
        final source = ShuweiScheduleExtractor.stringResult(
          await controller.evaluateJavascript(
            source: ShuweiScheduleExtractor.table0Script,
          ),
        );
        if (source == null || source.trim().isEmpty) {
          await Future<void>.delayed(_pollInterval);
          continue;
        }
        final resolvedSemesterId =
            requestedSemester.isNotEmpty
                ? requestedSemester
                : semesterContext.semesterId;
        final optionLabel =
            semesters
                .where((semester) => semester.id == resolvedSemesterId)
                .map((semester) => semester.label)
                .firstOrNull ??
            '';
        final semesterLabel = resolveSemesterLabel(
          requestedSemester: requestedSemester,
          contextLabel: semesterContext.semesterLabel,
          optionLabel: optionLabel,
        );
        final schedule = ShuweiScheduleParser.parse(
          source,
          semesterId: resolvedSemesterId,
          semesterLabel: semesterLabel,
        );
        return AcademicScheduleFetchResult(
          schedule: schedule,
          semesters: semesters,
        );
      } catch (error) {
        lastParseError = error;
        await Future<void>.delayed(_pollInterval);
      }
    }

    final mainFrameError = readMainFrameError();
    if (lastParseError != null) throw lastParseError;
    if (readCourseTableError() != null) {
      throw const AcademicAffairsException('教务系统课表入口加载失败，请稍后重试。');
    }
    if (mainFrameError != null) {
      throw const AcademicAffairsException('教务系统课表页面加载失败，请稍后重试。');
    }
    if (!navigationRequested) {
      throw const AcademicAffairsException('教务系统首页未找到“我的课表”入口。');
    }
    if (scope == AcademicScheduleScope.administrativeClass) {
      throw const AcademicAffairsException('当前账号的班级课表加载超时，请稍后重试。');
    }
    throw const AcademicAffairsException('教务系统课表加载超时，请稍后重试。');
  }

  Future<bool> _isPageReady(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(
        source: ShuweiScheduleExtractor.pageReadyScript,
      );
      return result == true || '$result' == 'true';
    } catch (_) {
      return false;
    }
  }

  bool _isCourseTableRequest(WebUri? url) {
    final uri = url == null ? null : Uri.tryParse(url.toString());
    return uri?.path.contains('/eams/courseTableForStd') == true;
  }

  static String resolveSemesterLabel({
    required String requestedSemester,
    required String contextLabel,
    required String optionLabel,
  }) {
    if (requestedSemester.isNotEmpty && optionLabel.isNotEmpty) {
      return optionLabel;
    }
    return contextLabel.isNotEmpty ? contextLabel : optionLabel;
  }

  InAppWebViewSettings _settings() => InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    useWideViewPort: true,
    thirdPartyCookiesEnabled: true,
    useShouldInterceptRequest: true,
    userAgent: AuthenticatedWebViewCapability.desktopUserAgent,
  );
}
