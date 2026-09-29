// Pure-Dart unit tests for the data/helper classes — no platform channel needed.
// Covers: Guid, DeviceIdentifier, DisconnectReason, PhySupport, FbpError,
// AndroidScanMode, MsdFilter, ServiceDataFilter, cccdUuid, CharacteristicProperties,
// ScanResult, AdvertisementData, FlutterBluePlusException.
import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Pure-Dart data-class tests hold no shared mutable state, so there is nothing
  // to reset between cases. The setUp/tearDown pair is provided for symmetry with
  // the rest of the suite and to guarantee an empty channel/mock surface in case a
  // future test introduces platform interaction.
  setUp(() {
    // no-op: data classes are stateless; included for suite consistency.
  });

  tearDown(() {
    // no-op: nothing to clean up for pure value-object tests.
  });

  group('Guid', () {
    test('should produce 16 zero bytes for Guid.empty', () {
      final g = Guid.empty();
      expect(g.bytes, List<int>.filled(16, 0));
    });

    test('should treat Guid(input) as an alias of fromString', () {
      final a = Guid('180F');
      final b = Guid.fromString('180F');
      expect(a.bytes, b.bytes);
    });

    test('should accept 2 / 4 / 16 bytes in Guid.fromBytes', () {
      expect(Guid.fromBytes([0x18, 0x0F]).bytes, [0x18, 0x0F]);
      expect(Guid.fromBytes([0x18, 0x0F, 0x12, 0x34]).bytes, [0x18, 0x0F, 0x12, 0x34]);
      expect(Guid.fromBytes(List<int>.generate(16, (i) => i)).bytes.length, 16);
    });

    test('should reject invalid byte lengths in Guid.fromBytes', () {
      expect(() => Guid.fromBytes([1, 2, 3]), throwsA(isA<FormatException>()));
    });

    test('should reject non-hex input in Guid.fromString', () {
      expect(() => Guid.fromString('zzzz'), throwsA(isA<FormatException>()));
    });

    test('should return the shortest representation in str', () {
      expect(Guid.fromString('1234').str, '1234');
      expect(Guid.fromString('12345678').str, '12345678');
      expect(Guid.fromString('123e4567e89b12d3a456426614174000').str,
          '123e4567-e89b-12d3-a456-426614174000');
    });

    test('should return canonical 128-bit form in str128', () {
      expect(Guid.fromString('1234').str128, '00001234-0000-1000-8000-00805f9b34fb');
      expect(Guid.fromString('12345678').str128, '12345678-0000-1000-8000-00805f9b34fb');
    });

    test('should equal str in toString', () {
      final g = Guid('180F');
      expect(g.toString(), g.str);
    });

    test('should compare by value, case-insensitive on input', () {
      final a = Guid('180F');
      final b = Guid('0000180F-0000-1000-8000-00805F9B34FB');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(Guid('1122') == Guid('3344'), isFalse);
    });
  });

  group('DeviceIdentifier', () {
    test('should store str and toString', () {
      const id = DeviceIdentifier('AA:BB:CC:DD:EE:FF');
      expect(id.str, 'AA:BB:CC:DD:EE:FF');
      expect(id.toString(), id.str);
    });

    test('should be equal for identical strings', () {
      const a = DeviceIdentifier('AA:BB:CC:DD:EE:FF');
      const b = DeviceIdentifier('AA:BB:CC:DD:EE:FF');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('should be unequal for case-differing strings', () {
      // _compareAsciiLowerCase returns non-zero for same-letter-different-case,
      // so equality is effectively case-sensitive despite the function's name.
      const a = DeviceIdentifier('AA:BB');
      const b = DeviceIdentifier('aa:bb');
      expect(a == b, isFalse);
    });

    test('should be unequal for different values', () {
      const a = DeviceIdentifier('AA:BB');
      const b = DeviceIdentifier('CC:DD');
      expect(a == b, isFalse);
    });
  });

  test('should be the Client Characteristic Configuration UUID for cccdUuid', () {
    expect(cccdUuid, Guid('00002902-0000-1000-8000-00805f9b34fb'));
  });

  group('DisconnectReason', () {
    test('should expose platform / code / description', () {
      final r = DisconnectReason(ErrorPlatform.android, 8, 'auth');
      expect(r.platform, ErrorPlatform.android);
      expect(r.code, 8);
      expect(r.description, 'auth');
      expect(r.toString(), contains('auth'));
    });

    test('should allow null code / description', () {
      final r = DisconnectReason(ErrorPlatform.apple, null, null);
      expect(r.code, isNull);
      expect(r.description, isNull);
    });
  });

  group('PhySupport', () {
    test('should store constructor fields', () {
      final p = PhySupport(le2M: true, leCoded: false);
      expect(p.le2M, isTrue);
      expect(p.leCoded, isFalse);
    });

    test('should read le_2M / le_coded keys in fromMap', () {
      final p = PhySupport.fromMap({'le_2M': true, 'le_coded': true});
      expect(p.le2M, isTrue);
      expect(p.leCoded, isTrue);
    });
  });

  group('FbpError', () {
    test('should expose errorCode / errorString', () {
      final e = FbpError(7, 'serviceNotFound');
      expect(e.errorCode, 7);
      expect(e.errorString, 'serviceNotFound');
      // platform getter returns the native-error platform (apple on this host).
      expect(e.platform, isA<ErrorPlatform>());
    });
  });

  group('AndroidScanMode', () {
    test('should have correct values for predefined modes', () {
      expect(AndroidScanMode.lowPower.value, 0);
      expect(AndroidScanMode.balanced.value, 1);
      expect(AndroidScanMode.lowLatency.value, 2);
      expect(AndroidScanMode.opportunistic.value, -1);
    });

    test('should store value from custom constructor', () {
      expect(const AndroidScanMode(5).value, 5);
    });
  });

  group('MsdFilter', () {
    test('should store manufacturerId with default empty data/mask', () {
      final f = MsdFilter(0x0006);
      expect(f.manufacturerId, 0x0006);
      expect(f.data, isEmpty);
      expect(f.mask, isEmpty);
    });

    test('should store explicit data and mask', () {
      final f = MsdFilter(0x0006, data: [1, 2], mask: [3, 4]);
      expect(f.data, [1, 2]);
      expect(f.mask, [3, 4]);
    });
  });

  group('ServiceDataFilter', () {
    test('should store service with default empty data/mask', () {
      final f = ServiceDataFilter(Guid('180D'));
      expect(f.service, Guid('180D'));
      expect(f.data, isEmpty);
      expect(f.mask, isEmpty);
    });
  });

  group('CharacteristicProperties', () {
    test('should default all fields to false', () {
      const p = CharacteristicProperties();
      expect(p.broadcast, isFalse);
      expect(p.read, isFalse);
      expect(p.writeWithoutResponse, isFalse);
      expect(p.write, isFalse);
      expect(p.notify, isFalse);
      expect(p.indicate, isFalse);
      expect(p.authenticatedSignedWrites, isFalse);
      expect(p.extendedProperties, isFalse);
      expect(p.notifyEncryptionRequired, isFalse);
      expect(p.indicateEncryptionRequired, isFalse);
    });

    test('should map every BmCharacteristicProperties field in fromProto', () {
      final bm = BmCharacteristicProperties(
        broadcast: true,
        read: true,
        writeWithoutResponse: true,
        write: true,
        notify: true,
        indicate: true,
        authenticatedSignedWrites: true,
        extendedProperties: true,
        notifyEncryptionRequired: true,
        indicateEncryptionRequired: true,
      );
      final p = CharacteristicProperties.fromProto(bm);
      expect(p.broadcast, isTrue);
      expect(p.read, isTrue);
      expect(p.writeWithoutResponse, isTrue);
      expect(p.write, isTrue);
      expect(p.notify, isTrue);
      expect(p.indicate, isTrue);
      expect(p.authenticatedSignedWrites, isTrue);
      expect(p.extendedProperties, isTrue);
      expect(p.notifyEncryptionRequired, isTrue);
      expect(p.indicateEncryptionRequired, isTrue);
    });

    test('should read all 10 keys in BmCharacteristicProperties.fromMap', () {
      final bm = BmCharacteristicProperties.fromMap({
        'broadcast': 1,
        'read': 0,
        'write_without_response': 1,
        'write': 0,
        'notify': 1,
        'indicate': 0,
        'authenticated_signed_writes': 1,
        'extended_properties': 0,
        'notify_encryption_required': 1,
        'indicate_encryption_required': 0,
      });
      expect(bm.broadcast, isTrue);
      expect(bm.read, isFalse);
      expect(bm.writeWithoutResponse, isTrue);
      expect(bm.write, isFalse);
      expect(bm.notify, isTrue);
      expect(bm.indicate, isFalse);
      expect(bm.authenticatedSignedWrites, isTrue);
      expect(bm.extendedProperties, isFalse);
      expect(bm.notifyEncryptionRequired, isTrue);
      expect(bm.indicateEncryptionRequired, isFalse);
    });
  });

  group('ScanResult & AdvertisementData', () {
    BmScanAdvertisement adv({
      Map<int, List<int>>? manufacturerData,
      Map<String, List<int>>? serviceData,
      List<String>? serviceUuids,
    }) {
      // build a BmScanAdvertisement via its fromMap so we exercise the same
      // hex-decode path the platform uses. manufacturer_data keys must be int
      // (the platform channel delivers them as int).
      final md = <dynamic, String>{};
      (manufacturerData ?? {}).forEach((k, v) => md[k] = _hex(v));
      final sd = <String, String>{};
      (serviceData ?? {}).forEach((k, v) => sd[k] = _hex(v));
      return BmScanAdvertisement.fromMap({
        'remote_id': 'AA:BB:CC:DD:EE:FF',
        'platform_name': 'MyDevice',
        'adv_name': 'MyAdv',
        'connectable': 1,
        'tx_power_level': -59,
        'appearance': 0x0123,
        'manufacturer_data': md,
        'service_data': sd,
        'service_uuids': serviceUuids ?? [],
        'rssi': -42,
      });
    }

    test('should map device / rssi / advertisementData / timeStamp in ScanResult.fromProto', () {
      final sr = ScanResult.fromProto(adv());
      expect(sr.device.remoteId.str, 'AA:BB:CC:DD:EE:FF');
      expect(sr.rssi, -42);
      expect(sr.timeStamp, isA<DateTime>());
      expect(sr.advertisementData, isA<AdvertisementData>());
    });

    test('should expose every field with msd computed from manufacturerData in AdvertisementData', () {
      final ad = ScanResult.fromProto(adv(
        manufacturerData: {0x0060: [0x01, 0x02]},
        serviceData: {'180D': [0x03, 0x04]},
        serviceUuids: ['180D'],
      )).advertisementData;
      expect(ad.advName, 'MyAdv');
      expect(ad.txPowerLevel, -59);
      expect(ad.appearance, 0x0123);
      expect(ad.connectable, isTrue);
      expect(ad.manufacturerData[0x0060], [0x01, 0x02]);
      expect(ad.serviceData[Guid('180D')], [0x03, 0x04]);
      expect(ad.serviceUuids, [Guid('180D')]);
      // msd = [lowByte(manufId), highByte(manufId)] + value
      expect(ad.msd, [
        [0x60, 0x00, 0x01, 0x02]
      ]);
    });

    test('should base equality on device in ScanResult', () {
      final a = ScanResult.fromProto(adv());
      final b = ScanResult.fromProto(adv());
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('FlutterBluePlusException', () {
    test('should expose platform / function / code / description', () {
      final e = FlutterBluePlusException(ErrorPlatform.fbp, 'connect', 1, 'timeout');
      expect(e.platform, ErrorPlatform.fbp);
      expect(e.function, 'connect');
      expect(e.code, 1);
      expect(e.description, 'timeout');
    });

    test('should contain function and description in toString', () {
      final e = FlutterBluePlusException(ErrorPlatform.fbp, 'read', 8, 'notFound');
      final s = e.toString();
      expect(s, contains('read'));
      expect(s, contains('notFound'));
    });
  });
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
