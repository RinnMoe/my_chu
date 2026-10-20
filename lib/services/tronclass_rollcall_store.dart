import 'dart:async';

import 'package:flutter/foundation.dart';

import '../apps/tronclass_rollcall/tronclass_rollcall_models.dart';
import '../apps/tronclass_rollcall/tronclass_rollcall_qr.dart';
import '../apps/tronclass_rollcall/tronclass_rollcall_service.dart';
import 'auth_service.dart';
import 'host_auth_state.dart';
import 'privacy_agreement_service.dart';
import 'user_error_message.dart';
import 'logger_service.dart';

/// Host-owned ephemeral state. No attendance codes, QR data or credentials are cached.
class TronclassRollcallStore extends ChangeNotifier {
  TronclassRollcallStore({
    TronclassRollcallService? service,
    String? Function()? owner,
    Future<bool> Function()? consent,
    bool Function()? requestsAllowed,
    bool bindHost = true,
  }) : _service = service ?? TronclassRollcallService(),
       _readOwner = owner ?? _hostOwner,
       _consent = consent ?? PrivacyAgreementService.isAccepted,
       _requestsAllowed =
           requestsAllowed ??
           (() => !HostAuthState.snapshot.value.blocksRequests),
       _bindHost = bindHost {
    _owner = _readOwner();
    if (bindHost) {
      HostAuthState.snapshot.addListener(_hostChanged);
      AuthService.sessionRevisionNotifier.addListener(_hostChanged);
      PrivacyAgreementService.revision.addListener(_privacyChanged);
    }
  }

  static final instance = TronclassRollcallStore();
  final TronclassRollcallService _service;
  final String? Function() _readOwner;
  final Future<bool> Function() _consent;
  final bool Function() _requestsAllowed;
  final bool _bindHost;
  String? _owner;
  int _identity = 0;
  bool _started = false;
  bool _disposed = false;
  bool _checked = false;
  bool _loading = false;
  RollcallException? _error;
  List<TronclassRollcall> _items = const [];
  final Set<String> _completed = {};
  final Set<String> _submitting = {};
  Future<void>? _pending;

  List<TronclassRollcall> get items => _items;
  bool get loading => _loading;
  bool get hasChecked => _checked;
  RollcallException? get error => _error;
  int get identity => _identity;
  bool isSubmitting(String id) => _submitting.contains(id);

  static String? _hostOwner() {
    final auth = HostAuthState.snapshot.value;
    final key = auth.accountKey;
    if (key == null || auth.status == HostAuthStatus.storageError) return null;
    return '$key:${auth.contentRevision}:${AuthService.sessionRevision}';
  }

  void start() {
    _started = true;
    _hostChanged();
  }

  void _hostChanged() {
    _syncOwner();
    if (_started &&
        !_checked &&
        _requestsAllowed() &&
        (!_bindHost ||
            HostAuthState.snapshot.value.status != HostAuthStatus.checking)) {
      unawaited(ensureInitialCheck());
    }
  }

  void _syncOwner() {
    final current = _readOwner();
    if (current != _owner) {
      _clear();
      _owner = current;
    }
  }

  void _privacyChanged() {
    // Invalidate synchronously, before the asynchronous consent read completes.
    _clear();
  }

  void _clear() {
    _identity++;
    _pending = null;
    _items = const [];
    _completed.clear();
    _submitting.clear();
    _checked = false;
    _loading = false;
    _error = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> ensureInitialCheck() {
    _syncOwner();
    return _checked ? Future<void>.value() : refresh();
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    _syncOwner();
    if (_pending != null) return _pending!;
    late final Future<void> pending;
    pending = _refresh().whenComplete(() {
      if (identical(_pending, pending)) _pending = null;
    });
    return _pending = pending;
  }

  bool _current(int identity) =>
      !_disposed && identity == _identity && _owner == _readOwner();

  Future<void> _refresh() async {
    final identity = _identity;
    try {
      if (_owner == null ||
          !_requestsAllowed() ||
          !await _consent() ||
          !_current(identity) ||
          !_requestsAllowed()) {
        return;
      }
      _checked = true;
      _loading = true;
      notifyListeners();
      final result = await _service.fetchActive();
      if (!_current(identity)) return;
      _items = List.unmodifiable(
        result.where((item) => !_completed.contains(item.id)),
      );
      _error = null;
    } catch (error) {
      if (!_current(identity)) return;
      _error =
          error is RollcallException
              ? error
              : const RollcallException(RollcallFailure.network);
      if (_error!.failure != RollcallFailure.authentication) {
        logUserFacingError(
          UserErrorContext.network,
          error,
          operationId: UserOperationId.tronclassRollcallLoad,
        );
      }
    } finally {
      if (_current(identity)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> answerNumber(
    TronclassRollcall item,
    String code, {
    required int expectedIdentity,
  }) =>
      _answer(item, () => _service.answerNumber(item, code), expectedIdentity);

  Future<bool> answerQr(
    TronclassRollcall item,
    TronclassRollcallQr qr, {
    required int expectedIdentity,
  }) => _answer(item, () => _service.answerQr(item, qr), expectedIdentity);

  Future<bool> _answer(
    TronclassRollcall item,
    Future<void> Function() send,
    int identity,
  ) async {
    _syncOwner();
    if (!_current(identity) ||
        _owner == null ||
        _submitting.contains(item.id) ||
        !_items.any((entry) => entry.id == item.id)) {
      return false;
    }
    // Reserve synchronously so repeated callbacks cannot pass the async consent check.
    _submitting.add(item.id);
    notifyListeners();
    try {
      if (!_requestsAllowed() || !await _consent() || !_requestsAllowed()) {
        throw const RollcallException(RollcallFailure.authentication);
      }
      if (!_current(identity)) return false;
      await send();
      if (!_current(identity)) return false;
      _remove(item.id);
      return true;
    } on RollcallException catch (error) {
      if (!_current(identity)) return false;
      if (error.failure == RollcallFailure.ended) _remove(item.id);
      if (error.failure != RollcallFailure.authentication) {
        logUserFacingError(
          UserErrorContext.network,
          error,
          operationId: UserOperationId.tronclassRollcallAnswer,
        );
      }
      rethrow;
    } catch (error) {
      if (!_current(identity)) return false;
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.tronclassRollcallAnswer,
      );
      throw const RollcallException(RollcallFailure.uncertain);
    } finally {
      if (_current(identity)) {
        _submitting.remove(item.id);
        notifyListeners();
      }
    }
  }

  void _remove(String id) {
    _completed.add(id);
    _items = List.unmodifiable(_items.where((item) => item.id != id));
  }

  @override
  void dispose() {
    _disposed = true;
    _identity++;
    if (_bindHost) {
      HostAuthState.snapshot.removeListener(_hostChanged);
      AuthService.sessionRevisionNotifier.removeListener(_hostChanged);
      PrivacyAgreementService.revision.removeListener(_privacyChanged);
    }
    super.dispose();
  }
}
