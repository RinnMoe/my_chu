import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/failure_details.dart';
import '../../services/public_http_client.dart';
export '../../services/public_http_client.dart' show PublicHttpException;

/// Feature-local third-party transport. The existing shared client contract and
/// safe exceptions are reused without adding charging-specific host behavior.
class ChargingPileHttpClient extends PublicHttpClient {
  ChargingPileHttpClient({
    http.Client? client,
    bool? ownsClient,
    Duration defaultTimeout = const Duration(seconds: 8),
  }) : this._(
         client ?? http.Client(),
         ownsClient ?? client == null,
         defaultTimeout,
       );

  ChargingPileHttpClient._(
    http.Client transport,
    bool ownsTransport,
    Duration timeout,
  ) : _transport = transport,
      _ownsTransport = ownsTransport,
      super(client: transport, ownsClient: false, defaultTimeout: timeout);

  final http.Client _transport;
  final bool _ownsTransport;
  bool _closed = false;

  @override
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? abortTrigger,
  }) => _send(
    'GET',
    uri,
    headers: headers,
    timeout: timeout,
    abortTrigger: abortTrigger,
  );

  @override
  Future<http.Response> postJson(
    Uri uri, {
    required Object body,
    Map<String, String>? headers,
    Duration? timeout,
    bool followRedirects = false,
    Future<void>? abortTrigger,
  }) => _send(
    'POST',
    uri,
    body: jsonEncode(body),
    timeout: timeout,
    followRedirects: followRedirects,
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      ...?headers,
    },
    abortTrigger: abortTrigger,
  );

  Future<http.Response> _send(
    String method,
    Uri uri, {
    String? body,
    Map<String, String>? headers,
    Duration? timeout,
    bool followRedirects = false,
    Future<void>? abortTrigger,
  }) async {
    if (_closed) throw _cancelled();
    final expired = Completer<void>();
    final limit = timeout ?? defaultTimeout;
    FailureReason? abortReason;
    void abort(FailureReason reason) {
      if (expired.isCompleted) return;
      abortReason = reason;
      expired.complete();
    }

    final timer = Timer(limit, () => abort(FailureReason.timeout));
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then<void>(
          (_) => abort(FailureReason.cancelled),
          onError: (Object _) => abort(FailureReason.cancelled),
        ),
      );
    }
    final authenticated =
        headers?.keys.any((name) => name.toLowerCase() == 'authorization') ??
        false;
    try {
      final request = http.AbortableRequest(
          method,
          uri,
          abortTrigger: expired.future,
        )
        // Never send this feature's Bearer credential through a redirect.
        ..followRedirects = followRedirects && !authenticated;
      if (headers != null) request.headers.addAll(headers);
      if (body != null) request.body = body;
      return await (() async =>
              http.Response.fromStream(await _transport.send(request)))()
          .timeout(limit);
    } on TimeoutException {
      throw abortReason == FailureReason.cancelled ? _cancelled() : _timedOut();
    } on http.RequestAbortedException {
      throw abortReason == FailureReason.timeout ? _timedOut() : _cancelled();
    } catch (_) {
      if (abortReason == FailureReason.cancelled || _closed) throw _cancelled();
      if (abortReason == FailureReason.timeout) throw _timedOut();
      throw const PublicHttpException(
        '网络请求失败，请稍后重试。',
        reason: FailureReason.httpTransport,
      );
    } finally {
      timer.cancel();
    }
  }

  static PublicHttpException _timedOut() =>
      const PublicHttpException('请求超时，请稍后重试。', reason: FailureReason.timeout);

  static PublicHttpException _cancelled() =>
      const PublicHttpException('请求已停止。', reason: FailureReason.cancelled);

  static Map<String, dynamic> decodeJsonMap(String body) =>
      PublicHttpClient.decodeJsonMap(body);

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    super.close();
    if (_ownsTransport) _transport.close();
  }
}
