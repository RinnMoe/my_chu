import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// Stores only normalized copies; source gallery files are never modified.
class AcademicScheduleBackgroundStore {
  static const maxBytes = 20 * 1024 * 1024;

  static Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/schedule_backgrounds');
  }

  static Future<File> file(String name) async {
    if (!RegExp(r'^background_[a-f0-9]{64}\.png$').hasMatch(name)) {
      throw const FormatException('invalid_background_reference');
    }
    return File('${(await _directory()).path}/$name');
  }

  static Future<String?> pick() async {
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '课表背景图片',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
          uniformTypeIdentifiers: [
            'public.jpeg',
            'public.png',
            'org.webmproject.webp',
          ],
        ),
      ],
      confirmButtonText: '选择',
    );
    if (selected == null) return null;
    if (await selected.length() > maxBytes) {
      throw const FormatException('image_too_large');
    }
    return importImage(await selected.readAsBytes());
  }

  static Future<String> importImage(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('invalid_image_size');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 60000000) {
        throw const FormatException('image_too_large');
      }
      final scale = math.min(
        1.0,
        2048 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) throw const FormatException('invalid_image');
      final normalized = encoded.buffer.asUint8List(
        encoded.offsetInBytes,
        encoded.lengthInBytes,
      );
      final name = 'background_${sha256.convert(normalized)}.png';
      final target = await file(name);
      await target.parent.create(recursive: true);
      if (!await target.exists()) {
        final temporary = File(
          '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        try {
          await temporary.writeAsBytes(normalized, flush: true);
          await temporary.rename(target.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      }
      return name;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
