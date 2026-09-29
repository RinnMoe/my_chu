import 'dart:io';

import 'package:flutter/foundation.dart' show ValueChanged, kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../../services/campus_session.dart';
import '../../services/file_save_service.dart';
import '../../services/logger_service.dart';
import '../../services/public_http_client.dart';
import '../../services/service_endpoints.dart';

/// Types of failures surfaced by the shared in-app download capability.
enum InAppDownloadErrorType {
  invalidUrl,
  unsupportedPlatform,
  network,
  http,
  storage,
}

/// A user-safe error from an in-app download operation.
class InAppDownloadException implements Exception {
  final InAppDownloadErrorType type;
  final int? statusCode;

  const InAppDownloadException(this.type, {this.statusCode});

  @override
  String toString() => 'InAppDownloadException(${type.name})';
}

/// Progress for one active download attempt.
class InAppDownloadProgress {
  final int receivedBytes;
  final int? totalBytes;
  final int attempt;

  const InAppDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.attempt,
  });

  /// A bounded fraction when the server supplied a usable total size.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

/// A saved file returned by [InAppDownloadCapability].
class InAppDownloadedFile {
  final String path;
  final String fileName;
  final int sizeBytes;

  const InAppDownloadedFile({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
  });
}

typedef InAppDownloadTemporaryDirectoryProvider = Future<Directory> Function();
typedef InAppDownloadFileSaver =
    Future<String?> Function({
      required String fileName,
      required File sourceFile,
    });
typedef InAppDownloadFileOpener =
    Future<bool> Function({required String path, required String fileName});

/// Shared application-internal file download capability for built-in apps.
///
/// Network access remains behind the host session layer. The capability only owns the
/// generic download-to-temporary-file, user-visible persistence, and open-file
/// flow; it does not expose cookies or credentials to callers.
class InAppDownloadCapability {
  static final _publicHttpClient = PublicHttpClient();

  final InAppDownloadTemporaryDirectoryProvider? _temporaryDirectoryProvider;
  final InAppDownloadFileSaver? _fileSaver;
  final InAppDownloadFileOpener? _fileOpener;

  const InAppDownloadCapability({
    InAppDownloadTemporaryDirectoryProvider? temporaryDirectoryProvider,
    InAppDownloadFileSaver? fileSaver,
    InAppDownloadFileOpener? fileOpener,
  }) : _temporaryDirectoryProvider = temporaryDirectoryProvider,
       _fileSaver = fileSaver,
       _fileOpener = fileOpener;

  Future<InAppDownloadedFile> download({
    required Uri url,
    required String fileName,
    Map<String, String> extraHeaders = const {},
    CampusServiceId? serviceId,
    Duration requestTimeout = const Duration(seconds: 60),
    Duration responseTimeout = const Duration(seconds: 60),
    bool followRedirects = false,
    ValueChanged<InAppDownloadProgress>? onProgress,
  }) async {
    _validateUrl(url);
    if (kIsWeb) {
      throw const InAppDownloadException(
        InAppDownloadErrorType.unsupportedPlatform,
      );
    }

    final safeName = _safeFileName(fileName);
    final temporaryFile = await _createTemporaryFile();
    try {
      final response = await _downloadToTemporaryFile(
        url: url,
        destination: temporaryFile,
        extraHeaders: extraHeaders,
        serviceId: serviceId,
        requestTimeout: requestTimeout,
        responseTimeout: responseTimeout,
        followRedirects: followRedirects,
        onProgress: onProgress,
      );
      if (response.statusCode < HttpStatus.ok ||
          response.statusCode >= HttpStatus.multipleChoices) {
        throw InAppDownloadException(
          InAppDownloadErrorType.http,
          statusCode: response.statusCode,
        );
      }

      final sizeBytes = await temporaryFile.length();
      final savedPath = await (_fileSaver ??
          FileSaveService.saveFileToDownloads)(
        fileName: safeName,
        sourceFile: temporaryFile,
      );
      if (savedPath == null || savedPath.isEmpty) {
        throw const InAppDownloadException(InAppDownloadErrorType.storage);
      }
      return InAppDownloadedFile(
        path: savedPath,
        fileName: _fileNameFromPath(savedPath, safeName),
        sizeBytes: sizeBytes,
      );
    } on InAppDownloadException {
      rethrow;
    } catch (error) {
      AppLogger.warn('应用内下载失败 (${error.runtimeType})');
      throw const InAppDownloadException(InAppDownloadErrorType.storage);
    } finally {
      try {
        if (await temporaryFile.exists()) await temporaryFile.delete();
      } catch (error) {
        AppLogger.warn('应用内下载临时文件清理失败 (${error.runtimeType})');
      }
    }
  }

