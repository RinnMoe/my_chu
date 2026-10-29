import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_remote_services_service.dart';
import 'privacy_agreement_service.dart';
import 'public_http_client.dart';
import 'supabase/supabase_privacy_gate.dart';
import 'supabase/supabase_project_config.dart';

/// Optional public feedback. This identity is separate from all campus sessions.
class FeedbackCommunityService {
  FeedbackCommunityService({
    SupabaseEndpointConfig? config,
    PublicHttpClient? httpClient,
    Future<bool> Function()? allowed,
    Future<String?> Function(String)? readSession,
    Future<void> Function(String, String)? writeSession,
    int Function()? epoch,
  }) : _config = config ?? SupabaseEndpointConfig.fromEnvironment(),
       _http = httpClient ?? PublicHttpClient(),
       _ownsHttp = httpClient == null,
       _allowed = allowed ?? _defaultAllowed,
       _read =
           readSession ??
           ((key) => const FlutterSecureStorage().read(key: key)),
       _write =
           writeSession ??
           ((key, value) =>
               const FlutterSecureStorage().write(key: key, value: value)),
       _epoch =
           epoch ??
           (() =>
               PrivacyAgreementService.revision.value * 1000000 +
               AppRemoteServicesService.revision.value);

  static const requiredAgreementVersion =
      SupabasePrivacyGate.requiredAgreementVersion;
  static Future<bool> _defaultAllowed() async =>
      await SupabasePrivacyGate.isAccepted() &&
      await AppRemoteServicesService.isEnabled();

  final SupabaseEndpointConfig? _config;
  final PublicHttpClient _http;
  final bool _ownsHttp;
  final Future<bool> Function() _allowed;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final int Function() _epoch;
  Future<Map<String, dynamic>?>? _identityFlight;
  bool _closed = false;

  static String requestId() {
    final random = Random.secure();
    final b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<void> _check(int epoch) async {
    if (_closed ||
        _config == null ||
        epoch != _epoch() ||
        !await _allowed() ||
        epoch != _epoch() ||
        _closed) {
      throw const CommunityException('请先同意新版用户协议并开启在线功能。');
    }
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Object body,
    int epoch, {
    String? token,
  }) async {
    await _check(epoch);
    final response = await _http.postJson(
      uri,
      body: body,
      headers: {
        ..._config!.authHeaders,
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    await _check(epoch);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CommunityException(
        response.statusCode == 429 ? '操作过于频繁，请稍后再试。' : '请求未完成，请刷新后重试。',
        uncertain: response.statusCode >= 500,
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on Object {
      throw const CommunityException('响应未能确认，请刷新后重试。', uncertain: true);
    }
  }

  Future<Map<String, dynamic>?> _identity({
    required bool create,
    required int epoch,
  }) async {
    // Reading and refreshing also share a single flight. A read never creates an identity.
    final existing = _identityFlight;
    if (existing != null) {
      final identity = await existing;
      if (identity != null || !create) return identity;
      if (identical(_identityFlight, existing)) _identityFlight = null;
      return _identity(create: true, epoch: epoch);
    }
    final flight = _loadIdentity(create, epoch);
    _identityFlight = flight;
    try {
      return await flight;
    } finally {
      if (identical(_identityFlight, flight)) _identityFlight = null;
    }
  }

  Future<Map<String, dynamic>?> _loadIdentity(bool create, int epoch) async {
    await _check(epoch);
    final key =
        'mychu.community.identity.v1.${sha256.convert(utf8.encode(_config!.baseUrl.toString()))}';
    final saved = await _read(key);
    await _check(epoch);
    Map<String, dynamic>? session;
    if (saved != null) {
      try {
        session = jsonDecode(saved) as Map<String, dynamic>;
      } on Object {
        throw const CommunityException('无法读取参与身份，请联系开发者。');
      }
      if (session['access_token'] is! String ||
          session['refresh_token'] is! String ||
          session['expires_at'] is! int) {
        throw const CommunityException('参与身份异常，请联系开发者。');
      }
      if ((session['expires_at'] as int) >
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60) {
        return session;
      }
    } else if (!create) {
      return null;
    }
    final fresh = await _post(
      _config.baseUrl.replace(
        path: session == null ? '/auth/v1/signup' : '/auth/v1/token',
        queryParameters:
            session == null ? null : {'grant_type': 'refresh_token'},
      ),
      session == null
          ? <String, Object>{}
          : {'refresh_token': session['refresh_token']},
      epoch,
    );
    if (fresh['access_token'] is! String ||
        fresh['refresh_token'] is! String ||
        fresh['user'] is! Map ||
        (fresh['user'] as Map)['is_anonymous'] != true) {
      throw const CommunityException('暂时无法参与，请稍后重试。');
    }
    final value = {
      'access_token': fresh['access_token'],
      'refresh_token': fresh['refresh_token'],
      'expires_at':
          DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          (fresh['expires_in'] as int? ?? 3600),
    };
    await _check(epoch);
    await _write(key, jsonEncode(value));
    await _check(epoch);
    return value;
  }

  Future<Map<String, dynamic>> feed({
    String? proposal,
    int offset = 0,
    bool mine = false,
  }) async {
    final epoch = _epoch();
    await _check(epoch);
    final identity = await _identity(create: false, epoch: epoch);
    return _post(
      _config!.restUri('rpc/community_feed'),
      {'p_proposal': proposal, 'p_offset': offset, 'p_mine': mine},
      epoch,
      token: identity?['access_token'] as String?,
    );
  }

  Future<void> write({
    required String action,
    required String id,
    String? proposal,
    String title = '',
    String body = '',
    bool supported = true,
  }) async {
    final epoch = _epoch();
    await _check(epoch);
    final identity = await _identity(create: true, epoch: epoch);
    try {
      final result = await _post(
        _config!.restUri('rpc/community_write'),
        {
          'p_action': action,
          'p_id': id,
          'p_proposal': proposal,
          'p_title': title,
          'p_body': body,
          'p_supported': supported,
        },
        epoch,
        token: identity!['access_token'] as String,
      );
      if (result['ok'] != true) throw const CommunityException('操作过于频繁，请稍后再试。');
    } on PublicHttpException {
      throw const CommunityException('提交结果未知，请刷新后确认。', uncertain: true);
    }
  }

  void close() {
    _closed = true;
    if (_ownsHttp) _http.close();
  }
}

class CommunityException implements Exception {
  const CommunityException(this.message, {this.uncertain = false});
  final String message;
  final bool uncertain;
  @override
  String toString() => message;
}
