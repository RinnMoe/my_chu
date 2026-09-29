import 'service_endpoints.dart';

/// The two student-facing information-portal page contexts currently exposed
/// by the campus portal.
enum PortalStudentType { undergraduate, graduate }

/// Identity-scoped routing metadata for information-portal APIs.
///
/// This class deliberately contains only non-secret endpoint and card
/// metadata. Credentials, cookies, account state and session recovery remain
/// owned by the shared networking layer.
class PortalRoute {
  static const undergraduate = PortalRoute(
    studentType: PortalStudentType.undergraduate,
    siteRoute: 'stu',
    personalDataCardWid: '8731199331630359',
  );

  static const graduate = PortalRoute(
    studentType: PortalStudentType.graduate,
    siteRoute: 'yjs',
    personalDataCardWid: '4973792429017263',
  );

  static const pageCode = 'grkj';

  final PortalStudentType studentType;
  final String siteRoute;
  final String personalDataCardWid;

  const PortalRoute({
    required this.studentType,
    required this.siteRoute,
    required this.personalDataCardWid,
  });

  /// Resolves only the supported student identities. Unknown identities must
  /// not silently use the undergraduate portal context.
  static PortalRoute? fromIdentity(String? identity) {
    final value = identity?.trim() ?? '';
    if (value.contains('研究生')) return graduate;
    if (value.contains('本科生')) return undergraduate;
    return null;
  }

  static PortalRoute forStudentType(PortalStudentType studentType) =>
      studentType == PortalStudentType.graduate ? graduate : undergraduate;

  String get pageBaseUrl =>
      '${CampusServiceEndpoints.portalBase}/$siteRoute/index.html';

  String get localPageUrl => '$pageBaseUrl#/$pageCode';

  /// The portal endpoint expects the original URL as an already escaped query
  /// value; [Uri.replace] applies the outer query escaping afterwards.
  String get encodedOriginalUrl => Uri.encodeComponent(localPageUrl);

  /// Headers used by the page bootstrap request. The portal sends this
  /// header as an already URL-encoded value, unlike the query value above
  /// which receives the outer escaping from [Uri.replace].
  Map<String, String> get pageViewHeaders => {
    'Referer': pageBaseUrl,
    'localPageUrl': Uri.encodeComponent(localPageUrl),
  };

  /// Headers used by card APIs. Card requests identify the active page with
  /// the referer; [localPageUrl] is a page-bootstrap-only header.
  Map<String, String> get cardHeaders => {'Referer': pageBaseUrl};

  /// Backwards-compatible alias for callers that need the page bootstrap
  /// headers.
  Map<String, String> get pageHeaders => {...pageViewHeaders};
}
