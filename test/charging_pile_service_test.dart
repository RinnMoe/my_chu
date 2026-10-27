import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mychu/apps/charging_pile/charging_pile_page.dart';
import 'package:mychu/charging_piles/charging_pile_api_client.dart';
import 'package:mychu/charging_piles/charging_pile_catalog.dart';
import 'package:mychu/charging_piles/charging_pile_models.dart';
import 'package:mychu/charging_piles/charging_pile_repository.dart';
import 'package:mychu/services/charging_credential_service.dart';
import 'package:mychu/services/privacy_agreement_service.dart';
import 'package:mychu/services/public_http_client.dart';

final _clock = DateTime.utc(2026, 10, 27);
String _jwt(String marker, {int exp = 4102444800}) =>
    '${base64Url.encode(utf8.encode('{"alg":"none"}'))}.'
    '${base64Url.encode(utf8.encode(jsonEncode({'exp': exp, 'marker': marker})))}.fixture';
String _record(String token, int updatedAt, {bool rejected = false}) =>
    jsonEncode({
      'version': 2,
      'token': token,
      'updatedAt': updatedAt,
      'rejected': rejected,
    });
http.Response _box(int stamp, String token) => http.Response(
  jsonEncode({'ok': true, 'exists': true, 'updatedAt': stamp, 'data': token}),
  200,
);
http.Response _slots({Object? data, int code = 200}) => http.Response(
  jsonEncode({
    'code': code,
    'data':
        data ??
        {
          'slotsData': [
            {'slotId': 3, 'status': 5},
            {'slotId': '1', 'status': '0'},
            {'slotId': 2, 'status': 1},
          ],
        },
  }),
  200,
);

ChargingCredentialService _credentials(
  Future<http.Response> Function(http.Request) handler, {
  DateTime Function()? now,
  Future<bool> Function()? consent,
  Future<String> Function(Map<String, String>)? decrypt,
}) => ChargingCredentialService(
  httpClient: PublicHttpClient(client: MockClient(handler)),
  consent: consent ?? () async => true,
  now: now ?? () => _clock,
  decrypt: decrypt ?? (input) async => input['data']!,
);

class _FakeApi implements ChargingPileApi {
  _FakeApi(this.handler);
  final Future<List<ChargingPileSlot>> Function(
    String,
    ChargingPileCancellation,
  )
  handler;
  @override
  Future<List<ChargingPileSlot>> queryDevice(
    String id,
    ChargingPileCancellation cancellation,
  ) => handler(id, cancellation);
}

