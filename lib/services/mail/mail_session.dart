import 'dart:async';

import 'package:flutter/foundation.dart';

import '../privacy_agreement_service.dart';
import 'enough_mail_sender.dart';
import 'enough_mail_transport.dart';
import 'mail_cache.dart';
import 'mail_compose.dart';
import 'mail_config.dart';
import 'mail_config_store.dart';
import 'mail_credential_store.dart';
import 'mail_error.dart';
import 'mail_models.dart';
import 'mail_transport.dart';

@immutable
class MailSessionState {
  final MailAccountConfig? config;
  final List<MailFolder> folders;
  final bool hasCredential;

  const MailSessionState({
    this.config,
    this.folders = const [],
    this.hasCredential = false,
  });

  static const initial = MailSessionState();

  bool get isConfigured => config != null && hasCredential;

  MailFolder? get inbox {
    for (final folder in folders) {
      if (folder.role == MailFolderRole.inbox) return folder;
    }
    return folders.isEmpty ? null : folders.first;
  }

  MailSessionState copyWith({
    MailAccountConfig? config,
    List<MailFolder>? folders,
    bool? hasCredential,
  }) {
    return MailSessionState(
      config: config ?? this.config,
      folders: folders ?? this.folders,
      hasCredential: hasCredential ?? this.hasCredential,
    );
  }
}

/// 邮箱会话：唯一持有收信连接、发送器、凭证读取与串行命令队列的宿主入口。
///
/// 页面只通过本类的方法与 [state] 交互，不接触 `enough_mail` 或密码。
class MailSession {
  MailSession({
    MailTransport? transport,
    MailSender? sender,
    MailConfigStore? configStore,
    MailCredentialStore? credentialStore,
    MailCache? cache,
    Future<bool> Function()? isPrivacyAccepted,
    Duration idleTimeout = const Duration(seconds: 60),
  }) : _transport = transport ?? const EnoughMailTransport(),
       _sender = sender ?? const EnoughMailSender(),
       _configStore = configStore ?? MailConfigStore(),
       _credentials = credentialStore ?? MailCredentialStore(),
       _cache = cache ?? MailCache(),
       _isPrivacyAccepted =
           isPrivacyAccepted ?? PrivacyAgreementService.isAccepted,
       _idleTimeout = idleTimeout;

  static final MailSession instance = MailSession();

  final ValueNotifier<MailSessionState> state = ValueNotifier(
    MailSessionState.initial,
  );

  /// 任何会影响首页焦点或未读数的变更都会递增。
  final ValueNotifier<int> revision = ValueNotifier(0);

  final MailTransport _transport;
  final MailSender _sender;
  final MailConfigStore _configStore;
  final MailCredentialStore _credentials;
  final MailCache _cache;
  final Future<bool> Function() _isPrivacyAccepted;
  final Duration _idleTimeout;

  MailAccountConfig? _config;
  MailConnection? _connection;
  Timer? _idleTimer;
  Future<void> _tail = Future.value();
  Future<void> _sendTail = Future.value();
  Future<void>? _initialization;
  int _epoch = 0;

  bool _isCurrentOwner(int epoch, MailAccountConfig? config) =>
      config != null && _epoch == epoch && _config?.email == config.email;

  Future<void> initialize() => _initialization ??= _runInitialize();

