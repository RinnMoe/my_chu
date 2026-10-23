import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'failure_details.dart';
export 'failure_details.dart' show classifyHttpFailure;

/// Extract structured categories while the original object is available.
/// Never inspect messages, URLs, response bodies, platform details or stacks.
FailureReason classifyFailure(
  Object error, {
  int? statusCode,
  bool? renderProcessCrashed,
}) {
  if (renderProcessCrashed != null) {
    return renderProcessCrashed
        ? FailureReason.rendererCrashed
        : FailureReason.rendererExited;
  }
  // Locally generated responses must not mask a known host-session cause.
  if (error is ClassifiedFailure &&
      error.failureReason != FailureReason.unexpected) {
    return error.failureReason;
  }
  if (error is DioException && error.type == DioExceptionType.cancel) {
    return FailureReason.cancelled;
  }
  final status =
      statusCode ??
      (error is DioException ? error.response?.statusCode : null) ??
      (error is WebResourceResponse ? error.statusCode : null);
  final httpReason = classifyHttpFailure(status);
  if (httpReason != null) return httpReason;
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => FailureReason.timeout,
      DioExceptionType.badCertificate => FailureReason.tls,
      DioExceptionType.connectionError =>
        error.error is TlsException
            ? FailureReason.tls
            : FailureReason.connection,
      DioExceptionType.cancel => FailureReason.cancelled,
      DioExceptionType.badResponse => FailureReason.httpTransport,
      DioExceptionType.unknown =>
        error.error != null && error.error is! DioException
            ? classifyFailure(error.error!)
            : FailureReason.unexpected,
    };
  }
  if (error is WebResourceError) {
    final type = error.type;
    if (type == WebResourceErrorType.CANCELLED ||
        type == WebResourceErrorType.USER_CANCELLED_AUTHENTICATION) {
      return FailureReason.cancelled;
    }
    if (type == WebResourceErrorType.TIMEOUT) return FailureReason.timeout;
    if (type == WebResourceErrorType.HOST_LOOKUP) return FailureReason.dns;
    if (type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST ||
        type == WebResourceErrorType.IO ||
        type == WebResourceErrorType.NETWORK_CONNECTION_LOST ||
        type == WebResourceErrorType.NOT_CONNECTED_TO_INTERNET ||
        type == WebResourceErrorType.SERVER_UNREACHABLE ||
        type == WebResourceErrorType.CONNECTION_ABORTED ||
        type == WebResourceErrorType.RESET) {
      return FailureReason.connection;
    }
    if ({
      WebResourceErrorType.FAILED_SSL_HANDSHAKE,
      WebResourceErrorType.SECURE_CONNECTION_FAILED,
      WebResourceErrorType.SERVER_CERTIFICATE_HAS_BAD_DATE,
      WebResourceErrorType.SERVER_CERTIFICATE_UNTRUSTED,
      WebResourceErrorType.SERVER_CERTIFICATE_HAS_UNKNOWN_ROOT,
      WebResourceErrorType.SERVER_CERTIFICATE_NOT_YET_VALID,
      WebResourceErrorType.CLIENT_CERTIFICATE_REJECTED,
      WebResourceErrorType.CLIENT_CERTIFICATE_REQUIRED,
    }.contains(type)) {
      return FailureReason.tls;
    }
    if (type == WebResourceErrorType.TOO_MANY_REQUESTS) {
      return FailureReason.httpRateLimited;
    }
    if (type == WebResourceErrorType.TOO_MANY_REDIRECTS) {
      return FailureReason.redirectLoop;
    }
    if (type == WebResourceErrorType.UNSUPPORTED_SCHEME ||
        type == WebResourceErrorType.BAD_URL ||
        type == WebResourceErrorType.UNSUPPORTED_AUTH_SCHEME) {
      return FailureReason.unsupportedResource;
    }
    if (type == WebResourceErrorType.USER_AUTHENTICATION_REQUIRED ||
        type == WebResourceErrorType.USER_AUTHENTICATION_FAILED ||
        type == WebResourceErrorType.PROXY_AUTHENTICATION) {
      return FailureReason.authentication;
    }
    if ({
      WebResourceErrorType.CANNOT_DECODE_RAW_DATA,
      WebResourceErrorType.CANNOT_DECODE_CONTENT_DATA,
      WebResourceErrorType.CANNOT_PARSE_RESPONSE,
      WebResourceErrorType.BAD_SERVER_RESPONSE,
    }.contains(type)) {
      return FailureReason.malformedResponse;
    }
    return FailureReason.unexpected;
  }
  if (error is TimeoutException) return FailureReason.timeout;
  if (error is TlsException) return FailureReason.tls;
  if (error is SocketException) return FailureReason.connection;
  if (error is http.ClientException) return FailureReason.httpTransport;
  if (error is HttpException) return FailureReason.httpTransport;
  if (error is FormatException) return FailureReason.malformedResponse;
  if (error is MissingPluginException) return FailureReason.pluginUnavailable;
  if (error is PlatformException) return FailureReason.platform;
  if (error is FlutterError) return FailureReason.framework;
  if (error is TypeError) return FailureReason.typeMismatch;
  if (error is AssertionError) return FailureReason.assertion;
  if (error is StateError) return FailureReason.invalidState;
  if (error is ArgumentError) return FailureReason.invalidArgument;
  return FailureReason.unexpected;
}
