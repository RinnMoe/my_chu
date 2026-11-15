import 'package:url_launcher/url_launcher.dart';

import '../services/logging/logger.dart';

/// Opens channel-resource links after restricting them to ordinary web URLs.
class ChannelResourcesLinkCapability {
  final Future<bool> Function(Uri uri)? _externalOpener;

  const ChannelResourcesLinkCapability({
    Future<bool> Function(Uri uri)? externalOpener,
  }) : _externalOpener = externalOpener;

  Future<bool> open(Uri uri) async {
    if (!_isWebUri(uri)) return false;
    return (_externalOpener ?? _openExternally)(uri);
  }

  static Future<bool> _openExternally(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    }
  }

  static bool _isWebUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
  }
}