const _free = [ChargingPileSlot(slotId: 1, status: 0)];
List<ChargingPileDevice> _devices(int count) => List.generate(
  count,
  (i) => ChargingPileDevice(
    id: 'D$i',
    code: 'P$i',
    name: '测试 $i',
    location: ChargingPileArea.chaohui.location,
  ),
);
ChargingPileRepository _repository(
  ChargingPileApi api, {
  List<ChargingPileDevice>? catalog,
  DateTime Function()? now,
}) => ChargingPileRepository(
  api: api,
  catalog: catalog ?? _devices(20),
  now: now ?? () => _clock,
  consent: () async => true,
  retryDelay: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('catalog has 109 unique IDs with stable four-area mapping', () {
    expect(kChargingPileDevices, hasLength(109));
    expect(kChargingPileDevices.map((d) => d.id).toSet(), hasLength(109));
    expect(
      kChargingPileDevices.map((d) => d.area).toSet(),
      ChargingPileArea.values.toSet(),
    );
    expect(kChargingPileDevices.every((d) => d.campusId == 'weishui'), isTrue);
  });

  test(
    'decrypts independent Node crypto fixture and rejects tampering',
    () async {
      final fixture = jsonDecode(
        File('test/fixtures/charging_mailbox.json').readAsStringSync(),
      );
      final input = {
        'data': fixture['box']['data'] as String,
        'key': fixture['passphrase'] as String,
      };
      expect(decryptChargingMailbox(input), fixture['token']);
      final pack = jsonDecode(input['data']!);
      final bytes = base64Decode(pack['cipher']);
      bytes[20] ^= 1;
      pack['cipher'] = base64Encode(bytes);
      expect(
        () => decryptChargingMailbox({...input, 'data': jsonEncode(pack)}),
        throwsA(isA<ChargingPileException>()),
      );
      expect(
        () => decryptChargingMailbox({...input, 'data': '{}'}),
        throwsA(isA<ChargingPileException>()),
      );
    },
  );

  group('host credential lifecycle', () {
    test(
      'first use syncs automatically; concurrent callers share sync and legacy key',
      () async {
        var gets = 0;
        final token = _jwt('first');
        final credentials = _credentials((request) async {
          if (request.method == 'GET') {
            gets++;
            await Future<void>.delayed(Duration.zero);
            return _box(100, token);
          }
          expect(request.headers['Authorization'], 'Bearer $token');
          expect(request.followRedirects, isFalse);
          expect(jsonDecode(request.body)['out_number'], startsWith('D'));
          return _slots();
        });
        addTearDown(credentials.close);
        await Future.wait(
          List.generate(
            6,
            (i) => credentials.queryDevice('D$i', ChargingPileCancellation()),
          ),
        );
        expect(gets, 1);
        final saved = jsonDecode(
          (await const FlutterSecureStorage().read(
            key: ChargingCredentialService.storageKey,
          ))!,
        );
        expect(saved['version'], 2);
        expect(saved['updatedAt'], 100);
      },
    );

    test(
      'never rolls back updatedAt and falls back to unexpired legacy token on network failure',
      () async {
        final token = _jwt('local');
        FlutterSecureStorage.setMockInitialValues({
          ChargingCredentialService.storageKey: _record(token, 200),
        });
        final credentials = _credentials((request) async {
          if (request.method == 'GET') return _box(100, _jwt('older'));
          expect(request.headers['Authorization'], 'Bearer $token');
          return _slots();
        });
        addTearDown(credentials.close);
        await credentials.queryDevice('D1', ChargingPileCancellation());
        FlutterSecureStorage.setMockInitialValues({
          ChargingCredentialService.storageKey: token,
        });
        final fallback = _credentials((request) async {
          if (request.method == 'GET')
            throw http.ClientException('sensitive diagnostic');
          expect(request.headers['Authorization'], 'Bearer $token');
          return _slots();
        });
        addTearDown(fallback.close);
        await fallback.queryDevice('D1', ChargingPileCancellation());
      },
    );

    test(
      'expired local/mailbox token never reaches device endpoint; failed sync throttles',
      () async {
        var gets = 0;
        var posts = 0;
        final credentials = _credentials((request) async {
          if (request.method == 'GET') {
            gets++;
            return _box(100, _jwt('expired', exp: 1));
          }
          posts++;
          return _slots();
        });
        addTearDown(credentials.close);
        for (var i = 0; i < 2; i++) {
          await expectLater(
            credentials.queryDevice('D1', ChargingPileCancellation()),
            throwsA(isA<ChargingPileException>()),
          );
        }
        expect(posts, 0);
        expect(gets, 1);
      },
    );

    test(
      'HTML 401 recovers once with new mailbox; unchanged rejected JWT stops future calls',
      () async {
        var gets = 0;
        var posts = 0;
        final old = _jwt('old');
        final newer = _jwt('new');
        final credentials = _credentials((request) async {
          if (request.method == 'GET')
            return _box(++gets, gets == 1 ? old : newer);
          posts++;
          return posts == 1
              ? http.Response('<html>private auth error</html>', 401)
              : _slots();
        });
        addTearDown(credentials.close);
        await credentials.queryDevice('D1', ChargingPileCancellation());
        expect(gets, 2);
        expect(posts, 2);
        FlutterSecureStorage.setMockInitialValues({});
        gets = 0;
        posts = 0;
        final unchanged = _credentials((request) async {
          if (request.method == 'GET') {
            gets++;
            return _box(1, old);
          }
          posts++;
          return http.Response('', 403);
        });
        addTearDown(unchanged.close);
        for (var i = 0; i < 2; i++) {
          await expectLater(
            unchanged.queryDevice('D1', ChargingPileCancellation()),
            throwsA(isA<ChargingPileException>()),
          );
        }
        expect(gets, 2);
        expect(posts, 1);
      },
    );

    test(
      'concurrent auth failures share one recovery; same token in newer envelope stays rejected',
      () async {
        var gets = 0;
        var posts = 0;
        final token = _jwt('same');
        final credentials = _credentials((request) async {
          if (request.method == 'GET') {
            gets++;
            await Future<void>.delayed(Duration.zero);
            return _box(gets, token);
          }
          posts++;
          await Future<void>.delayed(Duration.zero);
          return _slots(code: 401);
        });
        addTearDown(credentials.close);
        await Future.wait(
          List.generate(6, (i) async {
            await expectLater(
              credentials.queryDevice('D$i', ChargingPileCancellation()),
              throwsA(isA<ChargingPileException>()),
            );
          }),
        );
        expect(gets, 2);
        expect(posts, lessThanOrEqualTo(6));
        await expectLater(
          credentials.queryDevice('D9', ChargingPileCancellation()),
          throwsA(isA<ChargingPileException>()),
        );
        expect(gets, 2);
      },
    );

    test(
      'fences cancelled sync and checks consent before all requests',
      () async {
        final pending = Completer<http.Response>();
        var gets = 0;
        final credentials = _credentials((request) {
          gets++;
          return pending.future;
        });
        addTearDown(credentials.close);
        final flight = credentials.syncCredential();
        final assertion = expectLater(
          flight,
          throwsA(isA<ChargingPileException>()),
        );
        await Future<void>.delayed(Duration.zero);
        credentials.cancelPending();
        pending.complete(_box(1, _jwt('late')));
        await assertion;
        expect(
          await const FlutterSecureStorage().read(
            key: ChargingCredentialService.storageKey,
          ),
          isNull,
        );
        final blocked = _credentials((request) async {
          gets++;
          return _slots();
        }, consent: () async => false);
        addTearDown(blocked.close);
        await expectLater(
          blocked.queryDevice('D1', ChargingPileCancellation()),
          throwsA(isA<ChargingPileException>()),
        );
        expect(gets, 1);
      },
    );
  });

  test(
    'API parses counts, preserves other states, rejects malformed data and raw server messages',
    () async {
      var response = _slots();
      final credentials = _credentials(
        (request) async =>
            request.method == 'GET' ? _box(1, _jwt('api')) : response,
      );
      addTearDown(credentials.close);
      final api = ChargingPileApiClient(credentials);
      final slots = await api.queryDevice('D1', ChargingPileCancellation());
      expect(slots.map((s) => s.slotId), [1, 2, 3]);
      final status = ChargingPileDeviceStatus(
        device: _devices(1).first,
        slots: slots,
        fetchedAt: _clock,
      );
      expect(
        [status.freeSlots, status.occupiedSlots, status.otherSlots],
        [1, 1, 1],
      );
      for (final data in [
        [],
        'html',
        {'slotsData': []},
        {
          'slotsData': [
            {'slotId': 1, 'status': 'bad'},
          ],
        },
      ]) {
        response = _slots(data: data);
        await expectLater(
          api.queryDevice('D1', ChargingPileCancellation()),
          throwsA(
            isA<ChargingPileException>().having(
              (e) => e.failure,
              'failure',
              ChargingPileFailure.malformed,
            ),
          ),
        );
      }
      response = http.Response(
        '{"code":400,"message":"private token URL details"}',
        200,
      );
      await expectLater(
        api.queryDevice('D1', ChargingPileCancellation()),
        throwsA(
          isA<ChargingPileException>().having(
            (e) => e.toString(),
            'safe output',
            isNot(contains('private')),
          ),
        ),
      );
      response = http.Response('', 429);
      await expectLater(
        api.queryDevice('D1', ChargingPileCancellation()),
        throwsA(
          isA<ChargingPileException>().having(
            (e) => e.failure,
            'failure',
            ChargingPileFailure.rateLimited,
          ),
        ),
      );
    },
  );

  group('shared repository', () {
    test(
      'overlapping batches merge devices, cap concurrency globally and dedupe for 60 seconds',
      () async {
        var active = 0;
        var peak = 0;
        var calls = 0;
        var now = _clock;
        final repo = _repository(
          _FakeApi((id, cancellation) async {
            calls++;
            active++;
            if (active > peak) peak = active;
            await Future<void>.delayed(const Duration(milliseconds: 2));
            active--;
            return _free;
          }),
          now: () => now,
        );
        addTearDown(repo.dispose);
        await Future.wait([
          repo.refreshAll(),
          repo.refreshAll(),
          repo.refreshDevice('D1'),
        ]);
        expect(calls, 20);
        expect(peak, lessThanOrEqualTo(6));
        await repo.refreshAll();
        expect(calls, 20);
        now = now.add(const Duration(seconds: 61));
        expect(repo.stateFor('D1').isHistorical(now), isTrue);
        await repo.refreshDevice('D1');
        expect(calls, 21);
      },
    );

    test(
      'refreshes only selected area and retains actual success time after failure',
      () async {
        var now = _clock;
        var fail = false;
        final ids = <String>[];
        final repo = _repository(
          _FakeApi((id, cancellation) async {
            ids.add(id);
            now = now.add(const Duration(seconds: 1));
            if (fail)
              throw const ChargingPileException(ChargingPileFailure.network);
            return _free;
          }),
          catalog: kChargingPileDevices.take(2).toList(),
          now: () => now,
        );
        addTearDown(repo.dispose);
        await repo.refreshArea(ChargingPileArea.northGate);
        expect(ids, isEmpty);
        await repo.refreshArea(ChargingPileArea.chaohui);
        final saved = repo.stateFor(kChargingPileDevices.first.id).status!;
        expect(saved.fetchedAt.isAfter(_clock), isTrue);
        now = now.add(const Duration(seconds: 61));
        fail = true;
        await repo.refreshDevice(saved.device.id);
        final entry = repo.stateFor(saved.device.id);
        expect(entry.status!.fetchedAt, saved.fetchedAt);
        expect(entry.failure, ChargingPileFailure.network);
        expect(entry.isHistorical(now), isTrue);
      },
    );

    test(
      'one transient retry; repeated network failures or rate limit stop queue and pause',
      () async {
        var calls = 0;
        final repo = _repository(
          _FakeApi((id, cancellation) async {
            calls++;
            throw const ChargingPileException(ChargingPileFailure.network);
          }),
          catalog: _devices(100),
        );
        addTearDown(repo.dispose);
        await repo.refreshAll();
        expect(calls, lessThanOrEqualTo(20));
        expect(calls, greaterThanOrEqualTo(10));
        expect(repo.pausedUntil!.isAfter(_clock), isTrue);
        final before = calls;
        await repo.refreshDevice('D99');
        expect(calls, before);
        calls = 0;
        final limited = _repository(
          _FakeApi((id, cancellation) async {
            calls++;
            throw const ChargingPileException(ChargingPileFailure.rateLimited);
          }),
        );
        addTearDown(limited.dispose);
        await limited.refreshAll();
        expect(calls, lessThanOrEqualTo(6));
        expect(limited.failure, ChargingPileFailure.rateLimited);
      },
    );

    test(
      'last consumer release fences late results and stops retries/queue; second consumer survives',
      () async {
        final pending = Completer<List<ChargingPileSlot>>();
        var calls = 0;
        final repo = _repository(
          _FakeApi((id, cancellation) {
            calls++;
            return pending.future;
          }),
        );
        addTearDown(repo.dispose);
        final releaseA = repo.acquire();
        final releaseB = repo.acquire();
        final flight = repo.refreshAll();
        await Future<void>.delayed(Duration.zero);
        releaseA();
        expect(repo.isRefreshing, isTrue);
        releaseB();
        pending.complete(_free);
        await flight;
        expect(calls, 6);
        expect(repo.getCachedState(), isEmpty);
        expect(repo.isRefreshing, isFalse);
      },
    );

    test('privacy revision cancels old generation and clears data', () async {
      final pending = Completer<List<ChargingPileSlot>>();
      final repo = _repository(_FakeApi((id, cancellation) => pending.future));
      addTearDown(repo.dispose);
      final flight = repo.refreshAll();
      await Future<void>.delayed(Duration.zero);
      PrivacyAgreementService.revision.value++;
      pending.complete(_free);
      await flight;
      expect(repo.getCachedState(), isEmpty);
      expect(repo.failure, ChargingPileFailure.consentRequired);
    });
  });

  test(
    'repository retries a transient error once and cancellation stops backoff',
    () async {
      var calls = 0;
      final success = _repository(
        _FakeApi((id, cancellation) async {
          if (++calls == 1)
            throw const ChargingPileException(ChargingPileFailure.network);
          return _free;
        }),
      );
      addTearDown(success.dispose);
      await success.refreshDevice('D0');
      expect(calls, 2);
      expect(success.stateFor('D0').status, isNotNull);

      final started = Completer<void>();
      calls = 0;
      final cancelled = ChargingPileRepository(
        api: _FakeApi((id, cancellation) async {
          calls++;
          if (!started.isCompleted) started.complete();
          throw const ChargingPileException(ChargingPileFailure.network);
        }),
        catalog: _devices(1),
        consent: () async => true,
        retryDelay: const Duration(seconds: 10),
      );
      addTearDown(cancelled.dispose);
      final release = cancelled.acquire();
      final flight = cancelled.refreshAll();
      await started.future;
      release();
      await flight;
      expect(calls, 1);
      expect(cancelled.getCachedState(), isEmpty);
    },
  );

  test(
    'new credential generation can query immediately after failed batch',
    () async {
      var now = _clock;
      var gets = 0;
      var posts = 0;
      var updated = false;
      final credentials = _credentials((request) async {
        if (request.method == 'GET') {
          gets++;
          return _box(updated ? 2 : 1, _jwt(updated ? 'new' : 'old'));
        }
        posts++;
        return updated ? _slots() : http.Response('', 401);
      }, now: () => now);
      final repo = ChargingPileRepository(
        credentials: credentials,
        catalog: _devices(1),
        consent: () async => true,
        now: () => now,
      );
      addTearDown(repo.dispose);
      await repo.refreshAll();
      expect(repo.failure, ChargingPileFailure.credentialUnavailable);
      expect(posts, 1);
      updated = true;
      now = now.add(const Duration(seconds: 61));
      await repo.syncCredential();
      await repo.refreshAll();
      expect(repo.failure, isNull);
      expect(repo.stateFor('D0').status, isNotNull);
      expect(posts, 2);
      expect(gets, 3);
    },
  );

  test('closed credential service does not dispatch late devices', () async {
    final pending = Completer<http.Response>();
    var posts = 0;
    final credentials = _credentials((request) async {
      if (request.method == 'GET') return pending.future;
      posts++;
      return _slots();
    });
    final flight = credentials.queryDevice('D0', ChargingPileCancellation());
    final assertion = expectLater(
      flight,
      throwsA(isA<ChargingPileException>()),
    );
    await Future<void>.delayed(Duration.zero);
    credentials.close();
    pending.complete(_box(1, _jwt('late')));
    await assertion;
    expect(posts, 0);
  });

  testWidgets(
    'native page filters/searches, opens slots, refreshes selected area, releases on exit',
    (tester) async {
      final devices = [
        _devices(1).first,
        const ChargingPileDevice(
          id: 'N1',
          code: 'NORTH',
          name: '北门桩',
          location: '渭水-北门',
        ),
      ];
      final calls = <String>[];
      final repo = _repository(
        _FakeApi((id, cancellation) async {
          calls.add(id);
          return _free;
        }),
        catalog: devices,
      );
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ChargingPilePage(repositoryForTesting: repo)),
      );
      await tester.pumpAndSettle();
      expect(calls, ['D0']);
      await tester.tap(find.text('P0 号桩'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('北门').last);
      await tester.pumpAndSettle();
      expect(calls, ['D0', 'N1']);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pump();
      expect(find.textContaining('没有匹配的设备'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'NORTH');
      await tester.pump();
      expect(find.text('NORTH 号桩'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新当前分区'));
      await tester.pumpAndSettle();
      expect(calls, ['D0', 'N1']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(repo.isRefreshing, isFalse);
    },
  );
}
