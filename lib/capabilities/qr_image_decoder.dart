import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:zxing2/qrcode.dart';

/// Decodes one QR code from an image selected by the user.
///
/// The implementation is pure Dart so HarmonyOS can scan gallery images even
/// when the system camera scanner is unavailable, such as in the emulator.
({String? value, String? error, String? stack}) decodeQrImageBytes(
  Uint8List bytes,
) {
  if (bytes.isEmpty) return (value: null, error: null, stack: null);
  try {
    final decoded = image.decodeImage(bytes);
    if (decoded == null) return (value: null, error: null, stack: null);
    final rgba = decoded
        .convert(numChannels: 4)
        .getBytes(order: image.ChannelOrder.abgr);
    final source = RGBLuminanceSource(
      decoded.width,
      decoded.height,
      rgba.buffer.asInt32List(),
    );
    final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
    return (
      value: QRCodeReader().decode(bitmap).text,
      error: null,
      stack: null,
    );
  } catch (error, stack) {
    return (
      value: null,
      error: '${error.runtimeType}\n$error',
      stack: '$stack',
    );
  }
}
