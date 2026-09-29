enum PortalInfoKind { campusCard, email, library, taskCenter }

typedef PortalPersonalDataLoader =
    Future<Map<PortalInfoKind, PortalPersonalInfo>> Function();
typedef PortalAccountIdLoader = Future<String?> Function();

class PortalPersonalInfo {
  final PortalInfoKind kind;
  final String title;
  final String mainInfo;
  final String subInfo;

  const PortalPersonalInfo({
    required this.kind,
    required this.title,
    required this.mainInfo,
    required this.subInfo,
  });

  String get homeValue {
    final primary = switch (kind) {
      PortalInfoKind.campusCard => subInfo,
      PortalInfoKind.email => mainInfo,
      PortalInfoKind.library => subInfo,
      PortalInfoKind.taskCenter => mainInfo,
    };
    return _numberIn(primary) ??
        _numberIn(mainInfo) ??
        _numberIn(subInfo) ??
        '—';
  }

  String? _numberIn(String value) =>
      RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value)?.group(0);

  String get homeLabel => switch (kind) {
    PortalInfoKind.campusCard => '余额',
    PortalInfoKind.email => '封未读',
    PortalInfoKind.library => '本未还',
    PortalInfoKind.taskCenter => '待办',
  };
}

class PortalPersonalDataSeed {
  final String id;
  final String title;
  final Object? extraInfo;
  final String mainInfo;
  final String subInfo;
  final bool needRetrieve;

  const PortalPersonalDataSeed({
    required this.id,
    required this.title,
    required this.extraInfo,
    this.mainInfo = '',
    this.subInfo = '',
    this.needRetrieve = true,
  });
}

class PortalAuthenticationException implements Exception {
  final String message;

  const PortalAuthenticationException([this.message = '门户登录状态已失效，请重新登录后重试。']);

  @override
  String toString() => message;
}

class PortalApiException implements Exception {
  final String message;

  const PortalApiException(this.message);

  @override
  String toString() => message;
}
