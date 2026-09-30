import 'campus_service_id.dart';
import 'campus_service_policies.dart';

export 'campus_service_id.dart';
export 'campus_service_policies.dart';

/// Identity routing mode for a shared campus service target.
///
/// The two academic targets and the information portal have explicit route
/// selection. Other authenticated targets keep their historical address for
/// both student identities. Manual-login sites are intentionally not targets
/// in this enum and are documented separately by the app layer.
enum CampusServiceRouteKind { identitySpecific, sharedLegacy }

/// How a campus request is selected for the current account.
///
/// [explicit] and [legacyFallback] cover registered authenticated services;
/// [pending] is used by feature-level adapters that must not issue a request;
/// [manual] describes sites that intentionally keep their own WebView login.
enum CampusRouteDisposition { explicit, legacyFallback, pending, manual }

/// How an authenticated WebView obtains its first service page.
///
/// Most services expose a server-side CAS/OIDC entry that can be exchanged
/// before a WebView exists. Some static SPA shells instead start their own
/// browser redirect after JavaScript boots; those pages only need the current
/// root identity cookies materialized before the public entry is loaded.
enum WebViewBootstrapMode { serviceSession, browserRelay }

sealed class CampusRouteResolver {
  const CampusRouteResolver();
}

class StaticCampusRouteResolver extends CampusRouteResolver {
  const StaticCampusRouteResolver();
}

class IdentityCampusRouteResolver extends CampusRouteResolver {
  const IdentityCampusRouteResolver();
}

/// A manual-login site is deliberately outside the shared credential/session
/// layer, but it still belongs in the central route inventory so a new plugin
/// cannot silently become an unclassified campus endpoint.
class CampusManualServiceDefinition {
  final String id;
  final String entryUrl;

  const CampusManualServiceDefinition({
    required this.id,
    required this.entryUrl,
  });

  CampusRouteDisposition get disposition => CampusRouteDisposition.manual;
}

/// 声明式校园服务定义：新增一个服务 = 在 [CampusServiceEndpoints.definitions]
/// 里加一行数据，底层无需再写一份换票函数。
class CampusServiceDefinition {
  final CampusServiceId id;

  /// Whether the service address changes with the resolved student identity.
  final CampusServiceRouteKind routeKind;

  /// 服务主机（必须属于 `*.chd.edu.cn`）。
  final String host;

  /// Optional TCP port for services that share a host with another entry
  /// point. A null value keeps the historical default-port behaviour.
  final int? port;

  /// Additional hosts that belong to the same declared service, such as the
  /// identity realm used by the root session.
  final List<String> additionalHosts;

  /// 换票起始 URL：服务端会把它 302 到统一身份认证（CAS 或 OIDC）。
  final Uri startUri;

  /// 收集/播种服务凭证的基准 URL。
  final Uri seedUri;

  /// Cookie path used when restoring a persisted service session.
  final String cookiePath;

  /// 可选校验探针：GET 该地址期望 HTTP 200，确认换到的会话可用。
  final Uri? validationUri;

  /// Allowed request path prefixes for this service. The shared request
  /// boundary uses this list for host/path validation and WebView bootstraps.
  final List<String> allowedPaths;

  /// Whether this definition represents the root unified-identity session.
  /// Root cookies are persisted in the root jar rather than a service jar.
  final bool rootIdentity;

  /// Paths whose CAS service parameter must be the concrete request URI
  /// instead of the canonical service entry point.
  final List<String> exactExchangePaths;

  /// Whether the host can acquire a target session before creating the
  /// WebView, or must let a declared SPA continue the identity redirect.
  final WebViewBootstrapMode webViewBootstrapMode;

  /// Whether each WebView launch must first use the fresh terminal URL
  /// returned by the exchange to establish a session, then load its declared
  /// target URL (for example a short-lived access-token login URL).
  final bool webViewUsesSessionUri;

  /// Proactive refresh threshold for reusing a derived service session.
  /// This is an app-side refresh policy, not a claim about server expiry.
  final Duration? sessionRefreshAfter;

