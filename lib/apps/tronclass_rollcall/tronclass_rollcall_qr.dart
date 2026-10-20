import 'dart:convert';

import '../../capabilities/qr_scanner_capability.dart';
import '../../services/service_endpoints.dart';
import 'tronclass_rollcall_models.dart';

class TronclassRollcallQr {
  const TronclassRollcallQr(this.data);
  final Object data;
}

/// Pure decoder; scanned addresses are never fetched or used as API targets.
QrDecodeResult<TronclassRollcallQr> decodeRollcallQr(
  QrDecodedSymbol symbol,
  TronclassRollcall rollcall,
) {
  try {
    final raw = symbol.rawValue.trim();
    Object? decoded;
    if (raw.startsWith('{')) {
      decoded = jsonDecode(raw);
    } else {
      final uri = Uri.parse(raw);
      final base = Uri.parse(CampusServiceEndpoints.courseBase);
      if (uri.hasFragment ||
          uri.userInfo.isNotEmpty ||
          (uri.hasAuthority &&
              (uri.scheme != 'https' ||
                  uri.host != base.host ||
                  uri.port != base.port)) ||
          (!uri.hasAuthority && uri.hasScheme) ||
          (uri.path != '/j' && uri.path != '/scanner-jumper')) {
        return const QrDecodeResult.failure('请扫描当前课程的签到二维码。');
      }
      final plain = uri.queryParameters['_p'];
      if (plain != null) {
        try {
          decoded = jsonDecode(plain);
        } on FormatException {
          /* Try packed form. */
        }
      }
      if (decoded is! Map || decoded.isEmpty) {
        decoded = parsePackedRollcallQr(uri.queryParameters['p'] ?? '');
      }
    }
    if (decoded is! Map ||
        decoded['data'] == null ||
        (decoded['data'] is String && (decoded['data'] as String).isEmpty)) {
      return const QrDecodeResult.failure('二维码不是有效的签到码，请重新扫描。');
    }
    for (final entry
        in {'rollcallId': rollcall.id, 'courseId': rollcall.courseId}.entries) {
      if (decoded.containsKey(entry.key) &&
          rollcallIdentifier(decoded[entry.key]) != entry.value) {
        return const QrDecodeResult.failure('二维码与当前点名不匹配，请重新扫描。');
      }
    }
    return QrDecodeResult.success(
      TronclassRollcallQr(decoded['data'] as Object),
    );
  } on FormatException {
    return const QrDecodeResult.failure('二维码无法识别，请重新扫描。');
  }
}

/// Port of CHURollcallTool's parse_sign_qr_code dictionary/escape format.
Map<String, Object> parsePackedRollcallQr(String text) {
  const keys = [
    'courseId',
    'activityId',
    'activityType',
    'data',
    'rollcallId',
    'groupSetId',
    'accessCode',
    'action',
    'enableGroupRollcall',
    'createUser',
    'joinCourse',
  ];
  const values = {
    '\x1a2': 'classroom-exam',
    '\x1a3': 'feedback',
    '\x1a4': 'vote',
  };
  final result = <String, Object>{};
  for (final segment in text.split('!').where((part) => part.isNotEmpty)) {
    final separator = segment.indexOf('~');
    if (separator < 0) throw const FormatException('Invalid QR segment');
    final key = segment.substring(0, separator);
    final packedKey = int.tryParse(key, radix: 36);
    final name =
        packedKey != null && packedKey >= 0 && packedKey < keys.length
            ? keys[packedKey]
            : key;
    final value = segment.substring(separator + 1);
    if (result.containsKey(name)) {
      throw const FormatException('Duplicate QR key');
    }
    if (value.startsWith('\x1a')) {
      result[name] =
          value == '\x1a1'
              ? true
              : value == '\x1a0'
              ? false
              : values[value] ?? value;
    } else if (value.startsWith('\x10')) {
      final numbers =
          value
              .substring(1)
              .split('.')
              .map((part) => int.parse(part, radix: 36))
              .toList();
      if (numbers.length > 2) throw const FormatException('Invalid QR number');
      result[name] =
          numbers.length == 1
              ? numbers.single
              : double.parse('${numbers[0]}.${numbers[1]}');
    } else {
      result[name] = value.replaceAll('\x1f', '~').replaceAll('\x1e', '!');
    }
  }
  return result;
}
