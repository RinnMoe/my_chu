import '../services/session_storage_support.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'saved_login_credential.dart';
import '../services/channel_resources_session_service.dart';

import '../services/logging/logger.dart';

export '../services/channel_resources_session_service.dart'
    show
        ChannelResourcesAuthState,
        ChannelResourcesSessionErrorType,
        ChannelResourcesSessionException,
        ChannelResourcesSessionStatus,
        ChannelResourcesUser;

typedef ChannelAccountState = ChannelResourcesAuthState;
typedef ChannelAccountStatus = ChannelResourcesSessionStatus;
typedef ChannelAccountErrorType = ChannelResourcesSessionErrorType;
typedef ChannelAccountUser = ChannelResourcesUser;
typedef ChannelAccountException = ChannelResourcesSessionException;

/// Feature-safe response projection. Cookie headers and other transport
/// credentials remain inside [ChannelResourcesSession].
class ChannelAccountHttpResponse {
  const ChannelAccountHttpResponse(
    this.statusCode,
    this.bytes, {
    this.contentType,
  });

  final int statusCode;
  final List<int> bytes;
  final String? contentType;

  String get body => utf8.decode(bytes, allowMalformed: true);
}

/// Host-owned account and session capability for the independent QQ Channel
/// account. Future features can reuse this session without handling credentials.
class ChannelAccountCapability {
  ChannelAccountCapability(
    this._session, {
    SavedLoginCredentialCapability? savedCredential,
  }) : _savedCredential =
           savedCredential ??
           SavedLoginCredentialCapability(scope: 'channel_resources');

  static const String logoutConfirmationMessage = '这只会退出校园频道账号，不会影响统一身份认证登录。';

  static final ChannelAccountCapability current = ChannelAccountCapability(
    ChannelResourcesSessionService.current,
  );

  final ChannelResourcesSession _session;
  final SavedLoginCredentialCapability _savedCredential;

  ChannelAccountUser? get user => _session.user;
  bool get hasIdentity => _session.hasIdentity;
  ChannelAccountState get state => _session.authState;
  ValueListenable<ChannelAccountState> get stateListenable =>
      _session.authStateListenable;

  Future<ChannelAccountState> restore() => _session.restore();

  Future<SavedLoginCredential?> readRememberedCredential() =>
      _savedCredential.read();

  Future<void> _updateRememberedCredential(
    int revision,
    Future<void> Function() update,
  ) =>
      AccountSessionStorageQueue.run('host.channel.saved-credential', () async {
        if (_session.revision == revision) await update();
      });

  Future<void> clearRememberedCredential() =>
      _updateRememberedCredential(_session.revision, _savedCredential.clear);

  Future<ChannelAccountState> login({
    required String username,
    required String password,
    bool rememberPassword = false,
  }) async {
    final state = await _session.login(
      username: username,
      password: password,
      rememberSession: rememberPassword,
    );
    if (state.isAuthenticated && identical(_session.user, state.user)) {
      await _updateRememberedCredential(_session.revision, () async {
        if (rememberPassword) {
          await _savedCredential.save(username, password);
        } else {
          await _savedCredential.clear();
        }
      });
    }
    return state;
  }

  Future<void> logout() async {
    final pending = _session.logout();
    final revision = _session.revision;
    try {
      await pending;
    } finally {
      await _updateRememberedCredential(revision, _savedCredential.clear);
    }
  }

  Future<void> changePassword({
    String? oldPassword,
    required String newPassword,
    String? newUsername,
  }) async {
    await _session.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
      newUsername: newUsername,
    );
    if (!_session.authState.isAuthenticated) {
      await _updateRememberedCredential(
        _session.revision,
        _savedCredential.clear,
      );
    }
  }

  Future<ChannelAccountHttpResponse> request(
    String method,
    String path, {
    Map<String, String> queryParameters = const {},
    Object? body,
  }) async {
    final uri = Uri.tryParse(path);
    String? decodedPath;
    try {
      if (uri != null) decodedPath = Uri.decodeComponent(uri.path);
    } on FormatException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      decodedPath = null;
    }
    final pathSegments = decodedPath?.split('/') ?? const <String>[];
    if (uri == null ||
        decodedPath == null ||
        pathSegments.isEmpty ||
        pathSegments.contains('auth')) {
      throw const ChannelAccountException(ChannelAccountErrorType.malformed);
    }
    final response = await _session.request(
      method,
      path,
      queryParameters: queryParameters,
      body: body,
    );
    return ChannelAccountHttpResponse(
      response.statusCode,
      response.bytes,
      contentType: response.contentType,
    );
  }
}
