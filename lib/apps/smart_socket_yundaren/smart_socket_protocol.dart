import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class BleProtocolException implements Exception {
  final String message;

  const BleProtocolException(this.message);

  @override
  String toString() => message;
}

class BleQrInfo {
  final String raw;
  final String mode;
  final String snCode;
  final Uint8List mac;

  const BleQrInfo({
    required this.raw,
    required this.mode,
    required this.snCode,
    required this.mac,
  });

  String get formattedMac => formatMac(mac);

  static BleQrInfo parse(String content) {
    final value = content.trim();
    final parts = value.split(',');
    if (parts.length != 3) {
      throw const BleProtocolException('二维码格式错误，应包含三个字段');
    }
    if (parts[0] != 'KLCXKJ-Water') {
      throw const BleProtocolException('二维码前缀必须是 KLCXKJ-Water');
    }
    if (parts[1] != 'B') {
      throw const BleProtocolException('二维码不是 BLE 模式');
    }
    final snCode = parts[2].toUpperCase();
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(snCode)) {
      throw const BleProtocolException('设备 MAC 必须是 12 位十六进制');
    }
    return BleQrInfo(
      raw: value,
      mode: parts[1],
      snCode: snCode,
      mac: hexToBytes(snCode),
    );
  }
}

class BleFrame {
  final int type;
  final int command;
  final int reserved;
  final Uint8List payload;
  final Uint8List bytes;

  const BleFrame({
    required this.type,
    required this.command,
    required this.reserved,
    required this.payload,
    required this.bytes,
  });

  String get ascii => '#${bytesToHex(bytes)}\n';
}

class BleFrameCodec {
  static String request(int command, [List<int> payload = const []]) {
    final body = <int>[0x80, command, 0x00, ...payload];
    final bytes = <int>[
      0x60,
      0x00,
      body.length,
      ...body,
      checksum8(body),
      0x16,
    ];
    return '#${bytesToHex(bytes)}\n';
  }

  static BleFrame parseAscii(String value) {
    final line = value.trim();
    if (!line.startsWith('#')) {
      throw const BleProtocolException('BLE 帧缺少 # 前缀');
    }
    final encoded = line.substring(1);
    if (encoded.isEmpty || encoded.length.isOdd) {
      throw const BleProtocolException('BLE 帧十六进制长度错误');
    }
    final bytes = hexToBytes(encoded);
    if (bytes.length < 9 || bytes[0] != 0x60 || bytes[1] != 0x00) {
      throw const BleProtocolException('BLE 帧头错误');
    }
    final bodyLength = bytes[2];
    if (bytes.length != bodyLength + 5 || bodyLength < 3) {
      throw const BleProtocolException('BLE 帧长度字段错误');
    }
    if (bytes.last != 0x16) {
      throw const BleProtocolException('BLE 帧结束字节错误');
    }
    final body = bytes.sublist(3, 3 + bodyLength);
    if (bytes[3 + bodyLength] != checksum8(body)) {
      throw const BleProtocolException('BLE 帧校验和错误');
    }
    return BleFrame(
      type: body[0],
      command: body[1],
      reserved: body[2],
      payload: Uint8List.fromList(body.sublist(3)),
      bytes: bytes,
    );
  }
}

class BleNotificationDecoder {
  final StringBuffer _buffer = StringBuffer();

  List<BleFrame> add(List<int> bytes) {
    String text;
    try {
      text = ascii.decode(bytes, allowInvalid: false);
    } on FormatException {
      throw const BleProtocolException('设备通知不是 ASCII 数据');
    }
    _buffer.write(text);
    final source = _buffer.toString();
    final lines = source.split('\n');
    _buffer
      ..clear()
      ..write(lines.removeLast());
    return [
      for (final line in lines)
        if (line.trim().isNotEmpty) BleFrameCodec.parseAscii(line),
    ];
  }

  void clear() => _buffer.clear();
}