  Future<void> _runInitialize() async {
    try {
      await _loadInitialState();
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _loadInitialState() async {
    final config = await _configStore.read();
    final hasCredential =
        config != null && await _credentials.hasCredential(config.email);
    _config = config;
    state.value = MailSessionState(
      config: config,
      hasCredential: hasCredential,
    );
  }

  Future<void> _requirePrivacyAccepted() async {
    if (!await _isPrivacyAccepted()) {
      throw const MailException(MailErrorKind.rejected, '请先同意用户协议后再使用校园邮箱');
    }
  }

  Future<void> configure(MailAccountConfig config, String secret) async {
    await initialize();
    final validation = config.validationError;
    if (validation != null) {
      throw MailException(MailErrorKind.notConfigured, validation);
    }
    final normalizedSecret = secret.trim();
    if (normalizedSecret.isEmpty) {
      throw const MailException(MailErrorKind.invalidCredentials, '请输入密码');
    }

    await testConnection(config, normalizedSecret);

    final previousEmail = _config?.email;
    ++_epoch;
    await _dropConnection();
    await _configStore.save(config);
    await _credentials.save(config.email, normalizedSecret);
    if (previousEmail != null && previousEmail != config.email) {
      await _cache.clear(previousEmail);
    }
    _config = config;
    state.value = state.value.copyWith(
      config: config,
      hasCredential: true,
      folders: const [],
    );
    _bumpRevision();
  }

  /// 修改服务器地址等非机密配置；邮箱不变时保留已保存的密码。
  Future<void> updateConfig(MailAccountConfig config) async {
    await initialize();
    final validation = config.validationError;
    if (validation != null) {
      throw MailException(MailErrorKind.notConfigured, validation);
    }
    final existing = _config;
    final hasSecret = await _credentials.hasCredential(config.email);
    if (existing?.email != config.email || !hasSecret) {
      throw const MailException(MailErrorKind.invalidCredentials, '请输入密码');
    }

    ++_epoch;
    await _dropConnection();
    await _configStore.save(config);
    _config = config;
    state.value = state.value.copyWith(config: config, hasCredential: true);
    _bumpRevision();
  }

  /// 仅验证连通性与凭证，不保存任何内容。
  Future<List<MailFolder>> testConnection(
    MailAccountConfig config,
    String secret,
  ) async {
    await _requirePrivacyAccepted();
    final connection = await _transport.connect(config, secret.trim());
    try {
      return await connection.listFolders();
    } finally {
      try {
        await connection.close();
      } catch (_) {
        // 关闭失败不影响验证结果。
      }
    }
  }

  Future<List<MailFolder>> refreshFolders() async {
    final config = _config;
    final epoch = _epoch;
    try {
      final folders = await _withConnection(
        (connection) => connection.listFolders(),
        retry: true,
      );
      if (config != null && _isCurrentOwner(epoch, config)) {
        await _cache.writeFolders(config.email, folders);
        state.value = state.value.copyWith(folders: folders);
        _bumpRevision();
      }
      return folders;
    } on MailException catch (error) {
      if (config != null &&
          _isCurrentOwner(epoch, config) &&
          error.isRetryable) {
        final cached = await _cache.readFolders(config.email);
        if (cached != null &&
            cached.folders.isNotEmpty &&
            _isCurrentOwner(epoch, config)) {
          state.value = state.value.copyWith(folders: cached.folders);
          return cached.folders;
        }
      }
      rethrow;
    }
  }

  Future<MailPage> loadHeaders(
    String folderPath, {
    int? beforeUid,
    int limit = 20,
  }) async {
    final config = _config;
    final epoch = _epoch;
    final cacheKey = beforeUid ?? 0;
    try {
      final page = await _withConnection(
        (connection) => connection.fetchHeaders(
          folderPath,
          beforeUid: beforeUid,
          limit: limit,
        ),
        retry: true,
      );
      if (config != null && _isCurrentOwner(epoch, config)) {
        await _cache.writeHeaders(
          config.email,
          folderPath,
          cacheKey,
          page.items,
        );
      }
      return page;
    } on MailException catch (error) {
      if (config != null &&
          _isCurrentOwner(epoch, config) &&
          error.isRetryable) {
        final cached = await _cache.readHeaders(
          config.email,
          folderPath,
          cacheKey,
        );
        if (cached != null && _isCurrentOwner(epoch, config)) {
          return MailPage(
            items: cached.items,
            nextBeforeUid: null,
            hasMore: false,
          );
        }
      }
      rethrow;
    }
  }

  Future<MailBody> loadBody(String folderPath, int uid) async {
    final config = _config;
    final epoch = _epoch;
    try {
      final body = await _withConnection(
        (connection) => connection.fetchBody(folderPath, uid),
        retry: true,
      );
      if (config != null && _isCurrentOwner(epoch, config)) {
        await _cache.writeBody(config.email, folderPath, uid, body);
      }
      return body;
    } on MailException catch (error) {
      if (config != null &&
          _isCurrentOwner(epoch, config) &&
          error.isRetryable) {
        final cached = await _cache.readBody(config.email, folderPath, uid);
        if (cached != null && _isCurrentOwner(epoch, config)) return cached;
      }
      rethrow;
    }
  }

  Future<Uint8List> downloadAttachment(
    String folderPath,
    int uid,
    MailAttachment attachment,
  ) async {
    final config = _config;
    final epoch = _epoch;
    try {
      final bytes = await _withConnection(
        (connection) => connection.downloadAttachment(
          folderPath,
          uid,
          attachment.fetchId,
          knownSize: attachment.size,
        ),
        retry: true,
      );
      if (config != null && _isCurrentOwner(epoch, config)) {
        await _cache.writeAttachment(
          config.email,
          folderPath,
          uid,
          attachment.fetchId,
          bytes,
        );
      }
      return bytes;
    } on MailException catch (error) {
      if (config != null &&
          _isCurrentOwner(epoch, config) &&
          error.isRetryable) {
        final cached = await _cache.readAttachment(
          config.email,
          folderPath,
          uid,
          attachment.fetchId,
        );
        if (cached != null && _isCurrentOwner(epoch, config)) return cached;
      }
      rethrow;
    }
  }

  Future<void> setSeen(String folderPath, int uid, bool seen) async {
    await _withConnection(
      (connection) => connection.setSeen(folderPath, uid, seen),
    );
    _bumpRevision();
  }

  /// 发送一封纯文本邮件。
  ///
  /// SMTP 使用独立连接与独立串行队列，不阻塞收信；发送成功后尽力把副本
  /// 追加到服务器「已发送」，副本失败不回滚发送结果。
  Future<MailSendResult> send(MailDraft draft) {
    return _sendSerial(() async {
      await initialize();
      final config = _config;
      if (config == null) throw MailException.notConfigured();
      final validation = draft.validationError;
      if (validation != null) {
        throw MailException(MailErrorKind.rejected, validation);
      }
      await _requirePrivacyAccepted();
      final secret = await _credentials.readSecret(config.email);
      if (secret == null) {
        throw const MailException(
          MailErrorKind.invalidCredentials,
          '请重新输入邮箱密码',
        );
      }
      final receipt = await _sender.send(config, secret, draft);
      final sentCopyStored = await _storeSentCopy(receipt.messageText);
      _bumpRevision();
      return MailSendResult(sentCopyStored: sentCopyStored);
    });
  }

  Future<bool> _storeSentCopy(String messageText) async {
    try {
      return await _withConnection(
        (connection) => connection.appendToSent(messageText),
        retry: false,
      );
    } on Object {
      // 副本写入失败不影响已投递的邮件，页面只提示未保存副本。
      return false;
    }
  }

  Future<T> _sendSerial<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _sendTail = _sendTail
        .then((_) async {
          try {
            completer.complete(await action());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .catchError((Object _) {});
    return completer.future;
  }

  /// 首页焦点使用的轻量未读检查：单独短连接，不复用页面连接。
  Future<int> checkUnread() async {
    await initialize();
    if (!await _isPrivacyAccepted()) return 0;
    final config = _config;
    final epoch = _epoch;
    if (config == null) return 0;
    final secret = await _credentials.readSecret(config.email);
    if (secret == null) return 0;

    MailConnection? connection;
    try {
      connection = await _transport.connect(config, secret);
      final unread = await connection.unreadCount('INBOX');
      if (_isCurrentOwner(epoch, config)) {
        _bumpRevision();
      }
      return unread;
    } finally {
      try {
        await connection?.close();
      } catch (_) {
        // 忽略关闭失败。
      }
    }
  }

  Future<void> signOut() async {
    final init = _initialization;
    if (init != null) {
      try {
        await init;
      } catch (_) {}
    }
    ++_epoch;
    final config = _config ?? await _configStore.read();
    await _dropConnection();
    await _credentials.clear();
    await _configStore.clear();
    if (config != null) {
      await _cache.clear(config.email);
    }
    _config = null;
    _initialization = null;
    state.value = MailSessionState.initial;
    _bumpRevision();
  }

  Future<void> clearCache() async {
    final config = _config;
    if (config == null) return;
    await _cache.clear(config.email);
    _bumpRevision();
  }

  Future<MailCacheStats> cacheStats() async {
    final config = _config;
    if (config == null) return MailCacheStats.empty;
    return _cache.stats(config.email);
  }

  /// 测试用：关闭空闲连接。
  @visibleForTesting
  Future<void> shutdown() => _dropConnection();

  Future<T> _withConnection<T>(
    Future<T> Function(MailConnection connection) action, {
    bool retry = false,
  }) {
    return _serial(() async {
      _pauseIdle();
      try {
        try {
          final connection = await _ensureConnection();
          return await action(connection);
        } on MailException catch (error) {
          if (!retry || !error.isRetryable) rethrow;
          await _dropConnection();
          final connection = await _ensureConnection();
          return action(connection);
        }
      } finally {
        _resumeIdle();
      }
    });
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail
        .then((_) async {
          try {
            completer.complete(await action());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .catchError((Object _) {});
    return completer.future;
  }

  Future<MailConnection> _ensureConnection() async {
    final existing = _connection;
    if (existing != null) return existing;
    await _requirePrivacyAccepted();
    final config = _config;
    if (config == null) throw MailException.notConfigured();
    final epoch = _epoch;
    final expectedEmail = config.email;
    final secret = await _credentials.readSecret(expectedEmail);
    if (secret == null) {
      throw const MailException(MailErrorKind.invalidCredentials, '请重新输入邮箱密码');
    }
    final connection = await _transport.connect(config, secret);
    if (_epoch != epoch || _config?.email != expectedEmail) {
      try {
        await connection.close();
      } catch (_) {
        // 连接可能已断开。
      }
      throw MailException.notConfigured();
    }
    _connection = connection;
    return connection;
  }

  void _pauseIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _resumeIdle() {
    _pauseIdle();
    if (_connection == null || _idleTimeout <= Duration.zero) return;
    _idleTimer = Timer(_idleTimeout, () {
      unawaited(_dropConnection());
    });
  }

  Future<void> _dropConnection() async {
    _pauseIdle();
    final connection = _connection;
    _connection = null;
    if (connection == null) return;
    try {
      await connection.close();
    } catch (_) {
      // 连接可能已断开。
    }
  }

  void _bumpRevision() => revision.value++;
}
