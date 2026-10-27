import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
    Future<void>? abortTrigger,
  }) async {
    if (_closed) throw const PublicHttpException('请求已停止。');
    final expired = Completer<void>();
    final limit = timeout ?? defaultTimeout;
    final timer = Timer(limit, () => expired.complete());
    try {
      final request = http.AbortableRequest(
          method,
          uri,
          abortTrigger:
              abortTrigger == null
                  ? expired.future
                  : Future.any([expired.future, abortTrigger]),
        )
        // Never send this feature's Bearer credential through a redirect.
        ..followRedirects = false;
      if (headers != null) request.headers.addAll(headers);
      if (body != null) request.body = body;
      return await (() async =>
              http.Response.fromStream(await _transport.send(request)))()
          .timeout(limit);
    } on TimeoutException {
      throw const PublicHttpException('请求超时，请稍后重试。');
    } catch (_) {
      throw const PublicHttpException('网络请求失败，请稍后重试。');
    } finally {
      timer.cancel();
    }
  }

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