  final AuthenticationPolicy authentication;
  final SessionMaterializer? _sessionMaterializer;
  final SessionScope? _sessionScope;
  final Map<String, SessionScope> scopedPaths;
  final AuthFailurePolicy authFailurePolicy;
  final ValidationPolicy? _validationPolicy;
  final TransportPolicy transportPolicy;

  CampusServiceDefinition({
    required this.id,
    this.routeKind = CampusServiceRouteKind.sharedLegacy,
    required this.host,
    this.port,
    this.additionalHosts = const [],
    required this.startUri,
    required this.seedUri,
    this.cookiePath = '/',
    this.validationUri,
    this.allowedPaths = const ['/'],
    this.rootIdentity = false,
    this.exactExchangePaths = const [],
    this.webViewBootstrapMode = WebViewBootstrapMode.serviceSession,
    this.webViewUsesSessionUri = false,
    this.sessionRefreshAfter,
    this.scopedPaths = const {},
    this.authentication = const FederatedAuthentication(ChdIdentityProvider()),
    SessionMaterializer? sessionMaterializer,
    SessionScope? sessionScope,
    this.authFailurePolicy = const NoStatusAuthFailure(),
    ValidationPolicy? validationPolicy,
    this.transportPolicy = const TransportPolicy(),
  }) : _sessionMaterializer = sessionMaterializer,
       _sessionScope = sessionScope,
       _validationPolicy = validationPolicy;

  Uri get entryUri => startUri;

  List<String> get hosts => [host, ...additionalHosts];

  bool allowsUri(Uri uri) {
    final normalizedHost = uri.host.toLowerCase();
    if (!hosts.any((candidate) => candidate.toLowerCase() == normalizedHost)) {
      return false;
    }
    if (port != null && uri.port != port) return false;
    return allowedPaths.any((prefix) => _pathMatchesPrefix(uri.path, prefix));
  }

  /// The canonical exchange entry may be a CAS/OIDC URL on an identity host.
  /// Caller-provided WebView entry URLs still have to match the service host
  /// and declared path policy through [allowsUri].
  bool allowsExchangeStartUri(Uri uri) => uri == startUri || allowsUri(uri);

  bool usesExactExchangeFor(Uri uri) =>
      exactExchangePaths.any((prefix) => _pathMatchesPrefix(uri.path, prefix));

  SessionScope get sessionScope =>
      _sessionScope ??
      (cookiePath == '/'
          ? const ServiceSessionScope()
          : PathPrefixSessionScope(cookiePath));

  SessionScope scopeFor(Uri uri) {
    final matching = <MapEntry<String, SessionScope>>[
      for (final entry in scopedPaths.entries)
        if (_pathMatchesPrefix(uri.path, entry.key)) entry,
    ]..sort((a, b) => b.key.length.compareTo(a.key.length));
    if (matching.isNotEmpty) {
      return matching.first.value;
    }
    return sessionScope;
  }

  /// All scopes that a redirect event can target for this definition.
  /// Capturing these generations at exchange start prevents an exact/path
  /// exchange from writing a different scope after that scope was invalidated.
  Set<String> get sessionScopeKeys => {
    sessionScope.key,
    ...scopedPaths.values.map((scope) => scope.key),
  };

  SessionMaterializer get sessionMaterializer =>
      _sessionMaterializer ?? const CookieMaterializer();

  ValidationPolicy get validationPolicy =>
      _validationPolicy ??
      (validationUri == null
          ? const NoValidationPolicy()
          : const HttpStatusValidation());

  CampusRouteResolver get routeResolver =>
      routeKind == CampusServiceRouteKind.identitySpecific
          ? const IdentityCampusRouteResolver()
          : const StaticCampusRouteResolver();

  CampusRouteDisposition get disposition =>
      routeKind == CampusServiceRouteKind.identitySpecific
          ? CampusRouteDisposition.explicit
          : CampusRouteDisposition.legacyFallback;

