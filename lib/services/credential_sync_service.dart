import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../services/service_endpoints.dart';
import '../services/session_readiness_service.dart';

enum CredentialSyncItemStatus { pending, success, failed, deferred }

class CredentialSyncItemState {
  final CredentialSyncItemStatus status;
  final String message;

  const CredentialSyncItemState({required this.status, this.message = ''});

  bool get isTerminal => status != CredentialSyncItemStatus.pending;
}

class CredentialSyncState {
  final String? accountKey;
  final int sessionRevision;
  final int runId;
  final bool isSyncing;
  final bool hasError;
  final int completedSteps;
  final int totalSteps;
  final String message;
  final Map<CampusServiceId, CredentialSyncItemState> items;

  const CredentialSyncState({
    this.accountKey,
    this.sessionRevision = 0,
    this.runId = 0,
    this.isSyncing = false,
    this.hasError = false,
    this.completedSteps = 0,
    this.totalSteps = 0,
    this.message = '',
    this.items = const {},
  });

  bool get isForAccount => accountKey != null && accountKey!.isNotEmpty;
}

/// Account-scoped, non-blocking credential warm-up.
///
/// The service owns the completion barrier and status publication. A feature
/// may observe the state, but it must not infer portal readiness from another
/// service's profile request.
class CredentialSyncService {
  static const coreServices = <CampusServiceId>[
    CampusServices.mobileCampus,
    CampusServices.informationPortal,
    CampusServices.courseOnline,
  ];

  static final statusNotifier = _createStatusNotifier();
  static int _nextRunId = 0;

  /// Test seam for exercising the completion barrier without contacting a
  /// campus service. Production callers always use session readiness.
  @visibleForTesting
  static Future<bool> Function(CampusServiceId serviceId)? debugReadinessGetter;

  static ValueNotifier<CredentialSyncState> _createStatusNotifier() {
    AuthService.sessionRevisionNotifier.addListener(_discardStaleState);
    return ValueNotifier(const CredentialSyncState());
  }

  static void _discardStaleState() {
    final current = statusNotifier.value;
    if (current.accountKey == null ||
        current.sessionRevision == AuthService.sessionRevision) {
      return;
    }
    ++_nextRunId;
    statusNotifier.value = const CredentialSyncState();
  }

  static Future<void> startForAccount(
    String accountKey, {
    Iterable<CampusServiceId> services = coreServices,
  }) async {
    final serviceList = services.toSet().toList(growable: false);
    final sessionRevision = AuthService.sessionRevision;
    final runId = ++_nextRunId;
    final items = <CampusServiceId, CredentialSyncItemState>{
      for (final serviceId in serviceList)
        serviceId: const CredentialSyncItemState(
          status: CredentialSyncItemStatus.pending,
        ),
    };
    statusNotifier.value = CredentialSyncState(
      accountKey: accountKey,
      sessionRevision: sessionRevision,
      runId: runId,
      isSyncing: serviceList.isNotEmpty,
      totalSteps: serviceList.length,
      message: serviceList.isEmpty ? '' : '正在同步核心应用会话…',
      items: Map.unmodifiable(items),
    );
    if (serviceList.isEmpty) return;

    await Future.wait<void>(
      serviceList.map(
        (serviceId) => _syncTarget(
          accountKey: accountKey,
          sessionRevision: sessionRevision,
          runId: runId,
          serviceId: serviceId,
        ),
      ),
    );
  }

  static Future<void> _syncTarget({
    required String accountKey,
    required int sessionRevision,
    required int runId,
    required CampusServiceId serviceId,
  }) async {
    try {
      final account = await AuthService.getCurrentAccount();
      if (account == null ||
          account.accountKey != accountKey ||
          AuthService.sessionRevision != sessionRevision) {
        _discardRun(accountKey, sessionRevision, runId);
        return;
      }
      final getter = debugReadinessGetter;
      final available =
          getter != null
              ? await getter(serviceId)
              : await SessionReadinessService.ensure(serviceId);
      _publishItem(
        accountKey: accountKey,
        sessionRevision: sessionRevision,
        runId: runId,
        serviceId: serviceId,
        item: CredentialSyncItemState(
          status:
              available
                  ? CredentialSyncItemStatus.success
                  : CredentialSyncItemStatus.failed,
          message: available ? '已完成' : '暂未获取到会话',
        ),
      );
    } catch (error) {
      AppLogger.warn(
        '后台准备 ${CampusServiceEndpoints.labelFor(serviceId)} 会话失败 '
        '(${error.runtimeType})',
      );
      _publishItem(
        accountKey: accountKey,
        sessionRevision: sessionRevision,
        runId: runId,
        serviceId: serviceId,
        item: const CredentialSyncItemState(
          status: CredentialSyncItemStatus.failed,
          message: '获取失败，使用时可重试',
        ),
      );
    }
  }

  static void _publishItem({
    required String accountKey,
    required int sessionRevision,
    required int runId,
    required CampusServiceId serviceId,
    required CredentialSyncItemState item,
  }) {
    final current = statusNotifier.value;
    if (AuthService.sessionRevision != sessionRevision) {
      _discardRun(accountKey, sessionRevision, runId);
      return;
    }
    if (current.accountKey != accountKey ||
        current.sessionRevision != sessionRevision ||
        current.runId != runId ||
        AuthService.sessionRevision != sessionRevision) {
      return;
    }
    final items = Map<CampusServiceId, CredentialSyncItemState>.from(
      current.items,
    )..[serviceId] = item;
    final completed = items.values.where((value) => value.isTerminal).length;
    final finished = completed == current.totalSteps;
    final hasError =
        finished &&
        items.values.any(
          (value) => value.status == CredentialSyncItemStatus.failed,
        );
    statusNotifier.value = CredentialSyncState(
      accountKey: accountKey,
      sessionRevision: sessionRevision,
      runId: runId,
      isSyncing: !finished,
      hasError: hasError,
      completedSteps: completed,
      totalSteps: current.totalSteps,
      message:
          !finished
              ? '正在同步 ${_serviceLabel(serviceId)}…'
              : hasError
              ? '部分核心会话暂未同步，打开对应应用时会自动重试'
              : '核心应用会话已同步',
      items: Map.unmodifiable(items),
    );
  }

  static void _discardRun(String accountKey, int sessionRevision, int runId) {
    final current = statusNotifier.value;
    if (current.accountKey == accountKey &&
        current.sessionRevision == sessionRevision &&
        current.runId == runId) {
      ++_nextRunId;
      statusNotifier.value = const CredentialSyncState();
    }
  }

  static String _serviceLabel(CampusServiceId serviceId) {
    return CampusServiceEndpoints.labelFor(serviceId);
  }

  static void cancel({String? accountKey}) {
    final current = statusNotifier.value;
    if (accountKey != null && current.accountKey != accountKey) return;
    ++_nextRunId;
    statusNotifier.value = const CredentialSyncState();
  }

  /// Compatibility helpers for pages that only need to dismiss an old status.
  static void complete() => cancel();

  static void fail(String message) {
    final current = statusNotifier.value;
    statusNotifier.value = CredentialSyncState(
      accountKey: current.accountKey,
      sessionRevision: current.sessionRevision,
      runId: current.runId,
      hasError: true,
      completedSteps: current.completedSteps,
      totalSteps: current.totalSteps,
      message: message,
      items: current.items,
    );
  }
}
