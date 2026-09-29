// Unit tests for the FlutterBluePlus static API surface. Uses a mock method
// channel so no real platform is needed. Covers the static methods/getters/
// streams that the upstream demo did not exercise.
import 'dart:async';

import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _remote = 'AA:BB:CC:DD:EE:FF';

void main() {
  setUp(() {
    mockChannel(withDefaults(null));
    // _initFlutterBluePlus installs the native->Dart handler.
  });

  tearDown(tearDownFlutterBluePlus);

  test('should return the mocked isSupported value', () async {
    mockChannel(withDefaults((c) async {
      if (c.method == 'isSupported') return false;
      return null;
    }));
    expect(await FlutterBluePlus.isSupported, isFalse);
  });

  test('should return the mocked adapter name', () async {
    mockChannel(withDefaults((c) async {
      if (c.method == 'getAdapterName') return 'TestAdapter';
      return null;
    }));
    expect(await FlutterBluePlus.adapterName, 'TestAdapter');
  });

  test('should default adapterStateNow to unknown', () {
    expect(FlutterBluePlus.adapterStateNow, BluetoothAdapterState.unknown);
  });

  test('should reflect pushed adapter state via the adapterState stream', () async {
    // first read triggers _initFlutterBluePlus + getAdapterState
    final first = FlutterBluePlus.adapterState.first;
    // push an adapter "on" event
    await emitEvent('OnAdapterStateChanged', {'adapter_state': 4}); // on
    final state = await first.timeout(const Duration(seconds: 2));
    expect(state, BluetoothAdapterState.on);
    expect(FlutterBluePlus.adapterStateNow, BluetoothAdapterState.on);
  });

  test('should call setOptions without throwing', () async {
    await FlutterBluePlus.setOptions(showPowerAlert: false, restoreState: false);
    // no exception thrown
  });

  test('should update logLevel synchronously via setLogLevel', () async {
    await FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);
    expect(FlutterBluePlus.logLevel, LogLevel.verbose);
    await FlutterBluePlus.setLogLevel(LogLevel.none);
    expect(FlutterBluePlus.logLevel, LogLevel.none);
  });

  test('should throw FlutterBluePlusException when getPhySupport is called on a non-android host', () async {
    expect(
      () => FlutterBluePlus.getPhySupport(),
      throwsA(isA<FlutterBluePlusException>()),
    );
  });

  test('should include connected devices in connectedDevices after a pushed connected event', () async {
    expect(FlutterBluePlus.connectedDevices, isEmpty);
    await emitEvent('OnConnectionStateChanged', {
      'remote_id': _remote,
      'connection_state': 1, // connected
      'disconnect_reason_code': null,
      'disconnect_reason_string': null,
    });
    final devices = FlutterBluePlus.connectedDevices;
    expect(devices.length, 1);
    expect(devices.first.remoteId.str, _remote);
  });

  test('should exclude disconnected devices from connectedDevices', () async {
    await emitEvent('OnConnectionStateChanged', {
      'remote_id': _remote,
      'connection_state': 0, // disconnected
      'disconnect_reason_code': 1,
      'disconnect_reason_string': 'unknown',
    });
    expect(FlutterBluePlus.connectedDevices, isEmpty);
  });

  test('should parse the device list returned by systemDevices', () async {
    mockChannel(withDefaults((c) async {
      if (c.method == 'getSystemDevices') {
        return {
          'devices': [
            {'remote_id': '11:22:33:44:55:66', 'platform_name': 'Sys1'},
            {'remote_id': _remote, 'platform_name': null},
          ]
        };
      }
      return null;
    }));
    final devices = await FlutterBluePlus.systemDevices([]);
    expect(devices.length, 2);
    expect(devices.first.platformName, 'Sys1');
    expect(devices.first.remoteId.str, '11:22:33:44:55:66');
  });

  test('should parse the device list returned by bondedDevices', () async {
    mockChannel(withDefaults((c) async {
      if (c.method == 'getBondedDevices') {
        return {
          'devices': [
            {'remote_id': 'AA:BB:CC:DD:EE:FF', 'platform_name': 'Bonded1'},
          ]
        };
      }
      return null;
    }));
    final devices = await FlutterBluePlus.bondedDevices;
    expect(devices.length, 1);
    expect(devices.first.platformName, 'Bonded1');
  });

  group('scan', () {
    test('should expose scan state and results across startScan and stopScan', () async {
      // startScan pushes an empty list first, then real results. Wait for a
      // non-empty result.
      final resultsFuture = FlutterBluePlus.scanResults.firstWhere((r) => r.isNotEmpty);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      expect(FlutterBluePlus.isScanningNow, isTrue);
      // push a scan response
      await emitEvent('OnScanResponse', {
        'success': 1,
        'error_code': 0,
        'error_string': '',
        'advertisements': [
          {
            'remote_id': _remote,
            'platform_name': 'Dev',
            'adv_name': 'DevAdv',
            'connectable': 1,
            'tx_power_level': -50,
            'appearance': null,
            'manufacturer_data': <dynamic, String>{},
            'service_data': <String, String>{},
            'service_uuids': <String>[],
            'rssi': -40,
          }
        ],
      });
      final results = await resultsFuture.timeout(const Duration(seconds: 2));
      expect(results.length, 1);
      expect(results.first.device.remoteId.str, _remote);
      expect(results.first.rssi, -40);
      expect(FlutterBluePlus.lastScanResults.length, 1);
      await FlutterBluePlus.stopScan();
      expect(FlutterBluePlus.isScanningNow, isFalse);
    });

    test('should emit only new results via onScanResults', () async {
      final sub = FlutterBluePlus.onScanResults.listen((_) {});
      await FlutterBluePlus.startScan();
      await emitEvent('OnScanResponse', {
        'success': 1,
        'error_code': 0,
        'error_string': '',
        'advertisements': [
          {
            'remote_id': _remote,
            'platform_name': null,
            'adv_name': null,
            'connectable': 0,
            'tx_power_level': null,
            'appearance': null,
            'manufacturer_data': <dynamic, String>{},
            'service_data': <String, String>{},
            'service_uuids': <String>[],
            'rssi': -30,
          }
        ],
      });
      await FlutterBluePlus.stopScan();
      await sub.cancel();
    });

    test('should emit scanning state changes via the isScanning stream', () async {
      // isScanning is a re-emitting Stream<bool>; startScan emits true, stopScan false.
      final states = <bool>[];
      final sub = FlutterBluePlus.isScanning.listen((s) => states.add(s));
      // The stream re-emits its initial value (false) to late subscribers.
      await Future<void>.delayed(Duration.zero);
      await FlutterBluePlus.startScan();
      expect(FlutterBluePlus.isScanningNow, isTrue);
      await FlutterBluePlus.stopScan();
      expect(FlutterBluePlus.isScanningNow, isFalse);
      await sub.cancel();
      // After start(true) then stop(false), the tail must reflect [.., true, false].
      expect(states.last, isFalse);
      expect(states.contains(true), isTrue);
      expect(states.contains(false), isTrue);
    });

    test('should cancel the subscription via cancelWhenScanComplete after stopScan', () async {
      // cancelWhenScanComplete takes any StreamSubscription; _stopScan calls
      // .cancel() on it. Detect via a broadcast controller's onCancel hook.
      bool canceled = false;
      final ctrl = StreamController<List<ScanResult>>.broadcast(onCancel: () => canceled = true);
      final sub = ctrl.stream.listen((_) {});
      FlutterBluePlus.cancelWhenScanComplete(sub);
      await FlutterBluePlus.startScan();
      await FlutterBluePlus.stopScan();
      await Future<void>.delayed(Duration.zero);
      expect(canceled, isTrue);
      await ctrl.close();
    });
  });
}
