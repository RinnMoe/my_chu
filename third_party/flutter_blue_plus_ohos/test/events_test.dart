// Unit tests for the BluetoothEvents streams. Each test subscribes to one of
// the 11 global event streams, simulates the native platform pushing the
// matching event, and verifies the typed Event object parses correctly.
import 'dart:async';

import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _remote = 'AA:BB:CC:DD:EE:FF';

void main() {
  setUp(() async {
    mockChannel(defaultMockHandler);
    // Trigger _initFlutterBluePlus so the native->Dart handler is installed.
    await FlutterBluePlus.isSupported;
  });

  tearDown(tearDownFlutterBluePlus);

  // helper: subscribe, emit, await first event with a safety timeout.
  Future<T> capture<T>(Stream<T> stream, String method, Map<dynamic, dynamic> args) async {
    final completer = Completer<T>();
    final sub = stream.listen(completer.complete);
    await emitEvent(method, args);
    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } finally {
      await sub.cancel();
    }
  }

  group('connection events', () {
    test('should emit connection state changes via onConnectionStateChanged', () async {
      final e = await capture<OnConnectionStateChangedEvent>(
        FlutterBluePlus.events.onConnectionStateChanged,
        'OnConnectionStateChanged',
        {'remote_id': _remote, 'connection_state': 1, 'disconnect_reason_code': null, 'disconnect_reason_string': null},
      );
      expect(e.device.remoteId.str, _remote);
      expect(e.connectionState, BluetoothConnectionState.connected);
    });
  });

  group('mtu events', () {
    test('should emit mtu changes on success via onMtuChanged', () async {
      final e = await capture<OnMtuChangedEvent>(
        FlutterBluePlus.events.onMtuChanged,
        'OnMtuChanged',
        {'remote_id': _remote, 'mtu': 247, 'success': 1, 'error_code': 0, 'error_string': ''},
      );
      expect(e.mtu, 247);
      expect(e.error, isNull);
    });

    test('should emit an FbpError on failure via onMtuChanged', () async {
      final e = await capture<OnMtuChangedEvent>(
        FlutterBluePlus.events.onMtuChanged,
        'OnMtuChanged',
        {'remote_id': _remote, 'mtu': 0, 'success': 0, 'error_code': 9, 'error_string': 'adapterIsOff'},
      );
      expect(e.error, isNotNull);
      expect(e.error!.errorCode, 9);
      expect(e.error!.errorString, 'adapterIsOff');
      expect(e.error!.platform, isA<ErrorPlatform>());
    });
  });

  group('rssi events', () {
    test('should emit rssi readings via onReadRssi', () async {
      final e = await capture<OnReadRssiEvent>(
        FlutterBluePlus.events.onReadRssi,
        'OnReadRssi',
        {'remote_id': _remote, 'rssi': -55, 'success': 1, 'error_code': 0, 'error_string': ''},
      );
      expect(e.rssi, -55);
      expect(e.error, isNull);
    });
  });

  group('service events', () {
    test('should emit service reset events via onServicesReset', () async {
      final e = await capture<OnServicesResetEvent>(
        FlutterBluePlus.events.onServicesReset,
        'OnServicesReset',
        {'remote_id': _remote, 'platform_name': null},
      );
      expect(e.device.remoteId.str, _remote);
    });

    test('should emit discovered services via onDiscoveredServices', () async {
      final e = await capture<OnDiscoveredServicesEvent>(
        FlutterBluePlus.events.onDiscoveredServices,
        'OnDiscoveredServices',
        {
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
        },
      );
      expect(e.services.length, 1);
      expect(e.services.first.serviceUuid, Guid('180F'));
      expect(e.error, isNull);
    });
  });

  group('characteristic events', () {
    test('should emit received characteristic values via onCharacteristicReceived', () async {
      final e = await capture<OnCharacteristicReceivedEvent>(
        FlutterBluePlus.events.onCharacteristicReceived,
        'OnCharacteristicReceived',
        {
          'remote_id': _remote,
          'service_uuid': '180F',
          'secondary_service_uuid': null,
          'characteristic_uuid': '2A19',
          'value': '4f',
          'success': 1,
          'error_code': 0,
          'error_string': '',
        },
      );
      expect(e.value, [0x4f]);
      expect(e.characteristic.uuid, Guid('2A19'));
      expect(e.device.remoteId.str, _remote);
    });

    test('should emit an FbpError on failure via onCharacteristicReceived', () async {
      final e = await capture<OnCharacteristicReceivedEvent>(
        FlutterBluePlus.events.onCharacteristicReceived,
        'OnCharacteristicReceived',
        {
          'remote_id': _remote,
          'service_uuid': '180F',
          'secondary_service_uuid': null,
          'characteristic_uuid': '2A19',
          'value': '',
          'success': 0,
          'error_code': 6,
          'error_string': 'characteristicNotFound',
        },
      );
      expect(e.error, isNotNull);
      expect(e.error!.errorCode, 6);
      expect(e.error!.errorString, 'characteristicNotFound');
      expect(e.error!.platform, isA<ErrorPlatform>());
    });

    test('should emit written characteristic values via onCharacteristicWritten', () async {
      final e = await capture<OnCharacteristicWrittenEvent>(
        FlutterBluePlus.events.onCharacteristicWritten,
        'OnCharacteristicWritten',
        {
          'remote_id': _remote,
          'service_uuid': '180F',
          'secondary_service_uuid': null,
          'characteristic_uuid': '2A19',
          'value': '0102',
          'success': 1,
          'error_code': 0,
          'error_string': '',
        },
      );
      expect(e.value, [0x01, 0x02]);
    });

    test('should emit an FbpError on failure via onCharacteristicWritten', () async {
      final e = await capture<OnCharacteristicWrittenEvent>(
        FlutterBluePlus.events.onCharacteristicWritten,
        'OnCharacteristicWritten',
        {
          'remote_id': _remote,
          'service_uuid': '180F',
          'secondary_service_uuid': null,
          'characteristic_uuid': '2A19',
          'value': '',
          'success': 0,
          'error_code': 8,
          'error_string': 'adapterIsOff',
        },
      );
      expect(e.error, isNotNull);
      expect(e.error!.errorCode, 8);
      expect(e.error!.errorString, 'adapterIsOff');
      expect(e.error!.platform, isA<ErrorPlatform>());
    });
  });

  group('descriptor events', () {
    test('should emit read descriptor values via onDescriptorRead', () async {
      final e = await capture<OnDescriptorReadEvent>(
        FlutterBluePlus.events.onDescriptorRead,
        'OnDescriptorRead',
        {
          'remote_id': _remote,
          'service_uuid': '180F',
          'secondary_service_uuid': null,
          'characteristic_uuid': '2A19',
          'descriptor_uuid': '2902',
          'value': '0100',
          'success': 1,
          'error_code': 0,
          'error_string': '',
        },
      );
      expect(e.value, [0x01, 0x00]);
      expect(e.descriptor.uuid, Guid('2902'));
    });

    test('should emit an FbpError on failure via onDescriptorRead', () async {
      final e = await capture<OnDescriptorReadEvent>(
        FlutterBluePlus.events.onDescriptorRead,
        'OnDescriptorRead',
        {
          'remote_id': _remote,
          'service_uuid': '180F',
          'secondary_service_uuid': null,
          'characteristic_uuid': '2A19',
          'descriptor_uuid': '2902',
          'value': '',
          'success': 0,
          'error_code': 9,
          'error_string': 'adapterIsOff',
        },
      );
      expect(e.error, isNotNull);
      expect(e.error!.errorCode, 9);
      expect(e.error!.errorString, 'adapterIsOff');
      expect(e.error!.platform, isA<ErrorPlatform>());
    });

    test('should emit written descriptor values via onDescriptorWritten', () async {
      final e = await capture<OnDescriptorWrittenEvent>(
        FlutterBluePlus.events.onDescriptorWritten,
        'OnDescriptorWritten',
        {
          'remote_id': _remote,
          'service_uuid': '180F',
          'secondary_service_uuid': null,
          'characteristic_uuid': '2A19',
          'descriptor_uuid': '2902',
          'value': '0000',
          'success': 1,
          'error_code': 0,
          'error_string': '',
        },
      );
      expect(e.value, [0x00, 0x00]);
    });

    test('should emit an FbpError on failure via onDescriptorWritten', () async {
      final e = await capture<OnDescriptorWrittenEvent>(
        FlutterBluePlus.events.onDescriptorWritten,
        'OnDescriptorWritten',
        {
          'remote_id': _remote,
          'service_uuid': '180F',
          'secondary_service_uuid': null,
          'characteristic_uuid': '2A19',
          'descriptor_uuid': '2902',
          'value': '',
          'success': 0,
          'error_code': 8,
          'error_string': 'adapterIsOff',
        },
      );
      expect(e.error, isNotNull);
      expect(e.error!.errorCode, 8);
      expect(e.error!.errorString, 'adapterIsOff');
      expect(e.error!.platform, isA<ErrorPlatform>());
    });
  });

  group('device name events', () {
    test('should emit name changes via onNameChanged', () async {
      final e = await capture<OnNameChangedEvent>(
        FlutterBluePlus.events.onNameChanged,
        'OnNameChanged',
        // The handler parses BmNameChanged (needs 'name'); the stream's
        // OnNameChangedEvent.name reads 'platform_name'. Provide both.
        {'remote_id': _remote, 'name': 'NewName', 'platform_name': 'NewName'},
      );
      expect(e.name, 'NewName');
    });
  });

  group('bond events', () {
    test('should emit bond state changes via onBondStateChanged', () async {
      final e = await capture<OnBondStateChangedEvent>(
        FlutterBluePlus.events.onBondStateChanged,
        'OnBondStateChanged',
        {'remote_id': _remote, 'bond_state': 2, 'prev_state': 1},
      );
      expect(e.bondState, BluetoothBondState.bonded);
    });
  });
}
