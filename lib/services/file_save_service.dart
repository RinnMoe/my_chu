import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'logger_service.dart';

/// Saves files into the public Android `Download/MyCHU` directory.
///
/// Android uses a native MediaStore channel so courseware lands in the
/// user-visible Downloads folder instead of app-private Android/data storage.
/// The Android implementation returns the grantable `content://` URI for the
/// saved item; callers should keep using the original file name separately.
/// Callers fall back to their own directory logic on other platforms.
class FileSaveService {
  static const _channel = MethodChannel('mychu/file_save');

  static Future<String?> saveToDownloads({
    required String fileName,
    required List<int> bytes,
  }) async {
    // 平台通道直接传大字节数组有大小限制，先把文件落到临时目录，
    // 让原生侧读取后复制到公共下载目录。
    final tempDir = await getTemporaryDirectory();
    final safeName = _safeFileName(fileName);
    final tempFile = File(
      '${tempDir.path}${Platform.pathSeparator}${_tempFileName(safeName)}',
    );
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      return await saveFileToDownloads(
        fileName: fileName,
        sourceFile: tempFile,
      );
    } catch (error) {
      AppLogger.warn('保存到系统下载目录失败 (${error.runtimeType})');
      return null;
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {
        // 临时文件清理失败不影响结果。
      }
    }
  }

  /// Persists an already downloaded file without loading it into memory.
  ///
  /// Android keeps using the existing MediaStore method channel. Other
  /// platforms copy the file into their user-visible downloads directory,
  /// falling back to the application documents directory when necessary.
  static Future<String?> saveFileToDownloads({
    required String fileName,
    required File sourceFile,
  }) async {
    if (kIsWeb || !await sourceFile.exists()) return null;
    final safeName = _safeFileName(fileName);
    try {
      if (Platform.isAndroid) {
        try {
          final saved = await _channel.invokeMethod<String>('saveToDownloads', {
            'fileName': safeName,
            'sourcePath': sourceFile.path,
          });
          if (saved != null && saved.isNotEmpty) return saved;
        } on MissingPluginException {
          // Fall back to the application-managed directory below.
        } on PlatformException catch (error) {
          AppLogger.warn('保存到系统下载目录失败 (${error.code})');
        }
      }

      final directory = await _downloadDirectory();
      if (!await directory.exists()) await directory.create(recursive: true);
      final target = await _availableFile(directory, safeName);
      await sourceFile.copy(target.path);
      return target.path;
    } catch (error) {
      AppLogger.warn('保存下载文件失败 (${error.runtimeType})');
      return null;
    }
  }

  /// Opens a previously saved file with the platform's file handler chooser.
  ///
  /// Android passes the grantable MediaStore `content://` URI to the chooser.
  /// Other platforms fall back
  /// to their registered file handler when no native channel is available.
  static Future<bool> openFile({
    required String path,
    required String fileName,
  }) async {
    if (path.trim().isEmpty || fileName.trim().isEmpty) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openFile', {
        'path': path,
        'fileName': fileName,
      });
      return opened ?? false;
    } on MissingPluginException {
      if (kIsWeb || Platform.isAndroid) return false;
      try {
        return await launchUrl(
          Uri.file(path),
          mode: LaunchMode.externalApplication,
        );
      } on MissingPluginException {
        return false;
      } on PlatformException catch (error) {
        AppLogger.warn('打开课件失败 (${error.code})');
        return false;
      }
    } on PlatformException catch (error) {
      AppLogger.warn('打开课件失败 (${error.code})');
      return false;
    }
  }

  /// Opens a saved WakeUp schedule directly in the Android WakeUp app. Android
  /// resolves the saved content and hands WakeUp an extension-bearing,
  /// grantable URI, so callers never need to handle a raw file URI.
  static Future<bool> openInWakeUp({
    required String path,
    required String fileName,
  }) async {
    if (path.trim().isEmpty ||
        fileName.trim().isEmpty ||
        !fileName.toLowerCase().endsWith('.wakeup_schedule')) {
      return false;
    }
    try {
      final opened = await _channel.invokeMethod<bool>('openInWakeUp', {
        'path': path,
        'fileName': fileName,
      });
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      AppLogger.warn('打开 WakeUp 失败 (${error.code})');
      return false;
    }
  }

  /// Shares a saved file through the platform chooser.
  static Future<bool> shareFile({
    required String path,
    required String fileName,
  }) async {
    if (path.trim().isEmpty || fileName.trim().isEmpty) return false;
    try {
      final shared = await _channel.invokeMethod<bool>('shareFile', {
        'path': path,
        'fileName': fileName,
      });
      return shared ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      AppLogger.warn('分享文件失败 (${error.code})');
      return false;
    }
  }

  static String _tempFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    return '$stem-${DateTime.now().microsecondsSinceEpoch}$ext';
  }

  static Future<Directory> _downloadDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory('${downloads.path}${Platform.pathSeparator}MyCHU');
    }
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}${Platform.pathSeparator}MyCHU');
  }

  static Future<File> _availableFile(
    Directory directory,
    String fileName,
  ) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot) : '';
    var candidate = File('${directory.path}${Platform.pathSeparator}$fileName');
    var index = 1;
    while (await candidate.exists()) {
      candidate = File(
        '${directory.path}${Platform.pathSeparator}$stem ($index)$extension',
      );
      index++;
    }
    return candidate;
  }

  static String _safeFileName(String value) {
    var cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), '_')
        .trim()
        .replaceFirst(RegExp(r'[. ]+$'), '');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'download';
    }
    final baseName = cleaned.split('.').first.toUpperCase();
    if ({
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    }.contains(baseName)) {
      cleaned = '_$cleaned';
    }
    return cleaned;
  }
}
