import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../host_platform.dart';

class ErrorEntry {
  const ErrorEntry({required this.timestamp, required this.content});
  final DateTime timestamp;
  final String content;
  String toText() => '${timestamp.toIso8601String()}\n$content';
}

class AppLogger {
  AppLogger._();
  static const maxErrors = 300;
  static const channel = MethodChannel('mychu/diagnostics');
  static final _errors = ValueNotifier<List<ErrorEntry>>(const []);
  static bool _crashRecording = false;
  static bool _publishing = false;
  static Future<void> _crashChanges = Future.value();
  static int _generation = 0;
  static bool _hostErrorsStarted = false;
  static bool _readingHostErrors = false;
  static bool _readHostErrorsAgain = false;
  static int _hostResetVersion = 0;
  static bool get supportsCrashRecording =>
      HostPlatform.current == HostPlatform.android;
  static bool get isCrashRecording => _crashRecording;
  static int get resetVersion => _generation;
  static ValueListenable<List<ErrorEntry>> get errors => _errors;
  static List<ErrorEntry> get entries => _errors.value;

  static Future<void> startHostErrors() async {
    if (_hostErrorsStarted ||
        (HostPlatform.current != HostPlatform.android &&
            HostPlatform.current != HostPlatform.harmony)) {
      return;
    }
    _hostErrorsStarted = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'errorsAvailable') await _readHostErrors();
    });
    await _readHostErrors();
  }

  static Future<void> _readHostErrors() async {
    _readHostErrorsAgain = true;
    if (_readingHostErrors) return;
    _readingHostErrors = true;
    try {
      do {
        _readHostErrorsAgain = false;
        final reset = _hostResetVersion;
        final batch = await channel.invokeListMethod<Object?>('takeErrors');
        if (reset != _hostResetVersion) continue;
        for (final item in batch ?? const []) {
          final entry = item as Map;
          _append(
            ErrorEntry(
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                (entry['timestamp'] as num).toInt(),
              ),
              content: entry['content'] as String,
            ),
          );
        }
      } while (_readHostErrorsAgain);
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack, context: '读取宿主错误');
    } finally {
      _readingHostErrors = false;
    }
  }

  static Future<void> restoreCrashRecording() async {
    if (!supportsCrashRecording) return;
    try {
      _crashRecording =
          await channel.invokeMethod<bool>('isCrashRecording') ?? false;
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
    }
  }

  static Future<bool> requiresCrashStoragePermission() async =>
      await channel.invokeMethod<bool>('requiresStoragePermission') ?? false;

  static Future<void> setCrashRecording(bool enabled) {
    final change = _crashChanges.then((_) async {
      if (enabled == _crashRecording) return;
      if (!supportsCrashRecording) {
        throw UnsupportedError(
          'Public crash reports are unavailable on this platform',
        );
      }
      await channel.invokeMethod<void>('setCrashRecording', {
        'enabled': enabled,
      });
      _crashRecording = enabled;
    });
    _crashChanges = change.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return change;
  }

  static void error(
    Object error, {
    StackTrace? stackTrace,
    bool fatal = false,
    String? context,
  }) {
    if (_publishing) return;
    String message;
    try {
      message = '${error.runtimeType}\n$error';
    } catch (_) {
      message = '${error.runtimeType} (toString failed)';
    }
    final entry = ErrorEntry(
      timestamp: DateTime.now(),
      content: [
        if (context != null) context,
        message,
        if (stackTrace != null)
          '$stackTrace'
        else
          '上报位置调用栈\n${StackTrace.current}',
      ].join('\n'),
    );
    _append(entry);
    if (fatal && _crashRecording) unawaited(_saveCrash(entry));
  }

  static Future<void> _saveCrash(ErrorEntry entry) async {
    try {
      await channel.invokeMethod<void>('saveCrashReport', {
        'content': entry.toText(),
      });
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
    }
  }

  static Future<T> guardAsync<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
      rethrow;
    }
  }

  static void debug(String message) => _print(message);
  static void info(String message) => _print(message);
  static void warn(String message) {
    if (_publishing) return;
    _append(ErrorEntry(timestamp: DateTime.now(), content: '警告\n$message'));
  }

  static void _print(String message) {
    if (kDebugMode) developer.log(message, name: 'MyCHU');
  }

  static void _append(ErrorEntry entry) {
    final values = [...entries];
    final next = values.indexWhere(
      (value) => value.timestamp.isAfter(entry.timestamp),
    );
    values.insert(next < 0 ? values.length : next, entry);
    _publish(values);
    if (kDebugMode) developer.log(entry.toText(), name: 'MyCHU', level: 1000);
  }

  static void _publish(List<ErrorEntry> values) {
    final start = values.length > maxErrors ? values.length - maxErrors : 0;
    _publishing = true;
    try {
      _errors.value = List.unmodifiable(values.sublist(start));
    } finally {
      _publishing = false;
    }
  }

  static void clear() {
    _generation++;
    _hostResetVersion++;
    _publish([]);
    if (_hostErrorsStarted) unawaited(_clearHostErrors());
  }

  static Future<void> _clearHostErrors() async {
    try {
      await channel.invokeMethod<void>('clearErrors');
      await _readHostErrors();
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack, context: '清空宿主错误');
    }
  }

  /// Removes the exported snapshot while keeping errors recorded during sharing.
  static void clearExported(
    List<ErrorEntry> exported, {
    required int resetVersion,
  }) {
    if (resetVersion != _generation) return;
    final exportedEntries = exported.toSet();
    _generation++;
    _publish(
      entries.where((entry) => !exportedEntries.contains(entry)).toList(),
    );
  }

  @visibleForTesting
  static void resetForTest() {
    _hostErrorsStarted = false;
    channel.setMethodCallHandler(null);
    _crashRecording = false;
    _crashChanges = Future.value();
    clear();
  }
}
