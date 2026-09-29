import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Builds the signed JSON envelope used by `app.chd.edu.cn` mobile campus
/// APIs. The captured protocol is deterministic:
///
/// `sign = md5("appKey=<appKey>&param=<param>&secure=0&time=<time>")`.
class MobileCampusRequestSigner {
  MobileCampusRequestSigner._();

  static const appKey = 'GiITvn';

  static Map<String, Object?> signedBody(
    Map<String, Object?> param, {
    DateTime? now,
  }) {
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final paramJson = jsonEncode(param);
    final canonical = 'appKey=$appKey&param=$paramJson&secure=0&time=$time';
    final sign = md5.convert(utf8.encode(canonical)).toString();
    return {
      'appKey': appKey,
      'param': paramJson,
      'time': time,
      'secure': 0,
      'sign': sign,
    };
  }
}