  static bool _pathMatchesPrefix(String path, String prefix) {
    if (prefix == '/') return true;
    final normalized =
        prefix.endsWith('/') ? prefix.substring(0, prefix.length - 1) : prefix;
    return path == normalized || path.startsWith('$normalized/');
  }
}

/// Central campus service endpoint registry.
///
/// Host→service ID、service ID→seed URI、声明式服务定义与共享 CAS/OIDC 登录 URI 都
/// 集中在这里，新增一个校园服务只改本文件。
class CampusServiceEndpoints {
  CampusServiceEndpoints._();

  static const idsAuthBase = 'https://ids.chd.edu.cn';
  static const portalBase = 'https://portal.chd.edu.cn';
  static const courseBase = 'https://course-online.chd.edu.cn';
  static const tronclassMobileBase = 'https://mobile2.chd.edu.cn';
  static const classroomRecordingBase = 'https://zlb.chd.edu.cn';
  static const sportsPortalBase = 'https://stuh5.chd.edu.cn';
  static const academicAffairsBase = 'http://bkjw.chd.edu.cn';
  static const graduateAcademicAffairsBase = 'https://yjs.chd.edu.cn';
  static const campusAppBase = 'https://gwwzxy.chd.edu.cn';
  static const roomisBase = 'https://roomis.chd.edu.cn';
  static const opacBase = 'http://opac.chd.edu.cn';
  static const qualityAssuranceBase = 'https://jxzlpj.chd.edu.cn';
  static const mobileCampusBase = 'https://app.chd.edu.cn';
  static const commuterBusBase = 'https://bus.chd.edu.cn';
  static const networkSelfServiceBase = 'https://wlfw.chd.edu.cn:8800';

  static final idsAuthUri = Uri.parse('$idsAuthBase/authserver/');

