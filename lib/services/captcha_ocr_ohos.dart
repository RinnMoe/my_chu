import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Method-channel bridge to the app-local Harmony ONNX Runtime implementation.
class HarmonyCaptchaOcrBridge {
  HarmonyCaptchaOcrBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'moe.rinn.mychu/harmony_captcha_ocr';

  final MethodChannel _channel;

  Future<void> initialize(Uint8List model) async {
    if (model.isEmpty) throw const FormatException('Captcha model is empty.');
    await _channel.invokeMethod<void>('initialize', {'model': model});
  }

  Future<HarmonyCaptchaOcrOutput> run(
    Float32List input, {
    required int height,
    required int width,
  }) async {
    if (height <= 0 || width <= 0 || input.length != height * width) {
      throw const FormatException('Captcha tensor dimensions are invalid.');
    }
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'run',
      {'input': input, 'height': height, 'width': width},
    );
    final data = result?['data'];
    final rawShape = result?['shape'];
    if (data is! Float32List || rawShape is! List) {
      throw const FormatException('Captcha ONNX output is invalid.');
    }
    final shape = <int>[];
    for (final dimension in rawShape) {
      if (dimension is! num || !dimension.isFinite) {
        throw const FormatException('Captcha ONNX output shape is invalid.');
      }
      shape.add(dimension.toInt());
    }
    return HarmonyCaptchaOcrOutput(data: data, shape: shape);
  }

  Future<void> close() => _channel.invokeMethod<void>('close');
}

class HarmonyCaptchaOcrOutput {
  const HarmonyCaptchaOcrOutput({required this.data, required this.shape});

  final Float32List data;
  final List<int> shape;
}
