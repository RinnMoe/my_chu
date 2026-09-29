import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as image;

import 'captcha_ocr_ohos.dart';
import 'host_platform.dart';

/// Device-local ddddocr 1.6.1 inference service.
class CaptchaOcrService {
  CaptchaOcrService({
    this.modelAsset = 'assets/models/ddddocr/common_old.onnx',
    this.charsetAsset = 'assets/models/ddddocr/charsets_old.json',
    HostPlatform? hostPlatform,
    HarmonyCaptchaOcrBridge? harmonyBridge,
  }) : _hostPlatform = hostPlatform ?? HostPlatform.current,
       _harmonyBridge = harmonyBridge ?? HarmonyCaptchaOcrBridge();

  static final CaptchaOcrService instance = CaptchaOcrService();

  final String modelAsset;
  final String charsetAsset;
  final HostPlatform _hostPlatform;
  final HarmonyCaptchaOcrBridge _harmonyBridge;
  final OnnxRuntime _runtime = OnnxRuntime();

  OrtSession? _session;
  bool _harmonyInitialized = false;
  Future<void>? _initializing;
  List<String> _charset = const [];

  Future<String> recognize(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const FormatException('Captcha image is empty.');
    }
    await _ensureInitialized();
    final tensor = preprocessForTest(bytes);
    if (_hostPlatform == HostPlatform.harmony) {
      if (!_harmonyInitialized) {
        throw StateError('Captcha OCR session is unavailable.');
      }
      final output = await _harmonyBridge.run(
        tensor.data,
        height: tensor.height,
        width: tensor.width,
      );
      return decodeCtcForTest(output.data, output.shape, _charset);
    }

    final session = _session;
    if (session == null) {
      throw StateError('Captcha OCR session is unavailable.');
    }
    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      input = await OrtValue.fromList(tensor.data, [
        1,
        1,
        tensor.height,
        tensor.width,
      ]);
      outputs = await session.run({session.inputNames.first: input});
      final output = outputs[session.outputNames.first];
      if (output == null) {
        throw StateError('Captcha OCR model returned no primary output.');
      }
      final raw = await output.asFlattenedList();
      return decodeCtcForTest(
        raw.map((value) => (value as num).toDouble()).toList(growable: false),
        output.shape,
        _charset,
      );
    } finally {
      if (input != null) await input.dispose();
      if (outputs != null) {
        for (final output in outputs.values) {
          await output.dispose();
        }
      }
    }
  }

  Future<void> _ensureInitialized() async {
    if (_hostPlatform == HostPlatform.harmony
        ? _harmonyInitialized
        : _session != null) {
      return;
    }
    final pending = _initializing;
    if (pending != null) return pending;
    final initialization = _initialize();
    _initializing = initialization;
    try {
      await initialization;
    } finally {
      if (identical(_initializing, initialization)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    final decoded = jsonDecode(await rootBundle.loadString(charsetAsset));
    if (decoded is! Map<String, dynamic> || decoded['charset'] is! List) {
      throw const FormatException('Unsupported ddddocr charset format.');
    }
    final charset = (decoded['charset'] as List)
        .map((value) => value.toString())
        .toList(growable: false);
    if (charset.isEmpty || charset.first.isNotEmpty) {
      throw StateError('ddddocr charset must start with the CTC blank.');
    }
    if (_hostPlatform == HostPlatform.harmony) {
      final modelData = await rootBundle.load(modelAsset);
      final modelBytes = modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      );
      await _harmonyBridge.initialize(modelBytes);
      _harmonyInitialized = true;
    } else {
      final session = await _runtime.createSessionFromAsset(modelAsset);
      if (session.inputNames.length != 1 || session.outputNames.isEmpty) {
        await session.close();
        throw StateError('Unexpected ddddocr model input/output contract.');
      }
      _session = session;
    }
    _charset = charset;
  }

  Future<void> dispose() async {
    final session = _session;
    _session = null;
    if (_harmonyInitialized) {
      _harmonyInitialized = false;
      await _harmonyBridge.close();
    }
    _charset = const [];
    if (session != null) await session.close();
  }

  @visibleForTesting
  static CaptchaOcrTensor preprocessForTest(Uint8List bytes) {
    final source = image.decodeImage(bytes);
    if (source == null || source.width <= 0 || source.height <= 0) {
      throw const FormatException('Captcha image cannot be decoded.');
    }
    const targetHeight = 64;
    final targetWidth = math.max(
      1,
      (source.width * targetHeight / source.height).floor(),
    );
    final resized = image.copyResize(
      source,
      width: targetWidth,
      height: targetHeight,
      interpolation: image.Interpolation.linear,
    );
    final data = Float32List(targetWidth * targetHeight);
    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < targetWidth; x++) {
        final pixel = resized.getPixel(x, y);
        final alpha = pixel.a.toDouble() / 255.0;
        final red = pixel.r.toDouble() * alpha + 255.0 * (1.0 - alpha);
        final green = pixel.g.toDouble() * alpha + 255.0 * (1.0 - alpha);
        final blue = pixel.b.toDouble() * alpha + 255.0 * (1.0 - alpha);
        final gray = 0.299 * red + 0.587 * green + 0.114 * blue;
        data[y * targetWidth + x] = gray / 255.0;
      }
    }
    return CaptchaOcrTensor(
      data: data,
      width: targetWidth,
      height: targetHeight,
    );
  }

  @visibleForTesting
  static String decodeCtcForTest(
    List<double> output,
    List<int> shape,
    List<String> charset,
  ) {
    late final int timeSteps;
    late final int classes;
    if (shape.length == 3 && shape[1] == 1) {
      timeSteps = shape[0];
      classes = shape[2];
    } else if (shape.length == 3 && shape[0] == 1) {
      timeSteps = shape[1];
      classes = shape[2];
    } else if (shape.length == 2) {
      timeSteps = shape[0];
      classes = shape[1];
    } else {
      throw StateError('Unsupported ddddocr output shape: $shape');
    }
    if (timeSteps <= 0 ||
        classes <= 0 ||
        output.length != timeSteps * classes) {
      throw StateError('Invalid ddddocr output dimensions: $shape');
    }
    if (classes != charset.length ||
        charset.isEmpty ||
        charset.first.isNotEmpty) {
      throw StateError(
        'ddddocr output classes ($classes) do not match charset (${charset.length}).',
      );
    }

    final result = StringBuffer();
    var previous = -1;
    for (var step = 0; step < timeSteps; step++) {
      final offset = step * classes;
      var bestIndex = 0;
      var bestValue = double.negativeInfinity;
      for (var index = 0; index < classes; index++) {
        final value = output[offset + index];
        if (value > bestValue) {
          bestValue = value;
          bestIndex = index;
        }
      }
      if (bestIndex != previous && bestIndex != 0) {
        result.write(charset[bestIndex]);
      }
      previous = bestIndex;
    }
    return result.toString();
  }
}

@immutable
class CaptchaOcrTensor {
  const CaptchaOcrTensor({
    required this.data,
    required this.width,
    required this.height,
  });

  final Float32List data;
  final int width;
  final int height;
}
