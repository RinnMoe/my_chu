import 'remote_feature_policy_models.dart';
import 'remote_feature_policy_source.dart';
import 'remote_feature_policy_store.dart';

import '../logging/logger.dart';

/// Fetches, validates and caches the published policy set.
///
/// The repository never applies a partial payload: [fetch] returns a snapshot
/// only when every row is valid, and [loadCached] discards a snapshot that can
/// no longer be decoded.
class RemoteFeaturePolicyRepository {
  RemoteFeaturePolicyRepository({
    required this.source,
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RemoteFeaturePolicySource source;
  final RemoteFeaturePolicyStore store;
  final DateTime Function() _clock;

  /// Returns the last validated snapshot, or null when the cache is absent or
  /// unreadable. A corrupt cache is removed so the next refresh starts clean.
  Future<RemoteFeaturePolicySnapshot?> loadCached() async {
    final String? raw;
    try {
      raw = await store.read();
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      return RemoteFeaturePolicySnapshot.decode(raw);
    } on RemoteFeaturePolicyFormatException catch (
      diagnosticError,
      diagnosticStack
    ) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      await _clearQuietly();
      return null;
    }
  }

  /// Fetches and validates the published set.
  ///
  /// Throws [RemoteFeaturePolicyFetchException] on transport failure and
  /// [RemoteFeaturePolicyFormatException] when the payload cannot be trusted.
  Future<RemoteFeaturePolicySnapshot> fetch() async {
    final rows = await source.fetchRows();
    return RemoteFeaturePolicySnapshot.fromRows(rows, fetchedAt: _clock());
  }

  /// Persists a validated snapshot. Failures are surfaced to the caller so the
  /// service can keep the in-memory snapshot usable for this session.
  Future<void> persist(RemoteFeaturePolicySnapshot snapshot) =>
      store.write(snapshot.encode());

  Future<void> _clearQuietly() async {
    try {
      await store.clear();
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      // A stale cache is harmless once the in-memory snapshot is authoritative.
    }
  }

  void close() => source.close();
}