  /// Keycloak realm 根：OIDC 流程（如 roomis）走 identity 域，
  /// 登录页收集的 realm 会话 Cookie（AUTH_SESSION_ID 等）需在此域下发。
  static final identityRealmUri = Uri.parse(
    'https://identity.chd.edu.cn/auth/realms/chd',
  );
  static final portalLoginUri = Uri.parse('$portalBase/login');
  static final portalGetLoginUserUri = Uri.parse('$portalBase/getLoginUser');
  static final portalUserAndGuestUri = Uri.parse(
    '$portalBase/getLoginUserAndGuest',
  );
  static final portalPermissionsUri = Uri.parse(
    '$portalBase/getUserPermissionRouters',
  );
  static final portalSiteSwitchUri = Uri.parse(
    '$portalBase/queryUserSiteWitching',
  );
  static final portalPageViewUri = Uri.parse('$portalBase/getPageView');
  static final portalOriginUri = Uri.parse(portalBase);
  static Uri portalCardMethodUri(String cardWid, String cardId) =>
      Uri.https(Uri.parse(portalBase).host, '/execCardMethod/$cardWid/$cardId');
  static final courseLoginUri = Uri.parse(
    '$courseBase/login?next=%2Fuser%2Findex',
  );
  static final courseProfileUri = Uri.parse('$courseBase/api/profile');
  static final tronclassMobileHomeUri = Uri.parse('$tronclassMobileBase/');
  static final classroomRecordingHomeUri = Uri.parse(
    '$classroomRecordingBase/jy-mobile-resourcemanage-ui/',
  );
  static final sportsPortalHomeUri = Uri.parse('$sportsPortalBase/');
  static final classroomRecordingLiveListUri = Uri.parse(
    '$classroomRecordingHomeUri#/liveList',
  );
  static final academicAffairsHomeUri = Uri.parse(
    '$academicAffairsBase/eams/home.action',
  );
  static final graduateAcademicAffairsHomeUri = Uri.parse(
    '$graduateAcademicAffairsBase/py/page/student/grkcgl.htm',
  );
  static final graduateScheduleUri = Uri.parse(
    '$graduateAcademicAffairsBase/py/page/student/grkcb.htm',
  );
  static final graduateExamUri = Uri.parse(
    '$graduateAcademicAffairsBase/py/page/student/grksap.htm',
  );
  static final academicHistoryGradeUri = Uri.parse(
    '$academicAffairsBase/eams/teach/grade/course/'
    'person!historyCourseGrade.action?projectType=MAJOR',
  );
  static final academicExamUri = Uri.parse(
    '$academicAffairsBase/eams/stdExamTable.action',
  );
  static final academicExamDetailUri = Uri.parse(
    '$academicAffairsBase/eams/stdExamTable!examTable.action',
  );
  static final academicSyllabusUri = Uri.parse(
    '$academicAffairsBase/eams/stdSyllabus.action',
  );
  static final academicSyllabusSearchUri = Uri.parse(
    '$academicAffairsBase/eams/stdSyllabus!search.action',
  );
  static final academicSyllabusDataQueryUri = Uri.parse(
    '$academicAffairsBase/eams/dataQuery.action',
  );
  static final graduateGradesUri = Uri.parse(
    '$graduateAcademicAffairsBase/py/page/student/cjgrcx.htm',
  );
  static final graduateSyllabusUri = Uri.parse(
    '$graduateAcademicAffairsBase/py/page/student/lnsjCxdc.htm',
  );
  static final campusCasLoginUri = Uri.parse(
    '$campusAppBase/basicinfo/mobile/login/casLogin?openId=&unionId=',
  );
  static final idsLoginForCampusUri = Uri.parse(
    '$idsAuthBase/authserver/login?service='
    '${Uri.encodeComponent(campusCasLoginUri.toString())}',
  );
  static final campusHomeAppsUri = Uri.parse(
    '$campusAppBase/basicinfo/mobile/home/getHomeApps?env=0',
  );
  static final campusHomePageUri = Uri.parse(
    '$campusAppBase/h5/mobile/basicinfo/index/home/homeStudent',
  );
  static final campusAppOriginUri = Uri.parse(campusAppBase);
  static final campusAppH5RouteBaseUri = Uri.parse(
    '$campusAppBase/h5/mobile/basicinfo/index',
  );
  static final roomisBuildingsUri = Uri.parse(
    '$roomisBase/console/buildings/json',
  );
  static final roomisBookingSpacesUri = Uri.parse(
    '$roomisBase/console/booking/spaces',
  );
  static final roomisSpacesUri = Uri.parse(
    '$roomisBase/console/booking/spaces/json',
  );
  static final opacHomeUri = Uri.parse('$opacBase/');
  static final libraryPublicIpStatusUri = Uri.parse(
    'https://lib.chd.edu.cn/entry/user/getUserIpAndCheck',
  );
  // 评教系统（商鼎）会话 URL 换票入口：ids CAS 登录后直接 302 到
  // `#/pages/login/caslogin?userToken=…`，仅供认证 WebView 打开。
  static final qualityAssuranceCasUrl = Uri.parse(
    'https://jxzlpj.chd.edu.cn:8080/api/manage/cas/toUrl?type=mobile',
  );
  static const mobileCampusSchoolId = 138;
  static const mobileCampusSdkAppKey = '86fe3650';
  static final idsMobileCallbackUri = Uri.parse(
    '$idsAuthBase/authserver/mobile/callback?appId=963450004020658176',
  );

