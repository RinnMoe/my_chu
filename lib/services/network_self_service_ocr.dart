import 'package:flutter/foundation.dart';

import 'captcha_ocr_service.dart';

/// Device-local OCR bridge for the four-digit network self-service captcha.
///
/// The native implementations receive only the image bytes and return a
/// normalized candidate. They do not perform network access or receive any
/// account/session values.
class NetworkSelfServiceOcr {
  NetworkSelfServiceOcr._();

  /// Test seam for the parser and authentication state machine.
  @visibleForTesting
  static Future<String?> Function(Uint8List bytes)? debugRecognizer;

  static Future<String?> recognize(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    final override = debugRecognizer;
    if (override != null) return _normalize(await override(bytes));
    try {
      return _normalize(await CaptchaOcrService.instance.recognize(bytes));
    } catch (_) {
      return null;
    }
  }

  /// Keeps only the server's expected four ASCII digits.
  @visibleForTesting
  static String? normalize(Object? value) => _normalize(value);

  static String? _normalize(Object? value) {
    final text = value?.toString().trim() ?? '';
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^\d{4}$').hasMatch(compact) ? compact : null;
  }
}