class BleDeviceInfo {
  final int productId;
  final int deviceId;
  final int accountId;
  final Uint8List mac;
  final int charge;
  final int reserved;
  final Uint8List tacTime;
  final int macType;
  final int lType;
  final int constype;
  final int macTime;

  const BleDeviceInfo({
    required this.productId,
    required this.deviceId,
    required this.accountId,
    required this.mac,
    required this.charge,
    required this.reserved,
    required this.tacTime,
    required this.macType,
    required this.lType,
    required this.constype,
    required this.macTime,
  });

  bool get isIdle => charge == 0 && accountId == 0 && constype == 0;

  String get formattedMac => formatMac(mac);

  static BleDeviceInfo fromFrame(BleFrame frame) {
    _expectResponse(frame, 0x23);
    final data = frame.payload;
    if (data.length != 28) {
      throw const BleProtocolException('0x23 响应数据长度错误');
    }
    _expectSuccess(data[0], '0x23');
    return BleDeviceInfo(
      productId: readU32(data, 1),
      deviceId: readU32(data, 5),
      accountId: readU32(data, 9),
      mac: Uint8List.fromList(data.sublist(13, 19)),
      charge: data[19],
      reserved: data[20],
      tacTime: Uint8List.fromList(data.sublist(21, 23)),
      macType: data[23],
      lType: data[24],
      constype: data[25],
      macTime: readU16(data, 26),
    );
  }
}

class BleStoredOrder {
  final Uint8List timeId;
  final int productId;
  final int deviceId;
  final int accountId;
  final Uint8List unknownData;
  final Uint8List mac;

  const BleStoredOrder({
    required this.timeId,
    required this.productId,
    required this.deviceId,
    required this.accountId,
    required this.unknownData,
    required this.mac,
  });

  String get timeIdText => bytesToHex(timeId);

  static BleStoredOrder fromFrame(BleFrame frame) {
    _expectResponse(frame, 0x85);
    final data = frame.payload;
    if (data.length != 42) {
      throw const BleProtocolException('0x85 响应数据长度错误');
    }
    _expectSuccess(data[0], '0x85');
    return BleStoredOrder(
      timeId: Uint8List.fromList(data.sublist(1, 7)),
      productId: readU32(data, 7),
      deviceId: readU32(data, 11),
      accountId: readU32(data, 15),
      unknownData: Uint8List.fromList(data.sublist(19, 36)),
      mac: Uint8List.fromList(data.sublist(36, 42)),
    );
  }

  Uint8List buildClearPayload() {
    return Uint8List.fromList([
      ...timeId,
      ...u32(productId),
      ...u32(deviceId),
      ...u32(accountId),
      ...u32(2),
    ]);
  }
}

class BleStartPayload {
  final Uint8List plaintext;
  final Uint8List ciphertext;
  final String frame;
  final Uint8List auth4;

  const BleStartPayload({
    required this.plaintext,
    required this.ciphertext,
    required this.frame,
    required this.auth4,
  });
}

class BleStartProtocol {
  static final Uint8List _authKeySuffix = hexToBytes('55AA');
  static final Uint8List _startDesKey = hexToBytes('53853699E3D698AA');
  static final Uint8List _authMagic = Uint8List.fromList(
    ascii.encode('876543'),
  );

  static Uint8List makeAuth4(BleDeviceInfo device) {
    final key = Uint8List.fromList([...device.mac, ..._authKeySuffix]);
    final plain = Uint8List.fromList([...device.tacTime, ..._authMagic]);
    return Uint8List.fromList(singleDesEcbEncrypt(key, plain).sublist(0, 4));
  }

