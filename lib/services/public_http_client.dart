import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 公开 HTTP 请求失败（超时、网络错误或服务端异常状态）。
class PublicHttpException implements Exception {
  final String message;

  /// 服务端返回的 HTTP 状态码；网络层失败时为 null。
  final int? statusCode;

  const PublicHttpException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class PublicHttpDownloadResponse {
  final int statusCode;
  final int? contentLength;

  const PublicHttpDownloadResponse({
    required this.statusCode,
    this.contentLength,
  });
}

/// 面向“公开、免登录”HTTP 服务的共享客户端。
///
/// 现有 `WeatherService` / `IpStatusService` 与 Fenfa 等无凭证公开接口统一
/// 走本客户端，与账号会话层（`CampusSession`）完全隔离：不携带 Cookie、不依赖
/// 登录态，也不参与凭证换票。
class PublicHttpClient {
  PublicHttpClient({
    http.Client? client,
    bool? ownsClient,
    this.defaultTimeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _ownsClient = ownsClient ?? client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration defaultTimeout;
  bool _closed = false;

  /// GET 请求；超时或网络错误统一抛 [PublicHttpException]。
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    _ensureOpen();
    try {
      return await _client
          .get(uri, headers: headers)
          .timeout(timeout ?? defaultTimeout);
    } on TimeoutException {
      throw const PublicHttpException('请求超时，请稍后重试。');
    } catch (_) {
      throw const PublicHttpException('网络请求失败，请稍后重试。');
    }
  }

  /// Streams a public GET response into [destination]. A single transient
  /// retry is allowed for a safe read, and each attempt opens the file in
  /// write mode so a retry cannot append to a partial response.
  Future<PublicHttpDownloadResponse> downloadToFile(
    Uri uri, {
    required File destination,
    Map<String, String>? headers,
    Duration? requestTimeout,
    Duration? responseTimeout,
    bool followRedirects = true,
    void Function(int receivedBytes, int? totalBytes, int attempt)? onProgress,
  }) async {
    _ensureOpen();
    var attempt = 1;
    while (true) {
      try {
        final response = await _downloadAttempt(
          uri,
          destination: destination,
          headers: headers,
          requestTimeout: requestTimeout,
          responseTimeout: responseTimeout,
          followRedirects: followRedirects,
          attempt: attempt,
          onProgress: onProgress,
        );
        if (response.statusCode < 500 || attempt > 1) return response;
      } on PublicHttpException {
        if (attempt > 1) rethrow;
      }
      attempt++;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<PublicHttpDownloadResponse> _downloadAttempt(
    Uri uri, {
    required File destination,
    required Map<String, String>? headers,
    required Duration? requestTimeout,
    required Duration? responseTimeout,
    required bool followRedirects,
    required int attempt,
    required void Function(int receivedBytes, int? totalBytes, int attempt)?
    onProgress,
  }) async {
    IOSink? sink;
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = followRedirects;
      if (headers != null) request.headers.addAll(headers);
      final response = await _client
          .send(request)
          .timeout(requestTimeout ?? defaultTimeout);
      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      sink = destination.openWrite(mode: FileMode.write);
      onProgress?.call(0, totalBytes, attempt);
      await for (final chunk in response.stream.timeout(
        responseTimeout ?? requestTimeout ?? defaultTimeout,
      )) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes, attempt);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return PublicHttpDownloadResponse(
        statusCode: response.statusCode,
        contentLength: totalBytes,
      );
    } on TimeoutException {
      await sink?.close();
      throw const PublicHttpException('请求超时，请稍后重试。');
    } catch (_) {
      await sink?.close();
      throw const PublicHttpException('网络请求失败，请稍后重试。');
    }
  }

  /// POST JSON 请求；超时或网络错误统一抛 [PublicHttpException]。
  Future<http.Response> postJson(
    Uri uri, {
    required Object body,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    _ensureOpen();
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      ...?headers,
    };
    try {
      return await _client
          .post(uri, headers: requestHeaders, body: jsonEncode(body))
          .timeout(timeout ?? defaultTimeout);
    } on TimeoutException {
      throw const PublicHttpException('请求超时，请稍后重试。');
    } catch (_) {
      throw const PublicHttpException('网络请求失败，请稍后重试。');
    }
  }

  /// 解码 JSON 对象；空内容 / 非 JSON / 非对象抛 [FormatException]。
  static Map<String, dynamic> decodeJsonMap(String body) {
    final text = body.trim();
    if (text.isEmpty) throw const FormatException('接口未返回内容');
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('接口未返回 JSON 对象');
    }
    return decoded;
  }

  /// Releases the underlying connection pool when this wrapper owns it.
  ///
  /// Injected clients remain caller-owned unless [ownsClient] was explicitly
  /// set to true at construction time.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('PublicHttpClient is closed');
  }
}
