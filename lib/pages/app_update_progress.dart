import '../capabilities/in_app_download/in_app_download.dart';

/// Detailed progress for the mandatory-update dialog.
String updateProgressLabel(InAppDownloadProgress? progress) {
  if (progress == null) return '正在准备下载…';
  switch (progress.phase) {
    case AppUpdatePhase.preparing:
      return '正在检查更新方式…';
    case AppUpdatePhase.merging:
      return '正在合成安装包…';
    case AppUpdatePhase.verifying:
      return '正在校验安装包…';
    case AppUpdatePhase.installing:
      return '正在唤起系统安装程序…';
    case AppUpdatePhase.downloadingPatch:
    case AppUpdatePhase.downloadingFull:
      final fraction = progress.fraction;
      if (fraction != null && fraction >= 1) {
        return '下载完成，正在处理安装包…';
      }
      if (fraction != null) {
        final label =
            progress.phase == AppUpdatePhase.downloadingPatch
                ? '正在下载更新补丁'
                : '正在下载安装包';
        return '$label ${(fraction * 100).floor()}%';
      }
      final bytes = progress.receivedBytes;
      final size =
          bytes < 1024
              ? '$bytes B'
              : bytes < 1024 * 1024
              ? '${(bytes / 1024).toStringAsFixed(1)} KB'
              : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '已下载 $size';
  }
}