  static BleStartPayload build({
    required BleQrInfo qr,
    required BleDeviceInfo device,
    required DateTime time,
    required int appRandom,
  }) {
    if (!bytesEqual(qr.mac, device.mac)) {
      throw const BleProtocolException('二维码 MAC 与 BLE 设备 MAC 不一致');
    }
    if (appRandom < 1000 || appRandom > 10000) {
      throw const BleProtocolException('APP_RANDOM 必须在 1000–10000 之间');
    }
    final auth4 = makeAuth4(device);
    final timeId =
        '${time.year.toString().padLeft(4, '0')}'
        '${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}'
        '${time.hour.toString().padLeft(2, '0')}'
        '${time.minute.toString().padLeft(2, '0')}';
    final builder =
        BytesBuilder(copy: false)
          ..add(hexToBytes(timeId))
          ..add(u32(6))
          ..add(u32(appRandom))
          ..addByte(2)
          ..add(u32(1))
          ..add(auth4)
          ..addByte(device.macType)
          ..addByte(device.lType)
          ..addByte(0)
          ..add(u32(10))
          ..add(u32(300))
          ..add(u32(0))
          ..addByte(29)
          ..add(u16(1))
          ..add(u16(1));
    for (var i = 0; i < 8; i++) {
      builder.add(u16(0));
    }
    builder.add(Uint8List(5));
    final plaintext = builder.takeBytes();
    if (plaintext.length != 64) {
      throw BleProtocolException('START 明文长度错误：${plaintext.length}');
    }
    final ciphertext = singleDesEcbEncrypt(_startDesKey, plaintext);
    return BleStartPayload(
      plaintext: plaintext,
      ciphertext: ciphertext,
      frame: BleFrameCodec.request(0x31, ciphertext),
      auth4: auth4,
    );
  }
}

Uint8List singleDesEcbEncrypt(Uint8List key, Uint8List data) {
  if (key.length != 8) {
    throw const BleProtocolException('DES key 必须是 8 bytes');
  }
  if (data.length % 8 != 0) {
    throw const BleProtocolException('DES 数据必须按 8 bytes 对齐');
  }
  final cipher =
      DESedeEngine()..init(
        true,
        KeyParameter(Uint8List.fromList([...key, ...key, ...key])),
      );
  final output = Uint8List(data.length);
  for (var offset = 0; offset < data.length; offset += 8) {
    cipher.processBlock(data, offset, output, offset);
  }
  return output;
}

void expectAck(BleFrame frame, int command) {
  _expectResponse(frame, command);
  if (frame.payload.length != 1) {
    throw BleProtocolException(
      '0x${command.toRadixString(16).toUpperCase()} ACK 长度错误',
    );
  }
  _expectSuccess(
    frame.payload[0],
    '0x${command.toRadixString(16).toUpperCase()}',
  );
}

void _expectResponse(BleFrame frame, int command) {
  if (frame.type != 0x81 || frame.command != command || frame.reserved != 0) {
    throw BleProtocolException(
      '收到非预期的 0x${frame.command.toRadixString(16).toUpperCase()} 响应',
    );
  }
}

void _expectSuccess(int status, String command) {
  if (status != 0x80) {
    throw BleProtocolException(
      '$command 返回失败状态 0x${status.toRadixString(16).padLeft(2, '0').toUpperCase()}',
    );
  }
}

int checksum8(List<int> data) =>
    data.fold<int>(0, (sum, byte) => sum + byte) & 0xFF;

Uint8List u16(int value) =>
    Uint8List.fromList([(value >> 8) & 0xFF, value & 0xFF]);

Uint8List u32(int value) => Uint8List.fromList([
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
]);

int readU16(List<int> data, int offset) =>
    (data[offset] << 8) | data[offset + 1];

int readU32(List<int> data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

Uint8List hexToBytes(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
    throw const BleProtocolException('十六进制数据格式错误');
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

String bytesToHex(List<int> bytes) =>
    bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();

String formatMac(List<int> bytes) {
  if (bytes.length != 6) {
    throw const BleProtocolException('MAC 必须是 6 bytes');
  }
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}

bool bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
