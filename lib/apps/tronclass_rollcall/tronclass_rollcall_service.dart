import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../services/account_network_session_service.dart';
import '../../services/campus_session.dart';
import '../../services/host_auth_state.dart';
import '../../services/service_endpoints.dart';
import 'tronclass_rollcall_models.dart';
import 'tronclass_rollcall_qr.dart';

typedef RollcallRequest =
    Future<AccountNetworkResponse> Function(
      String method,
      String path,
      Object? body,
    );

class TronclassRollcallService {
  TronclassRollcallService({RollcallRequest? request})
    : _request = request ?? _send;
  final RollcallRequest _request;
  static final _client = CampusSession.client(CampusServices.courseOnline);
  static const _timeout = Duration(seconds: 12);

  static Future<AccountNetworkResponse> _send(
    String method,
    String path,
    Object? body,
  ) => _client.request(
    method,
    '${CampusServiceEndpoints.courseBase}$path',
    body: body,
    extraHeaders: const {
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36 TronClass/Common',
    },
    requestTimeout: _timeout,
    responseTimeout: _timeout,
    throwOnHttpError: false,
    // CampusSession also forbids retries for PUT. Never replay an answer.
    autoExchangeService: method == 'GET',
  );

  Future<List<TronclassRollcall>> fetchActive() async {
    try {
      final response = await _request('GET', '/api/radar/rollcalls', null);
      final json = _decode(response);
      return TronclassRollcall.parseList(json);
    } on RollcallException {
      rethrow;
    } on CampusAuthenticationRequired {
      throw const RollcallException(RollcallFailure.authentication);
    } on FormatException {
      throw const RollcallException(RollcallFailure.invalidResponse);
    }
  }

  Future<void> answerNumber(TronclassRollcall rollcall, String code) {
    if (rollcall.type != TronclassRollcallType.number ||
        !RegExp(r'^[0-9]{4}$').hasMatch(code)) {
      throw const RollcallException(RollcallFailure.rejected);
    }
    return _answer(rollcall.id, 'answer_number_rollcall', {
      'deviceId': _uuid(),
      'numberCode': code,
    });
  }

  Future<void> answerQr(TronclassRollcall rollcall, TronclassRollcallQr qr) {
    if (rollcall.type != TronclassRollcallType.qr) {
      throw const RollcallException(RollcallFailure.rejected);
    }
    return _answer(rollcall.id, 'answer_qr_rollcall', {
      'data': qr.data,
      'deviceId': _uuid(),
    });
  }

  Future<void> _answer(
    String id,
    String action,
    Map<String, Object> body,
  ) async {
    if (rollcallIdentifier(id) == null) {
      throw const RollcallException(RollcallFailure.rejected);
    }
    try {
      final response = await _request('PUT', '/api/rollcall/$id/$action', body);
      final result = _decode(response, answer: true);
      if (result is Map) {
        final status = result['status'];
        if (result['success'] == false ||
            result['ok'] == false ||
            status == false ||
            (result['error'] != null &&
                result['error'] != false &&
                result['error'] != '') ||
            (status is String &&
                RegExp(
                  r'error|fail|invalid|wrong|denied',
                  caseSensitive: false,
                ).hasMatch(status))) {
          throw const RollcallException(RollcallFailure.rejected);
        }
      }
    } on TimeoutException {
      throw const RollcallException(RollcallFailure.uncertain);
    } on SocketException {
      throw const RollcallException(RollcallFailure.uncertain);
    } on HttpException {
      throw const RollcallException(RollcallFailure.uncertain);
    } on CampusAuthenticationRequired {
      throw const RollcallException(RollcallFailure.authentication);
    } on FormatException {
      throw const RollcallException(RollcallFailure.uncertain);
    }
  }

  static Object? _decode(
    AccountNetworkResponse response, {
    bool answer = false,
  }) {
    final text = response.body.trim();
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        (response.statusCode >= 300 && response.statusCode < 400) ||
        text.startsWith('<')) {
      throw const RollcallException(RollcallFailure.authentication);
    }
    if (response.statusCode == 410) {
      throw const RollcallException(RollcallFailure.ended);
    }
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      if (response.statusCode == 200) rethrow;
    }
    if (answer && decoded is Map) {
      final state = decoded['rollcall_status'] ?? decoded['status'];
      final error = decoded['error'];
      if (const ['ended', 'expired', 'closed', 'finished'].contains(state) ||
          const ['rollcall_ended', 'rollcall_expired'].contains(error) ||
          decoded['is_expired'] == true) {
        throw const RollcallException(RollcallFailure.ended);
      }
    }
    if (response.statusCode != 200) {
      throw RollcallException(
        answer
            ? (response.statusCode >= 500
                ? RollcallFailure.uncertain
                : RollcallFailure.rejected)
            : RollcallFailure.network,
      );
    }
    if (answer && text.isEmpty) return null;
    if (decoded is! Map) throw const FormatException('Invalid response');
    return decoded;
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