  /// Opens a saved file with the platform's system file-handler chooser.
  Future<bool> open(InAppDownloadedFile file) => (_fileOpener ??
      FileSaveService.openFile)(path: file.path, fileName: file.fileName);

  Future<_DownloadResponse> _downloadToTemporaryFile({
    required Uri url,
    required File destination,
    required Map<String, String> extraHeaders,
    required CampusServiceId? serviceId,
    required Duration requestTimeout,
    required Duration responseTimeout,
    required bool followRedirects,
    required ValueChanged<InAppDownloadProgress>? onProgress,
  }) async {
    try {
      final effectiveServiceId = serviceId ?? inferRegisteredCampusService(url);

      void reportProgress(int receivedBytes, int? totalBytes, int attempt) {
        onProgress?.call(
          InAppDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            attempt: attempt,
          ),
        );
      }

      if (effectiveServiceId == null) {
        final response = await _publicHttpClient.downloadToFile(
          url,
          destination: destination,
          headers: extraHeaders.isEmpty ? null : extraHeaders,
          requestTimeout: requestTimeout,
          responseTimeout: responseTimeout,
          followRedirects: followRedirects,
          onProgress: reportProgress,
        );
        return _DownloadResponse(response.statusCode);
      }
      final response = await CampusSession.client(
        effectiveServiceId,
      ).downloadToFile(
        url.toString(),
        destination: destination,
        extraHeaders: extraHeaders.isEmpty ? null : extraHeaders,
        requestTimeout: requestTimeout,
        responseTimeout: responseTimeout,
        followRedirects: followRedirects,
        onProgress: reportProgress,
      );
      return _DownloadResponse(response.statusCode);
    } catch (error) {
      AppLogger.warn('应用内下载网络请求失败 (${error.runtimeType})');
      throw const InAppDownloadException(InAppDownloadErrorType.network);
    }
  }

  static CampusServiceId? inferRegisteredCampusService(Uri url) {
    final serviceId = CampusServiceEndpoints.serviceIdForHost(url.host);
    if (serviceId == null) return null;
    final definition = CampusServiceEndpoints.definitionFor(serviceId);
    if (definition == null || !definition.allowsUri(url)) return null;
    return serviceId;
  }

  Future<File> _createTemporaryFile() async {
    try {
      final directory =
          await (_temporaryDirectoryProvider ?? getTemporaryDirectory)();
      return File(
        '${directory.path}${Platform.pathSeparator}'
        '.mychu-download-${DateTime.now().microsecondsSinceEpoch}.part',
      );
    } catch (error) {
      AppLogger.warn('应用内下载临时目录不可用 (${error.runtimeType})');
      throw const InAppDownloadException(InAppDownloadErrorType.storage);
    }
  }

  static void _validateUrl(Uri url) {
    final scheme = url.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || url.host.isEmpty) {
      throw const InAppDownloadException(InAppDownloadErrorType.invalidUrl);
    }
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

  static String _fileNameFromPath(String path, String fallback) {
    if (path.startsWith('content://')) return fallback;
    final normalized = path.replaceAll('\\', '/');
    final last = normalized.substring(normalized.lastIndexOf('/') + 1).trim();
    return last.isEmpty || last == '.' || last == '..' ? fallback : last;
  }
}

class _DownloadResponse {
  final int statusCode;

  const _DownloadResponse(this.statusCode);
}
