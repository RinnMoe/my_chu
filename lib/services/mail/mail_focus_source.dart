import 'package:flutter/foundation.dart';

import '../privacy_agreement_service.dart';
import 'mail_cache.dart';
import 'mail_config.dart';
import 'mail_config_store.dart';
import 'mail_session.dart';

/// 首页焦点需要的邮件摘要。
///
/// 只暴露未读数量与检查时间，不携带发件人、主题或正文。
class MailFocusCandidate {
  final int unread;
  final DateTime? checkedAt;

  const MailFocusCandidate({required this.unread, this.checkedAt});
}

/// 邮件的焦点来源。
///
/// 先返回缓存未读数，避免首页等待 IMAP；网络检查异步进行，失败时保留缓存，
/// 且从不向焦点层抛错。
class MailFocusSource {
  MailFocusSource({
    MailSession? session,
    MailConfigStore? configStore,
    MailCache? cache,
    DateTime Function()? clock,
    Future<bool> Function()? isPrivacyAccepted,
    Duration checkInterval = defaultCheckInterval,
  }) : _session = session ?? MailSession.instance,
       _configStore = configStore ?? MailConfigStore(),
       _cache = cache ?? MailCache(),
       _clock = clock ?? DateTime.now,
       _isPrivacyAccepted =
           isPrivacyAccepted ?? PrivacyAgreementService.isAccepted,
       _checkInterval = checkInterval;

  static const defaultCheckInterval = Duration(minutes: 15);

  static final MailFocusSource instance = MailFocusSource();

  final MailSession _session;
  final MailConfigStore _configStore;
  final MailCache _cache;
  final DateTime Function() _clock;
  final Future<bool> Function() _isPrivacyAccepted;
  final Duration _checkInterval;

  DateTime? _lastCheckAt;
  bool _checking = false;
  Future<void>? _pendingCheck;

  /// 当前异步检查的完成信号，仅供测试等待。
  @visibleForTesting
  Future<void> get pendingCheck => _pendingCheck ?? Future<void>.value();

  Future<MailFocusCandidate?> load() async {
    if (!await _isPrivacyAccepted()) return null;
    final config = await _configStore.read();
    if (config == null) {
      _lastCheckAt = null;
      return null;
    }

    final now = _clock();
    final cached = await _cache.readFocusUnread(config.email, now: now);
    final lastCheck = _lastCheckAt;
    if (lastCheck == null || now.difference(lastCheck) >= _checkInterval) {
      _lastCheckAt = now;
      _pendingCheck = _refresh(config);
    }
    if (cached == null) return null;
    return MailFocusCandidate(
      unread: cached.unread,
      checkedAt: cached.checkedAt,
    );
  }

  Future<void> _refresh(MailAccountConfig config) async {
    if (_checking) return;
    _checking = true;
    try {
      if (!await _isPrivacyAccepted()) return;
      final unread = await _session.checkUnread();
      final current = await _configStore.read();
      if (current?.email != config.email) return;
      await _cache.writeFocusUnread(config.email, unread, checkedAt: _clock());
    } on Object {
      // 检查失败保留缓存值，不把邮件故障传给焦点。
    } finally {
      _checking = false;
    }
  }
}
