import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_policy_document.dart';
import 'privacy_policy_repository.dart';

/// Stores whether the user accepted the current user agreement.
class PrivacyAgreementService {
  PrivacyAgreementService._();

  /// Minimum historical acceptance retained for offline migration.
  /// Cloud versions are supplied by the validated startup snapshot.
  static const int currentVersion = 3;
  static const String versionKey = 'privacy.agreement.version';
  static const String _legacyMigrationKey =
      'privacy.agreement.legacy_v7_migrated';
  static const String _legacyConsentKey = 'privacy.consent.sdk_list';
  static const String _legacyVersionKey = 'privacy.consent.sdk_list.version';
  static const int _legacyConsentVersion = 7;

  /// Notifies protected pages immediately when the agreement is accepted or
  /// withdrawn, so they can refresh or clear account-scoped in-memory data.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const recordKey = 'privacy.agreement.acceptance';
  static const String policyCheckedAtKey = 'privacy.agreement.checked_at';

  /// 后台索引检查的节流窗口；冷启动不再同步等待协议源。
  static const Duration policyRefreshTtl = Duration(hours: 24);

  /// 测试注入的随包正文替身；为 null 时读取 `privacy/` 资源。
  @visibleForTesting
  static PrivacyPolicyDocument? debugBundledDocument;

  static int _requiredVersion = currentVersion;

  /// Local only. A cached document can never create acceptance.
  static Future<int> acceptedVersion() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyV7(preferences);
    final raw = preferences.getString(recordKey);
    if (raw == null) {
      final legacy = preferences.getInt(versionKey) ?? 0;
      // Integer-only history predates cloud receipts; it cannot authorize a
      // newer processor without the document/hash acceptance record.
      return legacy <= currentVersion ? legacy : 0;
    }
    try {
      final record = jsonDecode(raw) as Map<String, dynamic>;
      final version = record['version'];
      if (version == 0) return 0;
      if (version is! int ||
          version < 4 ||
          record['revision'] is! String ||
          record['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(record['sha256'] as String) ||
          record['acceptedAt'] is! String ||
          DateTime.tryParse(record['acceptedAt'] as String) == null) {
        return 0;
      }
      return version;
    } catch (_) {
      return 0;
    }
  }

  static Future<String?> acceptedHash() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      return (jsonDecode(preferences.getString(recordKey) ?? '{}')
              as Map<String, dynamic>)['sha256']
          as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isAccepted() async =>
      await acceptedVersion() >= _requiredVersion;

  /// 本地启动检查：只读本地已接受版本与随包/缓存正文，绝不联网，也不抛错。
  ///
  /// 返回需要用户确认的协议快照；返回 null 表示本地同意已覆盖当前版本，
  /// 或本地暂时没有可用正文（此时启动继续，受保护动作仍由 [isAccepted] 拦截）。
  static Future<PrivacyPolicyDocument?> prepareStartupLocal() async {
    try {
      _requiredVersion = currentVersion;
      final accepted = await acceptedVersion();
      final document = await _loadLocalDocument();
      if (document == null) return null;
      if (document.version <= accepted) return null;
      _requiredVersion = document.version;
      return document;
    } catch (_) {
      // 本地状态损坏也不能阻断启动；受保护动作仍由 isAccepted 拦截。
      return null;
    }
  }

  /// 后台刷新协议索引；每次冷启动至多一次，失败静默返回 null。
  ///
  /// 只把“发现更高版本”当作结果；网络失败、回退或同版变更都不影响启动。
  static Future<PrivacyPolicyDocument?> refreshInBackground({
    bool force = false,
    Duration ttl = policyRefreshTtl,
  }) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = preferences.getInt(policyCheckedAtKey) ?? 0;
      if (!force && now - last < ttl.inMilliseconds) return null;
      final accepted = await acceptedVersion();
      final document = await PrivacyPolicyRepository.instance.refresh(
        acceptedVersion: accepted,
        acceptedHash: await acceptedHash(),
      );
      await preferences.setInt(policyCheckedAtKey, now);
      if (document.version <= accepted) return null;
      _requiredVersion = document.version;
      return document;
    } catch (_) {
      // 启动不因协议源不可用而失败；下一次冷启动或前台再试。
      return null;
    }
  }

  /// 本地可用的协议正文：优先随包资源，其次上次下载的缓存。
  static Future<PrivacyPolicyDocument?> _loadLocalDocument() async {
    final injected = debugBundledDocument;
    if (injected != null) return injected;
    try {
      final index =
          jsonDecode(await rootBundle.loadString('privacy/latest.json'))
              as Map<String, dynamic>;
      final path = index['path'];
      final hash = index['sha256'];
      if (index['schemaVersion'] != 1 || path is! String || hash is! String) {
        throw const FormatException('Invalid bundled policy index');
      }
      final body = await rootBundle.loadString('privacy/$path');
      return PrivacyPolicyDocument.decode(body, expectedHash: hash);
    } catch (_) {
      // 随包资源缺失或损坏时回退到已下载缓存。
    }
    try {
      final cached = await PrivacyPolicyRepository.instance.cached();
      return cached.isEmpty ? null : cached.first;
    } catch (_) {
      return null;
    }
  }

  static Future<void> accept(PrivacyPolicyDocument document) async {
    if (document.version < 4 || document.version < _requiredVersion) {
      throw StateError('Obsolete policy');
    }
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyV7(preferences);
    final accepted = await acceptedVersion();
    if (document.version < accepted) throw StateError('Policy rollback');
    final hash = await acceptedHash();
    if (document.version == accepted && hash != null && hash != document.hash) {
      throw StateError('Policy mutation');
    }
    try {
      final saved = await preferences.setString(
        recordKey,
        jsonEncode({
          'version': document.version,
          'revision': document.revision,
          'sha256': document.hash,
          'acceptedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      if (!saved) throw StateError('无法保存隐私协议状态');
    } catch (_) {
      await preferences.reload();
      rethrow;
    }
    revision.value++;
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyV7(preferences);
    // Tombstone first: an old version key must never resurrect consent.
    if (!await preferences.setString(recordKey, jsonEncode({'version': 0}))) {
      throw StateError('无法清除隐私协议状态');
    }
    await preferences.remove(versionKey);
    revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    _requiredVersion = currentVersion;
    debugBundledDocument = null;
  }

  static Future<void> _migrateLegacyV7(SharedPreferences preferences) async {
    if (preferences.getBool(_legacyMigrationKey) == true) return;

    final legacyKeys = preferences
        .getKeys()
        .where((key) => key.startsWith('privacy.consent.'))
        .toList(growable: false);
    final legacyAccepted =
        preferences.getBool(_legacyConsentKey) == true &&
        (preferences.getInt(_legacyVersionKey) ?? 0) >= _legacyConsentVersion;

    if (legacyAccepted &&
        !preferences.containsKey(versionKey) &&
        !preferences.containsKey(recordKey)) {
      // Preserve the historical acceptance; never promote it on a later bump.
      final saved = await preferences.setInt(versionKey, 1);
      if (!saved) throw StateError('无法迁移既有隐私协议状态');
    }

    for (final key in legacyKeys) {
      final removed = await preferences.remove(key);
      if (!removed && preferences.containsKey(key)) {
        throw StateError('无法清理旧隐私状态');
      }
    }

    final marked = await preferences.setBool(_legacyMigrationKey, true);
    if (!marked) throw StateError('无法完成旧隐私状态迁移');
  }
}
