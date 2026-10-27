import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mychu/apps/charging_pile/charging_pile_models.dart';
import 'package:mychu/apps/charging_pile/charging_pile_service.dart';
import 'package:mychu/services/public_http_client.dart';

ChargingPileService _service({
  required http.Client client,
  DateTime Function()? now,
}) => ChargingPileService(
    httpClient: PublicHttpClient(client: client, ownsClient: false),
    now: now,
  );

ChargingPileDevice _device(String id) => ChargingPileDevice(
  id: id,
  code: id,
  name: '测试 $id 号桩',
  location: '测试区域',
);

String _jwt({required int expiresAt}) {
  String encode(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({
    'exp': expiresAt,
  })}.${encode({'sig': 'test'})}';
}

void main() {
  group('ChargingPileService.extractToken', () {
    test('extracts a raw JWT', () {
      final token = _jwt(expiresAt: 2000000000);
      expect(ChargingPileService.extractToken(token), token);
    });

    test('prefers an Authorization field', () {
      final token = _jwt(expiresAt: 2000000000);
      final input =
          'Cookie: x=eyJfake.fake.fake\nAuthorization: Bearer $token\n';
      expect(ChargingPileService.extractToken(input), token);
    });

    test('extracts from cURL and URL forms', () {
      final token = _jwt(expiresAt: 2000000000);
      expect(
        ChargingPileService.extractToken("curl -H 'token: $token' x"),
        token,
      );
      expect(
        ChargingPileService.extractToken('https://example.com/#t=$token'),
        token,
      );
    });

    test('rejects non-JWT input', () {
      expect(ChargingPileService.normalizeToken('Bearer not-a-jwt').error, isNotNull);
    });
  });

  group('ChargingPileService.tokenInfo', () {
    test('reports expiry states', () {
      final expired = ChargingPileService.tokenInfo(
        _jwt(expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10),
      );
      expect(expired.state, ChargingPileTokenState.expired);

      final soon = ChargingPileService.tokenInfo(
        _jwt(expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600),
      );
      expect(soon.state, ChargingPileTokenState.expiringSoon);

      final valid = ChargingPileService.tokenInfo(
        _jwt(expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 864000),
      );
      expect(valid.state, ChargingPileTokenState.valid);
    });
  });

  group('ChargingPileService.refresh', () {
    test('parses free and occupied slots', () async {
      final token = _jwt(expiresAt: 2000000000);
      final service = _service(
        client: MockClient((request) async {
          expect(request.url.toString(), contains('/api/rent/scan-code'));
          expect(request.headers['Authorization'], 'Bearer $token');
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': {
                'shopName': '测试',
                'slotsData': [
                  {'slotId': 2, 'status': 1},
                  {'slotId': 1, 'status': 0},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await service.refresh(
        devices: [_device('A')],
        token: token,
      );
      expect(result.failures.map((f) => f.message), isEmpty);
      expect(result.statuses, hasLength(1));
      final status = result.statuses.single;
      expect(status.slots.map((slot) => slot.slotId), [1, 2]);
      expect(status.slots.map((slot) => slot.free), [true, false]);
      expect(status.freeSlots, 1);
    });

    test('converts API 401 to an auth failure and skips the rest', () async {
      final token = _jwt(expiresAt: 2000000000);
      var requests = 0;
      final service = _service(
        client: MockClient((request) async {
          requests++;
          return http.Response(jsonEncode({'code': 401, 'message': '过期'}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      final result = await service.refresh(
        devices: List.generate(10, (index) => _device('D$index')),
        token: token,
      );
      expect(result.authFailed, isTrue);
      expect(requests, lessThan(10));
      expect(result.failures.every((failure) => failure.authFailure), isTrue);
    });

    test('retries transient failures once', () async {
      final token = _jwt(expiresAt: 2000000000);
      var attempts = 0;
      final service = _service(
        client: MockClient((request) async {
          attempts++;
          if (attempts == 1) {
            throw http.ClientException('network down');
          }
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': {
                'slotsData': [
                  {'slotId': 1, 'status': 0},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await service.refresh(devices: [_device('A')], token: token);
      expect(attempts, 2);
      expect(result.statuses, hasLength(1));
    });

    test('enforces the refresh interval', () async {
      final token = _jwt(expiresAt: 2000000000);
      var current = DateTime(2026, 10, 26, 12, 0, 0);
      final service = _service(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': 200,
              'data': {
                'slotsData': [
                  {'slotId': 1, 'status': 0},
                ],
              },
            }),
            200,
          ),
        ),
        now: () => current,
      );

      await service.refresh(devices: [_device('A')], token: token);
      expect(service.shouldRefresh(), isFalse);
      expect(service.timeUntilNextRefresh, const Duration(seconds: 60));

      current = current.add(const Duration(seconds: 61));
      expect(service.shouldRefresh(), isTrue);
    });

    test('uses bounded concurrency', () async {
      final token = _jwt(expiresAt: 2000000000);
      var active = 0;
      var maxActive = 0;
      final service = _service(
        client: MockClient((request) async {
          active++;
          maxActive = active > maxActive ? active : maxActive;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': {
                'slotsData': [
                  {'slotId': 1, 'status': 0},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await service.refresh(
        devices: List.generate(10, (index) => _device('C$index')),
        token: token,
      );
      expect(result.statuses, hasLength(10));
      expect(maxActive, lessThanOrEqualTo(6));
    });
  });
}