  /// 移动校园统一身份授权入口：外层 login 必须把 callback 编码成 service，
  /// 并带 `login_type=mobileLogin`，否则拿不到 mobile_code。
  static final idsMobileCallbackLoginUri = Uri.parse(
    '$idsAuthBase/authserver/login?service='
    '${Uri.encodeComponent(idsMobileCallbackUri.toString())}'
    '&login_type=mobileLogin',
  );
  static final mobileCampusWmaLoginUri = Uri.parse(
    '$mobileCampusBase/casCampus_wma/chd/$mobileCampusSchoolId/login',
  );
  static final mobileCampusVerifyUri = Uri.parse(
    '$mobileCampusBase/baseCampus/sdkOpen/verifyWithoutToken.do',
  );
  static final mobileCampusSkipLoginUri = Uri.parse(
    '$mobileCampusBase/baseCampus/login/skipLogin.do',
  );
  static final mobileCampusUserInfoUri = Uri.parse(
    '$mobileCampusBase/baseCampus/user/getUserInfo.do',
  );
  static const mobileCampusMessageBase = '$mobileCampusBase/newsCampus/message';
  static final mobileCampusCalendarTermsUri = Uri.parse(
    '$mobileCampusBase/oaCampus/sc/getXnXq.do',
  );
  static final mobileCampusCalendarDataUri = Uri.parse(
    '$mobileCampusBase/oaCampus/sc/getSchoolTime.do',
  );
  static final commuterBusLoginUri = Uri.parse(
    '$commuterBusBase/bus-api/v1/login',
  );
  static final commuterBusGetInfoUri = Uri.parse(
    '$commuterBusBase/bus-api/v1/getInfo',
  );
  static final commuterBusSelectUri = Uri.parse('$commuterBusBase/bus/select');
  static final networkSelfServiceLoginUri = Uri.parse(
    '$networkSelfServiceBase/',
  );
  static final networkSelfServiceHomeUri = Uri.parse(
    '$networkSelfServiceBase/home',
  );
  static final networkSelfServiceCaptchaUri = Uri.parse(
    '$networkSelfServiceBase/site/captcha',
  );
  static final networkSelfServiceValidateUserUri = Uri.parse(
    '$networkSelfServiceBase/site/validate-user',
  );
  static final networkSelfServiceValidateSmsUri = Uri.parse(
    '$networkSelfServiceBase/site/validate-smscode',
  );

  static final manualServiceDefinitions = [
    const CampusManualServiceDefinition(
      id: 'campus.network',
      entryUrl: 'https://wlfw.chd.edu.cn',
    ),
    const CampusManualServiceDefinition(
      id: 'second.classroom',
      entryUrl: 'https://win.9xueqi.com/#/home',
    ),
    const CampusManualServiceDefinition(
      id: 'trusted.docs',
      entryUrl: 'https://kxwdk.chd.edu.cn/index.html',
    ),
    const CampusManualServiceDefinition(
      id: 'xuexin',
      entryUrl: 'https://account.chsi.com.cn/passport/login',
    ),
    const CampusManualServiceDefinition(
      id: 'channel.resources',
      entryUrl: 'https://qbot.evian.asia/',
    ),
  ];

  static final _identitySpecificServices = {
    CampusServices.informationPortal,
    CampusServices.academicAffairs,
    CampusServices.graduateAcademicAffairs,
  };

  static const Map<String, CampusServiceId> _servicesByHost = {
    'portal.chd.edu.cn': CampusServices.informationPortal,
    'course-online.chd.edu.cn': CampusServices.courseOnline,
    'mobile2.chd.edu.cn': CampusServices.tronclassMobile,
    'zlb.chd.edu.cn': CampusServices.classroomRecording,
    'stuh5.chd.edu.cn': CampusServices.sportsPortal,
    'bkjw.chd.edu.cn': CampusServices.academicAffairs,
    'yjs.chd.edu.cn': CampusServices.graduateAcademicAffairs,
    'gwwzxy.chd.edu.cn': CampusServices.campusApp,
    'roomis.chd.edu.cn': CampusServices.roomReservation,
    'opac.chd.edu.cn': CampusServices.libraryOpac,
    'jxzlpj.chd.edu.cn': CampusServices.qualityAssurance,
    'app.chd.edu.cn': CampusServices.mobileCampus,
    'bus.chd.edu.cn': CampusServices.commuterBus,
    'wlfw.chd.edu.cn': CampusServices.networkSelfService,
    'ids.chd.edu.cn': CampusServices.unifiedIdentity,
    'identity.chd.edu.cn': CampusServices.unifiedIdentity,
  };

