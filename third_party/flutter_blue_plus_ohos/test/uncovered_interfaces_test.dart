// Covers previously-uncovered public interfaces and scenario gaps flagged by
// the test-coverage review:
//   - turnOn, device.advName, device.isAutoConnectEnabled, device.connect(),
//     device.disconnect()
//   - characteristic.properties / descriptors / isNotifying
//   - descriptor.lastValueStream
//   - BluetoothConnectionEvent (constructor, device, connectionState)
//   - exception / boundary / concurrency scenarios
// All platform interaction is mocked via test_helpers; no real BLE needed.
import 'dart:async';

import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

const _remote = 'AA:BB:CC:DD:EE:FF';
final Guid _svc = Guid('180F');
final Guid _chr = Guid('2A19');
final Guid _desc = Guid('2901');

void main() {
  setUp(() async {
    mockChannel(defaultMockHandler);
    // Trigger _initFlutterBluePlus so the native->Dart handler is installed.
    await FlutterBluePlus.isSupported;
  });

  tearDown(tearDownFlutterBluePlus);

  // Put the adapter in the "on" state and mark the device connected, so
  // fbpEnsureAdapterIsOn / isDisconnected preconditions pass.
  Future<void> primeConnected() async {
    await emitEvent('OnAdapterStateChanged', {'adapter_state': 4}); // on
    await emitEvent('OnConnectionStateChanged', {
      'remote_id': _remote,
      'connection_state': 1, // connected
      'disconnect_reason_code': null,
      'disconnect_reason_string': null,
    });
  }

  group('BluetoothConnectionEvent', () {
    test('should store device and connectionState in BluetoothConnectionEvent constructor', () {
      final device = BluetoothDevice.fromId(_remote);
      final e = BluetoothConnectionEvent(device, BluetoothConnectionState.connected);
      expect(e.device.remoteId.str, _remote);
      expect(e.connectionState, BluetoothConnectionState.connected);
    });

    test('should allow connectionState to be disconnected', () {
      final device = BluetoothDevice.fromId(_remote);
      final e = BluetoothConnectionEvent(device, BluetoothConnectionState.disconnected);
      expect(e.connectionState, BluetoothConnectionState.disconnected);
    });
  });

  group('FlutterBluePlus.turnOn', () {
    test('should complete turnOn when the user accepts and the adapter turns on', () async {
      // Capture the turnOn invoke so we can push the OnTurnOnResponse + adapter on.
      mockChannel(withDefaults((c) async {
        if (c.method == 'turnOn') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnTurnOnResponse', {'user_accepted': true});
          await emitEvent('OnAdapterStateChanged', {'adapter_state': 4}); // on
          return true;
        }
        return null;
      }));
      await FlutterBluePlus.turnOn(timeout: 5);
      expect(FlutterBluePlus.adapterStateNow, BluetoothAdapterState.on);
    });

    test('should throw when the user rejects turnOn', () async {
      mockChannel(withDefaults((c) async {
        if (c.method == 'turnOn') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnTurnOnResponse', {'user_accepted': false});
          await emitEvent('OnAdapterStateChanged', {'adapter_state': 6}); // off
          return true;
        }
        return null;
      }));
      expect(
        () => FlutterBluePlus.turnOn(timeout: 5),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });
  });

  group('BluetoothDevice connect/disconnect/advName/autoConnect', () {
    test('should complete connect when OnConnectionStateChanged(connected) arrives', () async {
      mockChannel(withDefaults((c) async {
        if (c.method == 'connect') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnConnectionStateChanged', {
            'remote_id': _remote,
            'connection_state': 1,
            'disconnect_reason_code': null,
            'disconnect_reason_string': null,
          });
          return true;
        }
        return null;
      }));
      await emitEvent('OnAdapterStateChanged', {'adapter_state': 4}); // on
      final device = BluetoothDevice.fromId(_remote);
      await device.connect(timeout: const Duration(seconds: 5), mtu: null);
      expect(device.isConnected, isTrue);
    });

    test('should invoke the disconnect method on the channel', () async {
      String? calledMethod;
      await primeConnected();
      mockChannel(withDefaults((c) async {
        calledMethod = c.method;
        if (c.method == 'disconnect') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnConnectionStateChanged', {
            'remote_id': _remote,
            'connection_state': 0,
            'disconnect_reason_code': 0,
            'disconnect_reason_string': 'ok',
          });
          return true;
        }
        return null;
      }));
      final device = BluetoothDevice.fromId(_remote);
      await device.disconnect();
      expect(calledMethod, 'disconnect');
      expect(device.isDisconnected, isTrue);
    });

    test('should expose advName from the scan advertisement', () async {
      mockChannel(withDefaults((c) async {
        if (c.method == 'startScan') return true;
        if (c.method == 'stopScan') return true;
        return null;
      }));
      // advName is cached from OnScanResponse, which only flows while a scan
      // is active (the response is buffered via _scanBuffer, set up by startScan).
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      await emitEvent('OnScanResponse', {
        'success': 1,
        'error_code': 0,
        'error_string': '',
        'advertisements': [
          {
            'remote_id': _remote,
            'platform_name': 'MyDevice',
            'adv_name': 'AdvName',
            'connectable': 1,
            'tx_power_level': -59,
            'appearance': null,
            'manufacturer_data': <dynamic, String>{},
            'service_data': <String, String>{},
            'service_uuids': <String>[],
            'rssi': -40,
          }
        ],
      });
      // allow the buffered scan result to flush.
      await FlutterBluePlus.scanResults.firstWhere((r) => r.isNotEmpty)
          .timeout(const Duration(seconds: 2));
      final device = BluetoothDevice.fromId(_remote);
      // device.advName reads the advertised name (_advNames), not platformName.
      expect(device.advName, 'AdvName');
      await FlutterBluePlus.stopScan();
    });

    test('should report isAutoConnectEnabled true after connect(autoConnect:true)', () async {
      mockChannel(withDefaults((c) async {
        if (c.method == 'connect') {
          // autoConnect returns immediately; no connection-state wait.
          return true;
        }
        // disconnect() is invoked at the end to drop the remoteId from the
        // singleton _autoConnect set (source library clears it in disconnect).
        // Returning false (changed=false) skips the connection-state wait,
        // so no extra events are needed. This prevents the entry from leaking
        // into later tests and triggering a spurious AutoConnect reconnect.
        if (c.method == 'disconnect') {
          return false;
        }
        return null;
      }));
      final device = BluetoothDevice.fromId(_remote);
      await device.connect(autoConnect: true, mtu: null);
      expect(device.isAutoConnectEnabled, isTrue);
      // Clean up: remove the device from _autoConnect so it does not leak
      // across tests (FlutterBluePlus is a non-resettable singleton).
      await device.disconnect();
      expect(device.isAutoConnectEnabled, isFalse);
    });
  });

  group('BluetoothCharacteristic properties/descriptors/isNotifying', () {
    BluetoothCharacteristic characteristic() => BluetoothCharacteristic(
          remoteId: const DeviceIdentifier(_remote),
          serviceUuid: _svc,
          characteristicUuid: _chr,
        );

    // Push a discovered-services payload containing one characteristic (with
    // notify + read properties and a CCCD descriptor) so _bmchr is populated.
    Future<void> pushDiscoveredServices() async {
      await emitEvent('OnDiscoveredServices', {
        'remote_id': _remote,
        'success': 1,
        'error_code': 0,
        'error_string': 'GATT_SUCCESS',
        'services': [
          {
            'remote_id': _remote,
            'service_uuid': '180F',
            'is_primary': 1,
            'characteristics': [
              {
                'remote_id': _remote,
                'service_uuid': '180F',
                'secondary_service_uuid': null,
                'characteristic_uuid': '2A19',
                'descriptors': [
                  {
                    'remote_id': _remote,
                    'service_uuid': '180F',
                    'characteristic_uuid': '2A19',
                    'descriptor_uuid': '2902',
                  },
                ],
                'properties': {
                  'broadcast': 0,
                  'read': 1,
                  'write_without_response': 0,
                  'write': 0,
                  'notify': 1,
                  'indicate': 0,
                  'authenticated_signed_writes': 0,
                  'extended_properties': 0,
                  'notify_encryption_required': 0,
                  'indicate_encryption_required': 0,
                },
              }
            ],
            'included_services': <Map<dynamic, dynamic>>[],
          }
        ],
      });
    }

    test('should yield default properties for an unknown characteristic', () {
      // A characteristic UUID that was never discovered -> properties default.
      final c = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: Guid('2A20'),
      );
      expect(c.properties.read, isFalse);
      expect(c.descriptors, isEmpty);
    });

    test('should reflect discovered characteristic flags via properties', () async {
      await pushDiscoveredServices();
      final c = characteristic();
      expect(c.properties.read, isTrue);
      expect(c.properties.notify, isTrue);
      expect(c.properties.write, isFalse);
    });

    test('should list the CCCD in descriptors after discovery', () async {
      await pushDiscoveredServices();
      final descs = characteristic().descriptors;
      expect(descs.length, 1);
      expect(descs.first.descriptorUuid, cccdUuid);
    });

    test('should report isNotifying false until the CCCD value enables it', () async {
      await pushDiscoveredServices();
      // CCCD lastValue empty by default -> not notifying.
      expect(characteristic().isNotifying, isFalse);
    });

    test('should report isNotifying true when the CCCD lastValue has the notify bit set', () async {
      await pushDiscoveredServices();
      // Push a descriptor read/written event with value 0x01 (notify enabled).
      await emitEvent('OnDescriptorRead', {
        'remote_id': _remote,
        'service_uuid': '180F',
        'secondary_service_uuid': null,
        'characteristic_uuid': '2A19',
        'descriptor_uuid': '2902',
        'value': '0100',
        'success': 1,
        'error_code': 0,
        'error_string': '',
      });
      expect(characteristic().isNotifying, isTrue);
    });
  });

  group('BluetoothDescriptor.lastValueStream', () {
    test('should emit descriptor values from OnDescriptorRead/Write via lastValueStream', () async {
      final d = BluetoothDescriptor(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
        descriptorUuid: _desc,
      );
      // skip the re-emitted initial (empty) value, wait for the real event.
      final next = d.lastValueStream.skip(1).first;
      await emitEvent('OnDescriptorRead', {
        'remote_id': _remote,
        'service_uuid': '180F',
        'secondary_service_uuid': null,
        'characteristic_uuid': '2A19',
        'descriptor_uuid': '2901',
        'value': 'cafe',
        'success': 1,
        'error_code': 0,
        'error_string': '',
      });
      final v = await next.timeout(const Duration(seconds: 2));
      expect(v, [0xca, 0xfe]);
    });
  });

  group('exception & boundary scenarios', () {
    test('should reject a 3-byte length in Guid.fromBytes (boundary)', () {
      expect(() => Guid.fromBytes([1, 2, 3]), throwsA(isA<FormatException>()));
    });

    test('should produce an empty Guid for Guid.fromString of an empty string', () {
      // empty string parses to all-zero 16 bytes (documents current behavior)
      expect(Guid.fromString('').bytes.length, 16);
    });

    test('should start scanning with an empty filter list', () async {
      mockChannel(withDefaults((c) async {
        if (c.method == 'startScan') return true;
        return null;
      }));
      await FlutterBluePlus.startScan(
        withServices: const [],
        timeout: const Duration(seconds: 1),
      );
      expect(FlutterBluePlus.isScanningNow, isTrue);
      await FlutterBluePlus.stopScan();
    });

    test('should throw when operating on a device while the adapter is off', () async {
      // adapter off -> fbpEnsureAdapterIsOn throws.
      await emitEvent('OnAdapterStateChanged', {'adapter_state': 6}); // off
      final device = BluetoothDevice.fromId(_remote);
      expect(
        () => device.readRssi(),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });

    test('should time out readCharacteristic when no response arrives', () async {
      await primeConnected();
      mockChannel(withDefaults((c) async {
        if (c.method == 'readCharacteristic') return true; // no event pushed
        return null;
      }));
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      expect(
        () => chr.read(timeout: 1),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });

    test('should complete an empty write when OnCharacteristicWritten arrives', () async {
      await primeConnected();
      mockChannel(withDefaults((c) async {
        if (c.method == 'writeCharacteristic') {
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnCharacteristicWritten', {
            'remote_id': _remote,
            'service_uuid': '180F',
            'secondary_service_uuid': null,
            'characteristic_uuid': '2A19',
            'value': '',
            'success': 1,
            'error_code': 0,
            'error_string': '',
          });
          return true;
        }
        return null;
      }));
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      await chr.write([], timeout: 5);
      expect(chr.lastValue, isEmpty);
    });
  });

  group('concurrency scenarios', () {
    test('should complete two concurrent writes to the same characteristic without error', () async {
      await primeConnected();
      int callCount = 0;
      mockChannel(withDefaults((c) async {
        if (c.method == 'writeCharacteristic') {
          callCount++;
          final seq = callCount; // 1 then 2
          await Future<void>.delayed(Duration.zero);
          await emitEvent('OnCharacteristicWritten', {
            'remote_id': _remote,
            'service_uuid': '180F',
            'secondary_service_uuid': null,
            'characteristic_uuid': '2A19',
            'value': seq == 1 ? '01' : '02',
            'success': 1,
            'error_code': 0,
            'error_string': '',
          });
          return true;
        }
        return null;
      }));
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      // fire two writes concurrently; both must complete without throwing.
      final results = await Future.wait([
        chr.write([0x01], timeout: 5).then((_) => 'first'),
        chr.write([0x02], timeout: 5).then((_) => 'second'),
      ]);
      expect(results, containsAll(['first', 'second']));
    });

    test('should emit multiple results from a concurrent scan without dropping', () async {
      final resultsFuture = FlutterBluePlus.scanResults.firstWhere((r) => r.length >= 2);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      // push two distinct devices "simultaneously" (back-to-back).
      Future<void> push(String id) async {
        await emitEvent('OnScanResponse', {
          'success': 1,
          'error_code': 0,
          'error_string': '',
          'advertisements': [
            {
              'remote_id': id,
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
      }

      await Future.wait([push('11:11:11:11:11:11'), push('22:22:22:22:22:22')]);
      final results = await resultsFuture.timeout(const Duration(seconds: 2));
      expect(results.length, greaterThanOrEqualTo(2));
      await FlutterBluePlus.stopScan();
    });
  });

  group('exported error codes', () {
    test('should export bmUserCanceledErrorCode as the HCI user-canceled value', () {
      // 23789258 (0x16) is the value the source library uses to flag a
      // connection teardown initiated by the user, so the Dart layer can
      // distinguish a user-initiated cancel from a system-side disconnect.
      expect(bmUserCanceledErrorCode, 23789258);
    });
  });

  group('parameter exception scenarios', () {
    // Force the device into the disconnected state regardless of any state left
    // over by earlier tests (FlutterBluePlus is a non-resettable singleton).
    Future<void> primeDisconnected() async {
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': _remote,
        'connection_state': 0, // disconnected
        'disconnect_reason_code': 0,
        'disconnect_reason_string': 'test',
      });
    }

    test('should throw when reading a characteristic of a disconnected device', () async {
      await primeDisconnected();
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      expect(
        () => chr.read(timeout: 2),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });

    test('should throw when setNotifyValue is called on a disconnected device characteristic', () async {
      await primeDisconnected();
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      expect(
        () => chr.setNotifyValue(true, timeout: 2),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });
  });

  group('state exception scenarios', () {
    test('should throw when reading a characteristic while the adapter is off', () async {
      // Device is connected, but the adapter is turned off -> the read must be
      // rejected by fbpEnsureAdapterIsOn.
      await primeConnected();
      await emitEvent('OnAdapterStateChanged', {'adapter_state': 6}); // off
      mockChannel(withDefaults((c) async {
        if (c.method == 'readCharacteristic') return true; // no event pushed
        return null;
      }));
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      expect(
        () => chr.read(timeout: 2),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });

    test('should throw when writing a characteristic while the adapter is off', () async {
      await primeConnected();
      await emitEvent('OnAdapterStateChanged', {'adapter_state': 6}); // off
      mockChannel(withDefaults((c) async {
        if (c.method == 'writeCharacteristic') return true; // no event pushed
        return null;
      }));
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      expect(
        () => chr.write([0x01], timeout: 2),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });

    test('should throw when requesting MTU on a non-ohos host', () async {
      // requestMtu is android-only; on the test host Platform.isAndroid is
      // false, so it must throw before any platform call is made.
      final device = BluetoothDevice.fromId(_remote);
      expect(
        () => device.requestMtu(247),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });
  });

  group('timeout exception scenarios', () {
    // Note: the readCharacteristic timeout is already covered under
    // 'exception & boundary scenarios'; these cover write & setNotifyValue.
    test('should time out writeCharacteristic when no OnCharacteristicWritten arrives', () async {
      await primeConnected();
      mockChannel(withDefaults((c) async {
        if (c.method == 'writeCharacteristic') return true; // no event pushed
        return null;
      }));
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      expect(
        () => chr.write([0x01], timeout: 1),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });

    test('should time out setNotifyValue when no CCCD write completes', () async {
      await primeConnected();
      mockChannel(withDefaults((c) async {
        // hasCCCD=true -> setNotifyValue waits for OnDescriptorWritten, which
        // we never emit, so the short timeout fires.
        if (c.method == 'setNotifyValue') return true;
        return null;
      }));
      final chr = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: _chr,
      );
      expect(
        () => chr.setNotifyValue(true, timeout: 1),
        throwsA(isA<FlutterBluePlusException>()),
      );
    });
  });

  group('additional concurrency scenarios', () {
    test('should handle concurrent reads from two characteristics without mixing values', () async {
      await primeConnected();
      mockChannel(withDefaults((c) async {
        if (c.method == 'readCharacteristic') {
          // Guid.str lowercases the uuid, so compare case-insensitively.
          final cu = (c.arguments['characteristic_uuid'] as String).toUpperCase();
          await Future<void>.delayed(Duration.zero);
          // Emit each characteristic's own distinct value.
          await emitEvent('OnCharacteristicReceived', {
            'remote_id': _remote,
            'service_uuid': '180F',
            'secondary_service_uuid': null,
            'characteristic_uuid': cu,
            'value': cu == '2A19' ? 'a1' : 'b2',
            'success': 1,
            'error_code': 0,
            'error_string': '',
          });
          return true;
        }
        return null;
      }));
      final chr1 = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: Guid('2A19'),
      );
      final chr2 = BluetoothCharacteristic(
        remoteId: const DeviceIdentifier(_remote),
        serviceUuid: _svc,
        characteristicUuid: Guid('2A20'),
      );
      // Fire both reads concurrently; the global mutex serializes them, but
      // each must still resolve to its own value (no cross-talk).
      final results = await Future.wait([
        chr1.read(timeout: 5),
        chr2.read(timeout: 5),
      ]);
      expect(results[0], [0xa1]);
      expect(results[1], [0xb2]);
      expect(chr1.lastValue, [0xa1]);
      expect(chr2.lastValue, [0xb2]);
    });

    test('should not drop concurrent connection-state events for distinct devices', () async {
      const id1 = '11:11:11:11:11:11';
      const id2 = '22:22:22:22:22:22';
      // Push two connection-state events back-to-back; both must be recorded.
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': id1,
        'connection_state': 1, // connected
        'disconnect_reason_code': null,
        'disconnect_reason_string': null,
      });
      await emitEvent('OnConnectionStateChanged', {
        'remote_id': id2,
        'connection_state': 1, // connected
        'disconnect_reason_code': null,
        'disconnect_reason_string': null,
      });
      // Filter to the two devices this test owns so the assertion is robust
      // against singleton state leaked from earlier tests.
      final mine = FlutterBluePlus.connectedDevices
          .where((d) => d.remoteId.str == id1 || d.remoteId.str == id2)
          .toList();
      expect(mine.length, 2);
    });
  });
}
