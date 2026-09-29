// Unit tests for BluetoothDevice. Getters and streams are verified by pushing
// native events; request methods (readRssi / requestMtu / discoverServices)
// are verified by mocking the platform response; the android-gated methods are
// verified to throw androidOnly on the test host.
import 'dart:async';

import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _remote = 'AA:BB:CC:DD:EE:FF';

BluetoothDevice get _device => BluetoothDevice.fromId(_remote);

void main() {
  setUp(() async {
    mockChannel(defaultMockHandler);
    // Trigger _initFlutterBluePlus so the native->Dart handler is installed
    // (pushed events otherwise never reach the streams).
    await FlutterBluePlus.isSupported;
  });

  tearDown(tearDownFlutterBluePlus);

  group('identity & constructors', () {
    test('should build a device with the given remoteId via fromId', () {
      final d = BluetoothDevice.fromId(_remote);
      expect(d.remoteId.str, _remote);
    });

    test('should accept a DeviceIdentifier via the constructor', () {
      final d = BluetoothDevice(remoteId: const DeviceIdentifier(_remote));
      expect(d.remoteId.str, _remote);
    });

    test('should compare equal when two devices share the same remoteId', () {
      expect(BluetoothDevice.fromId(_remote), BluetoothDevice.fromId(_remote));
    });
  });

  group('cached getters (driven by pushed events)', () {
    test('should flip isConnected/isDisconnected on connection state changes', () async {
      expect(_device.isConnected, isFalse);
      expect(_device.isDisconnected, isTrue);
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': _remote,
        'connection_state': 1,
        'disconnect_reason_code': null,
        'disconnect_reason_string': null,
      });
      expect(_device.isConnected, isTrue);
      expect(_device.isDisconnected, isFalse);
    });

    test('should expose disconnectReason code and description after disconnect', () async {
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': _remote,
        'connection_state': 0,
        'disconnect_reason_code': 8,
        'disconnect_reason_string': 'connTimeout',
      });
      final r = _device.disconnectReason;
      expect(r, isNotNull);
      expect(r!.code, 8);
      expect(r.description, 'connTimeout');
    });

    test('should reflect the pushed mtu in mtuNow', () async {
      expect(_device.mtuNow, 23); // default
      await emitEvent('OnMtuChanged', {
        'remote_id': _remote,
        'mtu': 185,
        'success': 1,
        'error_code': 0,
        'error_string': '',
      });
      expect(_device.mtuNow, 185);
    });

    test('should update prevBondState from the pushed bond state', () async {
      await emitEvent('OnBondStateChanged', {
        'remote_id': _remote,
        'bond_state': 2, // bonded
        'prev_state': 1, // bonding
      });
      expect(_device.prevBondState, BluetoothBondState.bonding);
    });

    test('should keep servicesList empty until services are discovered', () async {
      expect(_device.servicesList, isEmpty);
    });
  });

  group('streams', () {
    test('should emit the pushed state on the connectionState stream', () async {
      final next = _device.connectionState.firstWhere((s) => s == BluetoothConnectionState.connected);
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': _remote,
        'connection_state': 1,
        'disconnect_reason_code': null,
        'disconnect_reason_string': null,
      });
      expect(await next.timeout(const Duration(seconds: 2)), BluetoothConnectionState.connected);
    });

    test('should emit the pushed mtu on the mtu stream', () async {
      final next = _device.mtu.firstWhere((m) => m == 200);
      await emitEvent('OnMtuChanged', {
        'remote_id': _remote,
        'mtu': 200,
        'success': 1,
        'error_code': 0,
        'error_string': '',
      });
      expect(await next.timeout(const Duration(seconds: 2)), 200);
    });

    test('should fire on the onServicesReset stream when services are reset', () async {
      final completer = Completer<void>();
      final sub = _device.onServicesReset.listen((_) => completer.complete());
      await emitEvent('OnServicesReset', {'remote_id': _remote, 'platform_name': null});
      await completer.future.timeout(const Duration(seconds: 2));
      await sub.cancel();
    });
  });

  group('request methods (mocked platform response)', () {
    // Helper: put the adapter in the "on" state (caches _adapterStateNow) and
    // mark the device connected, so fbpEnsureAdapterIsOn / isDisconnected pass.
    Future<void> primeAdapterAndConnected() async {
      await emitEvent('OnAdapterStateChanged', {'adapter_state': 4}); // on
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': _remote,
        'connection_state': 1,
        'disconnect_reason_code': null,
        'disconnect_reason_string': null,
      });
    }

    test('should return the mocked rssi from readRssi', () async {
      await primeAdapterAndConnected();
      mockChannel(withDefaults((c) async {
        if (c.method == 'readRssi') {
          // simulate native pushing the result after invoke
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnReadRssi', {
            'remote_id': _remote,
            'rssi': -77,
            'success': 1,
            'error_code': 0,
            'error_string': '',
          });
          return true;
        }
        return null;
      }));
      final rssi = await _device.readRssi(timeout: 5);
      expect(rssi, -77);
    });

    test('should throw when requestMtu is called on a non-ohos host', () async {
      // requestMtu gates on Platform.operatingSystem == 'ohos'.
      expect(() => _device.requestMtu(247, predelay: 0), throwsA(isA<FlutterBluePlusException>()));
    });

    test('should return the discovered services from discoverServices', () async {
      await primeAdapterAndConnected();
      mockChannel(withDefaults((c) async {
        if (c.method == 'discoverServices') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnDiscoveredServices', {
            'remote_id': _remote,
            'success': 1,
            'error_code': 0,
            'error_string': '',
            'services': [
              {
                'remote_id': _remote,
                'service_uuid': '180F',
                'is_primary': 1,
                'characteristics': <Map<dynamic, dynamic>>[],
                'included_services': <Map<dynamic, dynamic>>[],
              }
            ],
          });
          return true;
        }
        return null;
      }));
      final services = await _device.discoverServices(subscribeToServicesChanged: false, timeout: 5);
      expect(services.length, 1);
      expect(services.first.uuid, Guid('180F'));
      expect(_device.servicesList.length, 1);
    });
  });

  group('android-gated methods throw on the test host', () {
    test('should throw when createBond is called on a non-android, non-ohos host', () {
      // createBond gates on Platform.isAndroid || operatingSystem == 'ohos'.
      expect(() => _device.createBond(), throwsA(isA<FlutterBluePlusException>()));
    });
    test('should throw when removeBond is called on a non-android host', () {
      expect(() => _device.removeBond(), throwsA(isA<FlutterBluePlusException>()));
    });
    test('should throw when clearGattCache is called on a non-android host', () {
      expect(() => _device.clearGattCache(), throwsA(isA<FlutterBluePlusException>()));
    });
    test('should throw when requestConnectionPriority is called on a non-android host', () {
      expect(
        () => _device.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });
    test('should throw when setPreferredPhy is called on a non-android host', () {
      expect(
        () => _device.setPreferredPhy(txPhy: 1, rxPhy: 1, option: PhyCoding.noPreferred),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });
    test('should throw when the bondState stream is accessed on a non-android, non-ohos host', () async {
      // bondState gates on Platform.isAndroid || operatingSystem == 'ohos'.
      expect(
        _device.bondState.toList(),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });
  });

  test('should cancel immediately via cancelWhenDisconnected when already disconnected', () async {
    // Use a fresh remoteId (never marked connected) so isConnected is false.
    final fresh = BluetoothDevice.fromId('12:34:56:78:9A:BC');
    bool canceled = false;
    final ctrl = StreamController<int>.broadcast(onCancel: () => canceled = true);
    final sub = ctrl.stream.listen((_) {});
    fresh.cancelWhenDisconnected(sub); // disconnected -> cancel immediately
    await Future<void>.delayed(Duration.zero);
    expect(canceled, isTrue);
    await ctrl.close();
  });
}