  /// 声明式服务注册表：换票引擎按这里的定义执行，不写服务专用代码。
  static final List<CampusServiceDefinition> definitions = [
    CampusServiceDefinition(
      id: CampusServices.unifiedIdentity,
      host: 'ids.chd.edu.cn',
      additionalHosts: const ['identity.chd.edu.cn'],
      startUri: idsAuthUri,
      seedUri: idsAuthUri,
      rootIdentity: true,
      authentication: const PublicAuthentication(),
    ),
    CampusServiceDefinition(
      id: CampusServices.informationPortal,
      routeKind: CampusServiceRouteKind.identitySpecific,
      host: 'portal.chd.edu.cn',
      startUri: portalLoginUri,
      seedUri: portalLoginUri,
      sessionRefreshAfter: const Duration(hours: 24),
      allowedPaths: const ['/', '/qljfwapp/'],
      exactExchangePaths: const ['/qljfwapp/'],
      scopedPaths: const {'/qljfwapp/': PathPrefixSessionScope('/qljfwapp/')},
    ),
    CampusServiceDefinition(
      id: CampusServices.courseOnline,
      host: 'course-online.chd.edu.cn',
      startUri: courseLoginUri,
      seedUri: courseLoginUri,
      validationUri: courseProfileUri,
      sessionMaterializer: const CompositeMaterializer([
        CookieMaterializer(),
        HeaderFromCookie(
          cookieName: 'sessionid',
          fallbackCookieName: 'session_id',
          headerName: 'x-session-id',
        ),
      ]),
    ),
    // 畅课移动端：静态 SPA 启动后才发起 OAuth/CAS，宿主先播种根身份。
    CampusServiceDefinition(
      id: CampusServices.tronclassMobile,
      host: 'mobile2.chd.edu.cn',
      startUri: tronclassMobileHomeUri,
      seedUri: tronclassMobileHomeUri,
      webViewBootstrapMode: WebViewBootstrapMode.browserRelay,
    ),
    // 课堂实录：静态 SPA 启动后才发起 OAuth/CAS，宿主先播种根身份。
    CampusServiceDefinition(
      id: CampusServices.classroomRecording,
      host: 'zlb.chd.edu.cn',
      startUri: classroomRecordingHomeUri,
      seedUri: classroomRecordingHomeUri,
      webViewBootstrapMode: WebViewBootstrapMode.browserRelay,
    ),
    // 长大体育：根页由静态 SPA 发起统一身份 OAuth，宿主播种根身份并辅助完成授权页。
    CampusServiceDefinition(
      id: CampusServices.sportsPortal,
      host: 'stuh5.chd.edu.cn',
      startUri: sportsPortalHomeUri,
      seedUri: sportsPortalHomeUri,
      allowedPaths: const ['/'],
      webViewBootstrapMode: WebViewBootstrapMode.browserRelay,
    ),
    CampusServiceDefinition(
      id: CampusServices.academicAffairs,
      routeKind: CampusServiceRouteKind.identitySpecific,
      host: 'bkjw.chd.edu.cn',
      startUri: academicAffairsHomeUri,
      seedUri: academicAffairsHomeUri,
      sessionRefreshAfter: const Duration(hours: 3),
      validationUri: academicAffairsHomeUri,
      cookiePath: '/eams',
      allowedPaths: const ['/eams'],
      sessionScope: const PathPrefixSessionScope('/eams'),
      transportPolicy: const TransportPolicy(
        closeConnection: true,
        serializationKey: 'academic-affairs',
        postExchangeSettle: Duration(milliseconds: 1200),
      ),
    ),
    CampusServiceDefinition(
      id: CampusServices.graduateAcademicAffairs,
      routeKind: CampusServiceRouteKind.identitySpecific,
      host: 'yjs.chd.edu.cn',
      startUri: graduateAcademicAffairsHomeUri,
      seedUri: graduateAcademicAffairsHomeUri,
      sessionRefreshAfter: const Duration(hours: 3),
      validationUri: graduateAcademicAffairsHomeUri,
      cookiePath: '/py',
      allowedPaths: const ['/py'],
      sessionScope: const PathPrefixSessionScope('/py'),
      transportPolicy: const TransportPolicy(
        closeConnection: true,
        serializationKey: 'graduate-academic-affairs',
        postExchangeSettle: Duration(milliseconds: 1200),
      ),
    ),
    CampusServiceDefinition(
      id: CampusServices.campusApp,
      host: 'gwwzxy.chd.edu.cn',
      startUri: idsLoginForCampusUri,
      seedUri: campusHomeAppsUri,
      validationPolicy: const CampusHomeValidation(),
      sessionMaterializer: const CompositeMaterializer([
        CookieMaterializer(),
        HeaderFromCookie(cookieName: 'JWSESSION', headerName: 'JWSESSION'),
      ]),
      authFailurePolicy: const CompositeAuthFailurePolicy([
        StatusAuthFailure({401, 403}),
        JsonAuthFailure([
          '"code":401',
          '"code":"401"',
          '"code":403',
          '"code":"403"',
          '"code":103',
          '"code":"103"',
          '"msg":"未登录"',
          '"msg":"登录失效"',
        ]),
      ]),
      transportPolicy: const TransportPolicy(
        // getHomeApps is a read-only endpoint implemented as POST. It is
        // safe to replay once after the service session is refreshed.
        replaySafePostPaths: ['/basicinfo/mobile/home/getHomeApps'],
      ),
    ),
    // 教室管理平台：走 identity 域 OIDC 授权重定向链，但收尾仍为收集服务域
    // Cookie（Kong 服务端会话模式），与其他服务共用同一条 Cookie 引擎。
    CampusServiceDefinition(
      id: CampusServices.roomReservation,
      host: 'roomis.chd.edu.cn',
      startUri: roomisSpacesUri,
      seedUri: roomisSpacesUri,
      validationUri: roomisBuildingsUri,
    ),
    // 图书馆服务（OPAC）：普通 CAS 换票，“收 Cookie”收尾。
    CampusServiceDefinition(
      id: CampusServices.libraryOpac,
      host: 'opac.chd.edu.cn',
      startUri: opacHomeUri,
      seedUri: opacHomeUri,
    ),
    // 评教系统（商鼎）：换票以“会话 URL”收尾（caslogin userToken 入口），
    // 由认证 WebView 打开；不走通用“收 Cookie”引擎，见换票引擎的会话 URL
    // 分支（跟随 CAS 重定向并捕获最终 URL）。
    CampusServiceDefinition(
      id: CampusServices.qualityAssurance,
      host: 'jxzlpj.chd.edu.cn',
      startUri: qualityAssuranceCasUrl,
      seedUri: qualityAssuranceCasUrl,
      sessionMaterializer: const WebViewSessionMaterializer(),
    ),
    // 移动校园：统一身份移动授权后由 Bootstrap Adapter 完成 WMA/SDK/skipLogin
    // 流程，最终把业务 token 作为受限 SessionMaterializer 投影。
    CampusServiceDefinition(
      id: CampusServices.mobileCampus,
      host: 'app.chd.edu.cn',
      startUri: mobileCampusUserInfoUri,
      seedUri: mobileCampusUserInfoUri,
      sessionMaterializer: const CustomPostSsoBootstrap(
        CampusServices.mobileCampus,
      ),
      authFailurePolicy: const JsonAuthFailure([
        '"code":401',
        '"code":"401"',
        '"tokenExpired":true',
        '"msg":"未登录"',
      ]),
    ),
    // 通勤车网页：CAS 重定向最终回带 access_token；认证 WebView 先使用
    // 该次换票的短时最终 URL 建立网页会话，再加载应用声明的业务目标页。
    CampusServiceDefinition(
      id: CampusServices.commuterBus,
      host: 'bus.chd.edu.cn',
      startUri: commuterBusLoginUri,
      seedUri: commuterBusGetInfoUri,
      validationUri: commuterBusGetInfoUri,
      webViewUsesSessionUri: true,
      sessionMaterializer: const CompositeMaterializer([
        CookieMaterializer(),
        TokenFromRedirect(
          queryParameter: 'access_token',
          headerName: 'Authorization',
          prefix: 'Bearer ',
        ),
      ]),
    ),
    CampusServiceDefinition(
      id: CampusServices.networkSelfService,
      host: 'wlfw.chd.edu.cn',
      port: 8800,
      startUri: networkSelfServiceLoginUri,
      seedUri: networkSelfServiceHomeUri,
      validationUri: networkSelfServiceHomeUri,
      authentication: const SavedIdentityPasswordAuthentication(),
      authFailurePolicy: const CompositeAuthFailurePolicy([
        LoginHtmlAuthFailure(['loginform-username', 'site/validate-user']),
        RedirectAuthFailure({'wlfw.chd.edu.cn'}),
      ]),
      sessionMaterializer: const CookieMaterializer(),
    ),
  ];

