import 'package:flutter/foundation.dart';

@immutable
class NetworkOnlineSession {
  final String ipAddress;
  final String onlineAt;
  final String packageName;
  final String macAddress;

  const NetworkOnlineSession({
    required this.ipAddress,
    required this.onlineAt,
    required this.packageName,
    required this.macAddress,
  });
}

@immutable
class NetworkPackageUsage {
  final String packageName;
  final String usedTraffic;
  final String balance;
  final String settlementDate;

  const NetworkPackageUsage({
    required this.packageName,
    required this.usedTraffic,
    required this.balance,
    required this.settlementDate,
  });
}

@immutable
class NetworkSelfServiceOverview {
  final List<NetworkOnlineSession> onlineSessions;
  final List<NetworkPackageUsage> packages;

  const NetworkSelfServiceOverview({
    required this.onlineSessions,
    required this.packages,
  });

  const NetworkSelfServiceOverview.empty()
    : onlineSessions = const [],
      packages = const [];
}

class NetworkSelfServiceAuthenticationRequiredException implements Exception {
  const NetworkSelfServiceAuthenticationRequiredException();
}

class NetworkSelfServiceParseException implements Exception {
  final String message;

  const NetworkSelfServiceParseException(this.message);
}
