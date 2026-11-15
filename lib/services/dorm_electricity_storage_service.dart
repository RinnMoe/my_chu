import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'logging/logger.dart';

/// Raw local storage shared by the feature and explicit host sign-out.
/// Campus authentication and network session material never enter this store.
class DormElectricityStorageService {
  DormElectricityStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  static const key = 'mychu.dorm_electricity.record.v2';
  static final revision = ValueNotifier<int>(0);

  /// A stuck queue must not hang every reader behind it; callers already turn a
  /// timeout into the stable `storage` failure category.
  static const _queueTimeout = Duration(seconds: 5);
  static Future<void> _tail = Future.value();
  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    await _tail.timeout(_queueTimeout);
    return _storage.read(key: key);
  }

  Future<bool> write(String? value, bool Function() current) {
    final epoch = revision.value;
    bool valid() => epoch == revision.value && current();
    final future = _tail.then((_) async {
      if (!valid()) return false;
      final previous = await _storage.read(key: key);
      if (!valid()) return false;
      try {
        await _storage.write(key: key, value: value);
      } catch (_) {
        await _restore(previous);
        rethrow;
      }
      if (valid()) return true;
      await _restore(previous);
      return false;
    });
    _tail = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  /// Invalidate readers and in-flight writes synchronously before queuing erase.
  /// The erase never restores the previous bytes: a failed clear must not
  /// resurrect a record the user just signed out of.
  Future<void> clearForSignOut() async {
    revision.value++;
    final future = _tail.then((_) async {
      try {
        await _storage.write(key: key, value: null);
      } catch (error, stack) {
        AppLogger.error(error, stackTrace: stack, context: '清除电费记录失败');
      }
    });
    _tail = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  /// Best effort: a failed rollback must not hide the storage error the caller
  /// is already handling, and there is no third state to report it as.
  Future<void> _restore(String? previous) async {
    try {
      await _storage.write(key: key, value: previous);
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack, context: '回滚电费记录失败');
    }
  }
}