  static CampusServiceId? serviceIdForHost(String host) {
    return _servicesByHost[host.toLowerCase()];
  }

  static AuthFailurePolicy authFailurePolicyFor(CampusServiceId serviceId) {
    final definition = definitionFor(serviceId);
    return definition?.authFailurePolicy ?? const NoStatusAuthFailure();
  }

  /// Returns the route mode for every authenticated service. A service
  /// not listed as identity-specific deliberately retains the original
  /// endpoint for both undergraduate and graduate accounts.
  static CampusServiceRouteKind routeKindFor(CampusServiceId serviceId) =>
      _identitySpecificServices.contains(serviceId)
          ? CampusServiceRouteKind.identitySpecific
          : CampusServiceRouteKind.sharedLegacy;

  /// Returns the four-state route disposition used by the central inventory.
  /// Academic feature-level pending routes are resolved by
  /// [AcademicAffairsBackendResolver], because they depend on the feature as
  /// well as the service.
  static CampusRouteDisposition dispositionFor(CampusServiceId serviceId) =>
      routeKindFor(serviceId) == CampusServiceRouteKind.identitySpecific
          ? CampusRouteDisposition.explicit
          : CampusRouteDisposition.legacyFallback;

  /// 换票引擎使用的服务定义；统一身份会话本身不参与换票，返回 null。
  static CampusServiceDefinition? definitionFor(CampusServiceId serviceId) {
    for (final definition in definitions) {
      if (definition.id == serviceId) return definition;
    }
    return null;
  }

