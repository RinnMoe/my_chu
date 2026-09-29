// Unit tests for BluetoothCharacteristic, BluetoothDescriptor, BluetoothService.
// Identifiers and streams are verified by pushing native events; read/write/
// setNotifyValue are verified by mocking the platform to push the matching
// response event after each invoke.
import 'dart:async';

import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _remote = 'AA:BB:CC:DD:EE:FF';
final Guid _svc = Guid('180F');
final Guid _chr = Guid('2A19');

void main() {
  setUp(() async {
    mockChannel(defaultMockHandler);
    await FlutterBluePlus.isSupported; // install native->Dart handler
  });

  tearDown(tearDownFlutterBluePlus);

  group('BluetoothCharacteristic identity', () {
    final c = BluetoothCharacteristic(
      remoteId: const DeviceIdentifier(_remote),
      serviceUuid: _svc,
      secondaryServiceUuid: Guid('1801'),
      characteristicUuid: _chr,
    );

    test('should expose every identifier', () {
      expect(c.remoteId.str, _remote);
      expect(c.serviceUuid, _svc);
      expect(c.secondaryServiceUuid, Guid('1801'));
      expect(c.characteristicUuid, _chr);
      expect(c.uuid, _chr);
    });

    test('should build device from remoteId', () {
      expect(c.device.remoteId.str, _remote);
    });

    test('should have empty lastValue until an event arrives', () {
      expect(c.lastValue, isEmpty);
    });
  });

  group('BluetoothCharacteristic streams', () {
    final c = BluetoothCharacteristic(
      remoteId: const DeviceIdentifier(_remote),
      serviceUuid: _svc,
      characteristicUuid: _chr,
    );

    Map<String, dynamic> chrData(String hex) => {
          'remote_id': _remote,
          'service_uuid': _svc.str,
          'secondary_service_uuid': null,
          'characteristic_uuid': _chr.str,
          'value': hex,
          'success': 1,
          'error_code': 0,
          'error_string': '',
        };

    test('should emit read and notify values on onValueReceived', () async {
      final next = c.onValueReceived.first;
      await emitEvent('OnCharacteristicReceived', chrData('4f'));
      final v = await next.timeout(const Duration(seconds: 2));
      expect(v, [0x4f]);
    });

    test('should emit both received and written values on lastValueStream', () async {
      final received = Completer<List<int>>();
      final written = Completer<List<int>>();
      final sub = c.lastValueStream.listen((v) {
        if (!received.isCompleted) {
          received.complete(v);
        } else if (!written.isCompleted) {
          written.complete(v);
        }
      });
      await emitEvent('OnCharacteristicReceived', chrData('01'));
      await received.future.timeout(const Duration(seconds: 2));
      await emitEvent('OnCharacteristicWritten', chrData('02'));
      await written.future.timeout(const Duration(seconds: 2));
      await sub.cancel();
    });

    test('should cache lastValue from the latest event', () async {
      final next = c.lastValueStream.first;
      await emitEvent('OnCharacteristicReceived', chrData('7a'));
      await next.timeout(const Duration(seconds: 2));
      expect(c.lastValue, [0x7a]);
    });
  });

  group('BluetoothCharacteristic read/write/setNotifyValue', () {
    final c = BluetoothCharacteristic(
      remoteId: const DeviceIdentifier(_remote),
      serviceUuid: _svc,
      characteristicUuid: _chr,
    );

    Future<void> primeConnected() async {
      await emitEvent('OnAdapterStateChanged', {'adapter_state': 4});
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': _remote,
        'connection_state': 1,
        'disconnect_reason_code': null,
        'disconnect_reason_string': null,
      });
    }

    Map<String, dynamic> chrData(String hex) => {
          'remote_id': _remote,
          'service_uuid': _svc.str,
          'secondary_service_uuid': null,
          'characteristic_uuid': _chr.str,
          'value': hex,
          'success': 1,
          'error_code': 0,
          'error_string': '',
        };

    test('should return the received value when read completes', () async {
      await primeConnected();
      mockChannel(withDefaults((call) async {
        if (call.method == 'readCharacteristic') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnCharacteristicReceived', chrData('cafe'));
          return true;
        }
        return null;
      }));
      final value = await c.read(timeout: 5);
      expect(value, [0xca, 0xfe]);
    });

    test('should complete write when OnCharacteristicWritten arrives', () async {
      await primeConnected();
      mockChannel(withDefaults((call) async {
        if (call.method == 'writeCharacteristic') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnCharacteristicWritten', chrData('0102'));
          return true;
        }
        return null;
      }));
      await c.write([0x01, 0x02], timeout: 5);
      // reaching here without throwing means success
      expect(c.lastValue, [0x01, 0x02]);
    });

    test('should complete setNotifyValue when CCCD OnDescriptorWritten arrives', () async {
      await primeConnected();
      mockChannel(withDefaults((call) async {
        if (call.method == 'setNotifyValue') {
          // setNotifyValue waits for the CCCD (0x2902) descriptor write result.
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnDescriptorWritten', {
            'remote_id': _remote,
            'service_uuid': _svc.str,
            'secondary_service_uuid': null,
            'characteristic_uuid': _chr.str,
            'descriptor_uuid': cccdUuid.str,
            'value': '0100',
            'success': 1,
            'error_code': 0,
            'error_string': '',
          });
          return true;
        }
        return null;
      }));
      final ok = await c.setNotifyValue(true, timeout: 5);
      expect(ok, isTrue);
    });
  });

  group('BluetoothDescriptor', () {
    // Use a non-CCCD descriptor UUID so the static _lastDescs cache (which the
    // setNotifyValue test populates for 0x2902) does not leak into lastValue.
    final Guid descUuid = Guid('2901');
    final d = BluetoothDescriptor(
      remoteId: const DeviceIdentifier(_remote),
      serviceUuid: _svc,
      characteristicUuid: _chr,
      descriptorUuid: descUuid,
    );

    test('should expose every identifier', () {
      expect(d.remoteId.str, _remote);
      expect(d.serviceUuid, _svc);
      expect(d.characteristicUuid, _chr);
      expect(d.descriptorUuid, descUuid);
      expect(d.uuid, descUuid);
      expect(d.device.remoteId.str, _remote);
      expect(d.lastValue, isEmpty);
    });

    test('should emit descriptor read values on onValueReceived', () async {
      final next = d.onValueReceived.first;
      await emitEvent('OnDescriptorRead', {
        'remote_id': _remote,
        'service_uuid': _svc.str,
        'secondary_service_uuid': null,
        'characteristic_uuid': _chr.str,
        'descriptor_uuid': descUuid.str,
        'value': '0100',
        'success': 1,
        'error_code': 0,
        'error_string': '',
      });
      final v = await next.timeout(const Duration(seconds: 2));
      expect(v, [0x01, 0x00]);
    });

    test('should return the descriptor value when read completes', () async {
      await emitEvent('OnAdapterStateChanged', {'adapter_state': 4});
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': _remote,
        'connection_state': 1,
        'disconnect_reason_code': null,
        'disconnect_reason_string': null,
      });
      mockChannel(withDefaults((call) async {
        if (call.method == 'readDescriptor') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnDescriptorRead', {
            'remote_id': _remote,
            'service_uuid': _svc.str,
            'secondary_service_uuid': null,
            'characteristic_uuid': _chr.str,
            'descriptor_uuid': descUuid.str,
            'value': '0001',
            'success': 1,
            'error_code': 0,
            'error_string': '',
          });
          return true;
        }
        return null;
      }));
      final value = await d.read(timeout: 5);
      expect(value, [0x00, 0x01]);
    });

    test('should complete write when OnDescriptorWritten arrives', () async {
      await emitEvent('OnAdapterStateChanged', {'adapter_state': 4});
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': _remote,
        'connection_state': 1,
        'disconnect_reason_code': null,
        'disconnect_reason_string': null,
      });
      mockChannel(withDefaults((call) async {
        if (call.method == 'writeDescriptor') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnDescriptorWritten', {
            'remote_id': _remote,
            'service_uuid': _svc.str,
            'secondary_service_uuid': null,
            'characteristic_uuid': _chr.str,
            'descriptor_uuid': descUuid.str,
            'value': '0100',
            'success': 1,
            'error_code': 0,
            'error_string': '',
          });
          return true;
        }
        return null;
      }));
      await d.write([0x01, 0x00], timeout: 5);
      expect(d.lastValue, [0x01, 0x00]);
    });
  });

  group('BluetoothService', () {
    test('should map remoteId, serviceUuid, isPrimary, and includedServices via fromProto', () {
      final svc = BluetoothService.fromProto(BmBluetoothService.fromMap({
        'remote_id': _remote,
        'service_uuid': '180F',
        'is_primary': 1,
        'characteristics': <Map<dynamic, dynamic>>[],
        'included_services': <Map<dynamic, dynamic>>[
          {
            'remote_id': _remote,
            'service_uuid': '1801',
            'is_primary': 0,
            'characteristics': <Map<dynamic, dynamic>>[],
            'included_services': <Map<dynamic, dynamic>>[],
          }
        ],
      }));
      expect(svc.remoteId.str, _remote);
      expect(svc.serviceUuid, Guid('180F'));
      expect(svc.uuid, Guid('180F'));
      expect(svc.isPrimary, isTrue);
      expect(svc.includedServices.length, 1);
      expect(svc.includedServices.first.serviceUuid, Guid('1801'));
      expect(svc.includedServices.first.isPrimary, isFalse);
      expect(svc.characteristics, isEmpty);
    });
  });
}