  static CampusServiceDefinition? definitionForId(CampusServiceId id) {
    return definitionFor(id);
  }

  /// Base URI used to seed the account-scoped session jar for [serviceId].
  static Uri seedUriFor(CampusServiceId serviceId) {
    return definitionFor(serviceId)?.seedUri ?? idsAuthUri;
  }

  /// 服务中文标签（日志用）。
  static String labelFor(CampusServiceId? serviceId) {
    return switch (serviceId) {
      CampusServiceId(value: 'information-portal') => '门户服务',
      CampusServiceId(value: 'course-online') => '畅课服务',
      CampusServiceId(value: 'tronclass-mobile') => '畅课移动端服务',
      CampusServiceId(value: 'classroom-recording') => '课堂实录服务',
      CampusServiceId(value: 'sports-portal') => '长大体育服务',
      CampusServiceId(value: 'academic-affairs') => '教务服务',
      CampusServiceId(value: 'graduate-academic-affairs') => '研究生教务服务',
      CampusServiceId(value: 'campus-app') => '校园应用服务',
      CampusServiceId(value: 'room-reservation') => '教室管理服务',
      CampusServiceId(value: 'library-opac') => '图书馆服务',
      CampusServiceId(value: 'quality-assurance') => '评教服务',
      CampusServiceId(value: 'mobile-campus') => '移动校园服务',
      CampusServiceId(value: 'commuter-bus') => '通勤车服务',
      CampusServiceId(value: 'network-self-service') => '网络自服服务',
      CampusServiceId(value: 'unified-identity') => '统一认证服务',
      null => '校园服务',
      _ => serviceId.value,
    };
  }

  static bool isChdHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'chd.edu.cn' || normalized.endsWith('.chd.edu.cn');
  }
}
