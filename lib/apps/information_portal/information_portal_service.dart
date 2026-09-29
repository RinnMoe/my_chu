import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../capabilities/account_scoped_cache.dart';
import '../../capabilities/alert_center.dart';
import '../../capabilities/alert_models.dart';
import '../../services/account_network_session_service.dart';
import '../../services/academic_affairs_backend.dart';
import '../../services/auth_service.dart';
import '../../services/campus_session.dart';
import '../../services/logger_service.dart';
import '../../services/portal_identity_service.dart';
import '../../services/portal_route_service.dart';
import '../../services/service_endpoints.dart';
import 'information_portal_models.dart';

/// Reads the small, privacy-conscious subset of data shown by the information
/// portal. It deliberately does not persist the returned personal data.
class PortalApiService {
  static const _balanceLowProviderId = 'portal_personal.balance_low';
  static const _unreadEmailProviderId = 'portal_personal.unread_email';

  /// 校园卡余额不足提醒提供者（订阅制）：余额低于订阅阈值时提醒。
  static final AlertProvider balanceLowAlertProvider = AlertProvider(
    id: _balanceLowProviderId,
    source: '个人数据',
    title: '校园卡余额不足',
    kind: AlertKind.condition,
    severity: AlertSeverity.warning,
    params: const [
      AlertParamSpec(
        key: 'threshold',
        label: '余额阈值',
        type: AlertParamType.number,
        defaultValue: 10,
        min: 1,
        max: 500,
        unit: '元',
      ),
    ],
    evaluate: (params, data) {
      final info =
          data is Map<PortalInfoKind, PortalPersonalInfo>
              ? data
              : const <PortalInfoKind, PortalPersonalInfo>{};
      final card = info[PortalInfoKind.campusCard];
      final amount = card == null ? null : double.tryParse(card.homeValue);
      if (amount == null) return const [];
      final threshold = (params['threshold'] as num?)?.toDouble() ?? 10;
      if (amount >= threshold) return const [];
      return [
        AlertDraft(
          fingerprintKey: 'balance_low',
          title: '校园卡余额不足',
          body: '当前余额 ${_formatAmount(amount)} 元，请及时充值',
          deeplinkAppId: 'feature.portal.personal',
        ),
      ];
    },
  );

  /// 未读邮件提醒提供者（订阅制）：存在未读邮件时提醒。
  static final AlertProvider unreadEmailAlertProvider = AlertProvider(
    id: _unreadEmailProviderId,
    source: '个人数据',
    title: '有未读邮件',
    kind: AlertKind.condition,
    severity: AlertSeverity.info,
    evaluate: (params, data) {
      final info =
          data is Map<PortalInfoKind, PortalPersonalInfo>
              ? data
              : const <PortalInfoKind, PortalPersonalInfo>{};
      final email = info[PortalInfoKind.email];
      final count = email == null ? null : int.tryParse(email.homeValue);
      if (count == null || count <= 0) return const [];
      return [
        AlertDraft(
          fingerprintKey: 'unread_email',
          title: '有 $count 封未读邮件',
          body: '打开邮箱查看最新邮件',
          deeplinkAppId: 'feature.portal.personal',
        ),
      ];
    },
  );

  static const _requestTimeout = Duration(seconds: 12);
  static const _bootstrapTtl = Duration(minutes: 5);
  static const _personalTtl = Duration(seconds: 60);

  static final AccountScopedCache<Map<PortalInfoKind, PortalPersonalInfo>>
  _personalCache = AccountScopedCache(ttl: _personalTtl);

  static final AccountScopedCache<_PortalPageContext>
  _personalPageBootstrapCache = AccountScopedCache<_PortalPageContext>(
    ttl: _bootstrapTtl,
    allowStale: false,
  );

  static final _portalUserAndGuestUri =
      CampusServiceEndpoints.portalUserAndGuestUri;
  static final _portalPermissionsUri =
      CampusServiceEndpoints.portalPermissionsUri;
  static final _portalSiteSwitchUri =
      CampusServiceEndpoints.portalSiteSwitchUri;
  static final _portalPageViewUri = CampusServiceEndpoints.portalPageViewUri;

  static const _personalDataCardId = 'CUS_CARD_CHU_PERSONALDATA';
  static const _taskCardId = 'CUS_CARD_CHU_TODOTASK';
  static const _taskCenterCardId = 'SYS_CARD_MYTASK';

  static String _accountCacheKey(String accountKey, PortalRoute route) =>
      '$accountKey|information_portal|${route.studentType.name}';

  @visibleForTesting
  static String cacheKeyFor(String accountKey, PortalRoute route) =>
      _accountCacheKey(accountKey, route);

  Future<Map<PortalInfoKind, PortalPersonalInfo>> fetchPersonalData({
    bool force = false,
  }) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) throw StateError('请先登录后再读取信息门户');
    final backend = await AcademicAffairsBackendResolver.resolveCurrent();
    final route = AcademicAffairsBackendResolver.routeFor(backend);
    final cacheKey = _accountCacheKey(account.accountKey, route);
    final info = await _personalCache.load(
      cacheKey,
      () => _fetchPersonalDataWithRecovery(account.accountKey, route),
      force: force,
    );
    unawaited(
      AlertCenterService.evaluate(
        account.accountKey,
        _balanceLowProviderId,
        info,
      ),
    );
    unawaited(
      AlertCenterService.evaluate(
        account.accountKey,
        _unreadEmailProviderId,
        info,
      ),
    );
    return info;
  }

  Future<Map<PortalInfoKind, PortalPersonalInfo>>
  _fetchPersonalDataWithRecovery(String accountKey, PortalRoute route) async {
    final cacheKey = _accountCacheKey(accountKey, route);
    try {
      return await _fetchPersonalData(accountKey, route);
    } on PortalAuthenticationException {
      _personalPageBootstrapCache.invalidate(cacheKey);
      final session = await CampusSession.open(accountKey: accountKey);
      await session.invalidateService(CampusServices.informationPortal);
      return _fetchPersonalData(accountKey, route);
    }
  }

  Future<Map<PortalInfoKind, PortalPersonalInfo>> _fetchPersonalData(
    String accountKey,
    PortalRoute route,
  ) async {
    final pageContext = await _bootstrapPersonalPage(accountKey, route);
    final userAccount = pageContext.userAccount;
    final personalCard = pageContext.card(_personalDataCardId);
    final personalCardWid = route.personalDataCardWid;
    final personalUri = personalDataCardUriFor(route);
    // The card's render/configuration requests can run together, but the
    // list endpoint must wait for them on a fresh mobile session. Calling all
    // three together can return the portal's HTML fallback instead of JSON.
    await _primePersonalDataCard(
      personalUri,
      personalCard,
      userAccount,
      route: route,
    );
    final seeds = await _loadPersonalSeeds(
      personalUri,
      userAccount,
      accountKey,
      route,
    );
    if (seeds.isEmpty) {
      // A legacy portal cookie can still read the account profile while the
      // card API returns an empty list. Re-exchange once after the
      // compatibility sequence has also failed.
      throw const PortalAuthenticationException('门户个人数据会话需要刷新');
    }
    final selected = PortalApiParser.selectPersonalDataSeeds(seeds);
    AppLogger.info('门户个人数据已匹配 ${selected.length}/${seeds.length} 项');

    final detailResults = await Future.wait(
      selected.entries.map(
        (entry) => _loadPersonalInfo(
          personalUri,
          personalCardWid,
          entry.key,
          entry.value,
          route,
        ),
      ),
    );
    PortalPersonalInfo? taskCenter;
    try {
      final taskCardWid = pageContext.cardWid(_taskCardId);
      final taskCardUri = _cardUri(taskCardWid, _taskCardId);
      final taskConfigResponse = await _postJson(
        taskCardUri,
        _taskCardConfigBody(taskCardWid),
        route: route,
      );
      final taskCenterWid = PortalApiParser.parseTaskCenterCardWid(
        taskConfigResponse,
      );
      final taskResponse = await _postJson(
        _cardUri(taskCenterWid, _taskCenterCardId),
        _taskCenterBody(taskCenterWid),
        route: route,
      );
      taskCenter = PortalApiParser.parseTaskCenterSummary(taskResponse);
    } catch (error) {
      // Task center is an optional card. Its layout/configuration may be
      // absent on one portal identity or temporarily return a non-JSON
      // response; personal status must remain usable when detail calls have
      // already succeeded.
      AppLogger.warn('门户任务中心加载失败 (${error.runtimeType})');
    }
    return personalDataWithOptionalTask(detailResults, taskCenter: taskCenter);
  }

  Future<MapEntry<PortalInfoKind, PortalPersonalInfo>> _loadPersonalInfo(
    Uri personalUri,
    String personalCardWid,
    PortalInfoKind kind,
    PortalPersonalDataSeed seed,
    PortalRoute route,
  ) async {
    // Graduate portal returns the email row as a complete/non-retrievable
    // item. Sending that row to getPersonalDataDetail produces a successful
    // HTTP response without a detail object and used to fail the whole page.
    if (!seed.needRetrieve) {
      return MapEntry(kind, PortalApiParser.personalInfoFromSeed(kind, seed));
    }
    try {
      final response = await _postJson(
        personalUri,
        _personalDetailBody(personalCardWid, seed),
        route: route,
      );
      return MapEntry(kind, PortalApiParser.parsePersonalInfo(response, kind));
    } on PortalAuthenticationException {
      rethrow;
    } on PortalApiException catch (error) {
      // One optional personal card must not hide the other successfully
      // retrieved cards. Keep the list snapshot as a visible fallback.
      AppLogger.warn('门户个人数据详情不可用，使用列表值 (${kind.name}, ${error.runtimeType})');
      return MapEntry(kind, PortalApiParser.personalInfoFromSeed(kind, seed));
    }
  }

  @visibleForTesting
  static Map<PortalInfoKind, PortalPersonalInfo> personalDataWithOptionalTask(
    Iterable<MapEntry<PortalInfoKind, PortalPersonalInfo>> details, {
    PortalPersonalInfo? taskCenter,
  }) => {
    ...Map<PortalInfoKind, PortalPersonalInfo>.fromEntries(details),
    if (taskCenter != null) PortalInfoKind.taskCenter: taskCenter,
  };

  Future<List<PortalPersonalDataSeed>> _loadPersonalSeeds(
    Uri personalUri,
    String? userAccount,
    String accountKey,
    PortalRoute route,
  ) async {
    try {
      final response = await _postJson(
        personalUri,
        personalDataListBodyFor(route),
        route: route,
      );
      final seeds = PortalApiParser.parsePersonalSeeds(response);
      if (seeds.isNotEmpty) return seeds;
      AppLogger.warn('门户个人数据快速读取返回空列表，按兼容顺序重试');
    } on PortalAuthenticationException {
      rethrow;
    } on PortalApiException catch (error) {
      // A few deployments respond with an HTML fallback while their card
      // context is still settling. Re-run the proven serial sequence once.
      AppLogger.warn('门户个人数据快速读取失败，按兼容顺序重试 (${error.runtimeType})');
    }
    final pageContext = await _bootstrapPersonalPage(accountKey, route);
    final card = pageContext.card(_personalDataCardId);
    await _primePersonalDataCard(
      personalUri,
      card,
      userAccount,
      route: route,
      parallel: false,
    );
    final response = await _postJson(
      personalUri,
      personalDataListBodyFor(route),
      route: route,
    );
    return PortalApiParser.parsePersonalSeeds(response);
  }

  /// The card's data is scoped to the portal's "个人空间" page.  The web
  /// client opens that page before calling the card API; merely exchanging a
  /// portal cookie is not enough for a new session.
  Future<_PortalPageContext> _bootstrapPersonalPage(
    String accountKey,
    PortalRoute route,
  ) async {
    final cacheKey = _accountCacheKey(accountKey, route);
    if (_personalPageBootstrapCache.isFresh(cacheKey)) {
      AppLogger.info('门户个人空间初始化缓存命中');
    }
    return _personalPageBootstrapCache.load(
      cacheKey,
      () => _bootstrapPersonalPageUncached(route),
    );
  }

  Future<_PortalPageContext> _bootstrapPersonalPageUncached(
    PortalRoute route,
  ) async {
    final userAccount = await _getPortalUserAccount();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    await _warmUpPortalPage(
      () => _getJson(
        _portalPermissionsUri.replace(
          queryParameters: {'_t': timestamp, 'langCountry': 'zh_CN'},
        ),
        route: route,
      ),
    );
    if (userAccount != null && userAccount.isNotEmpty) {
      await _warmUpPortalPage(
        () => _postJson(_portalSiteSwitchUri, {
          'userAccount': userAccount,
          'n': Random().nextDouble().toString(),
        }, route: route),
      );
    }
    await _warmUpPortalPage(
      () => _getJson(
        _portalUserAndGuestUri.replace(queryParameters: {'_t': timestamp}),
        route: route,
      ),
    );
    final pageViewResponse = await _getJson(
      _portalPageViewUri.replace(
        queryParameters: pageViewQueryFor(route, timestamp),
      ),
      route: route,
      pageViewHeaders: true,
    );
    final cards = PortalApiParser.parsePageCards(pageViewResponse);
    AppLogger.info('门户个人空间初始化完成');
    return _PortalPageContext(userAccount: userAccount, cards: cards);
  }

  /// 预热调用只是为卡片接口建立“个人空间”页面上下文，返回值不参与个人
  /// 数据解析；单个调用失败（如偶发 200 非 JSON）不应阻断其余预热与后续
  /// 卡片加载，真正的鉴权失败仍上抛以触发会话恢复。
  Future<void> _warmUpPortalPage(Future<Object?> Function() request) async {
    try {
      await request();
    } on PortalAuthenticationException {
      rethrow;
    } on PortalApiException catch (error) {
      AppLogger.warn('门户个人空间预热调用失败，继续初始化卡片上下文 (${error.runtimeType})');
    }
  }

  /// The portal's web client initializes this card before reading its items.
  /// Without these calls the same list endpoint may return a successful but
  /// empty array for a freshly exchanged portal session.
  Future<void> _primePersonalDataCard(
    Uri personalUri,
    Map<String, dynamic> personalCard,
    String? userAccount, {
    required PortalRoute route,
    bool parallel = true,
  }) async {
    try {
      if (parallel) {
        await Future.wait([
          _postJson(
            personalUri,
            _personalRenderBody(personalCard, route.personalDataCardWid),
            route: route,
          ),
          _postJson(
            personalUri,
            _personalConfiguredBody(
              personalCard,
              route.personalDataCardWid,
              userAccount,
            ),
            route: route,
          ),
        ]);
      } else {
        await _postJson(
          personalUri,
          _personalRenderBody(personalCard, route.personalDataCardWid),
          route: route,
        );
        await _postJson(
          personalUri,
          _personalConfiguredBody(
            personalCard,
            route.personalDataCardWid,
            userAccount,
          ),
          route: route,
        );
      }
    } on PortalAuthenticationException {
      rethrow;
    } catch (error) {
      // The list call remains worthwhile for older portal deployments that do
      // not require this initialization sequence.
      AppLogger.warn('门户个人数据卡片初始化未完成 (${error.runtimeType})');
    }
  }

  Map<String, Object?> _personalRenderBody(
    Map<String, dynamic> personalCard,
    String personalCardWid,
  ) => {
    ..._personalCardContext(personalCard, personalCardWid),
    'method': 'renderData',
    'param': const {'lang': 'zh_CN', 'platformType': 0},
    'n': Random().nextDouble().toString(),
  };

  Map<String, Object?> _personalConfiguredBody(
    Map<String, dynamic> personalCard,
    String personalCardWid,
    String? userAccount,
  ) => {
    ..._personalCardContext(personalCard, personalCardWid),
    'method': 'configuredData',
    'param': {
      'lang': 'zh_CN',
      if (userAccount != null && userAccount.isNotEmpty)
        'userAccount': userAccount,
      'platformType': 0,
    },
    'n': Random().nextDouble().toString(),
  };

  Map<String, Object?> _personalCardContext(
    Map<String, dynamic> personalCard,
    String personalCardWid,
  ) => <String, Object?>{
    ...personalCard,
    'cardId': _personalDataCardId,
    'cardWid': personalCardWid,
  };

  Future<String?> _getPortalUserAccount() async {
    return (await PortalIdentityService.fetchCurrent())?.uid;
  }

  static Map<String, Object?> _personalListBody(String personalCardWid) => {
    'cardId': _personalDataCardId,
    'cardWid': personalCardWid,
    'method': 'getPersonalDataList',
    'param': const {'lang': 'zh_CN', 'platformType': 0},
    'n': Random().nextDouble().toString(),
  };

  Map<String, Object?> _personalDetailBody(
    String personalCardWid,
    PortalPersonalDataSeed seed,
  ) => {
    'cardId': _personalDataCardId,
    'cardWid': personalCardWid,
    'method': 'getPersonalDataDetail',
    'param': {
      'wid': seed.id,
      'extraInfo': seed.extraInfo,
      'lang': 'zh_CN',
      'platformType': 0,
    },
    'n': Random().nextDouble().toString(),
  };

  Map<String, Object?> _taskCardConfigBody(String taskCardWid) => {
    'cardWid': taskCardWid,
    'cardId': _taskCardId,
    'method': 'getConfig',
    'param': {
      '_t': DateTime.now().millisecondsSinceEpoch,
      'lang': 'zh_CN',
      'platformType': 0,
    },
    'n': Random().nextDouble().toString(),
  };

  Map<String, Object?> _taskCenterBody(String taskCenterWid) => {
    'cardWid': taskCenterWid,
    'cardId': _taskCenterCardId,
    'method': 'render',
    'param': const {'lang': 'zh_CN', 'platformType': 0},
    'n': Random().nextDouble().toString(),
  };

  static Uri _cardUri(String cardWid, String cardId) {
    final validSegment = RegExp(r'^[A-Za-z0-9_-]+$');
    if (!validSegment.hasMatch(cardWid) || !validSegment.hasMatch(cardId)) {
      throw const PortalApiException('门户卡片配置格式异常');
    }
    return CampusServiceEndpoints.portalCardMethodUri(cardWid, cardId);
  }

  @visibleForTesting
  static Uri personalDataCardUriFor(PortalRoute route) =>
      _cardUri(route.personalDataCardWid, _personalDataCardId);

  @visibleForTesting
  static Map<String, String> pageViewQueryFor(
    PortalRoute route,
    String timestamp,
  ) => {
    '_t': timestamp,
    'pageCode': PortalRoute.pageCode,
    'originalUrl': route.encodedOriginalUrl,
    'lang': 'zh_CN',
  };

  @visibleForTesting
  static Map<String, Object?> personalDataListBodyFor(PortalRoute route) =>
      _personalListBody(route.personalDataCardWid);

  Future<Object?> _getJson(
    Uri uri, {
    required PortalRoute route,
    bool pageViewHeaders = false,
  }) async {
    return _requestJson(uri, route: route, pageViewHeaders: pageViewHeaders);
  }

  Future<Object?> _postJson(
    Uri uri,
    Map<String, Object?> body, {
    required PortalRoute route,
  }) async {
    return _requestJson(uri, body: body, route: route);
  }

  Future<Object?> _requestJson(
    Uri uri, {
    Map<String, Object?>? body,
    required PortalRoute route,
    bool pageViewHeaders = false,
  }) async {
    final requestLabel = '${body == null ? 'GET' : 'POST'} 门户接口';
    final stopwatch = Stopwatch()..start();
    try {
      AppLogger.info('门户接口开始: $requestLabel');
      var response = await _sendPortalRequest(
        uri,
        body,
        route,
        pageViewHeaders: pageViewHeaders,
      );
      var decoded = PortalApiParser.decodeJsonObject(response.body);
      if (body == null &&
          response.statusCode == HttpStatus.ok &&
          decoded == null) {
        // 门户偶发对 GET 返回 200 但正文不是 JSON（HTML 兜底/空响应/截断）：
        // 等待片刻重试一次，效果等价于网页端刷新。
        AppLogger.warn('门户接口返回非 JSON 响应，稍后重试: $requestLabel');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        response = await _sendPortalRequest(
          uri,
          body,
          route,
          pageViewHeaders: pageViewHeaders,
        );
        decoded = PortalApiParser.decodeJsonObject(response.body);
      }
      AppLogger.info(
        '门户接口完成: $requestLabel → HTTP ${response.statusCode} '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden ||
          (response.statusCode >= 300 && response.statusCode < 400)) {
        throw const PortalAuthenticationException();
      }
      if (response.statusCode != HttpStatus.ok) {
        throw PortalApiException('门户服务返回 HTTP ${response.statusCode}');
      }

      if (decoded == null) throw _unrecognizedPortalResponse(response.body);
      PortalApiParser.throwIfFailedResponse(decoded);
      return decoded;
    } on TimeoutException {
      AppLogger.warn('门户接口超时: $requestLabel');
      throw const PortalApiException('门户响应超时，请稍后重试。');
    }
  }

  Future<AccountNetworkResponse> _sendPortalRequest(
    Uri uri,
    Map<String, Object?>? body,
    PortalRoute route, {
    bool pageViewHeaders = false,
  }) {
    return CampusSession.client(CampusServices.informationPortal).request(
      body == null ? 'GET' : 'POST',
      uri.toString(),
      body: body,
      throwOnHttpError: false,
      requestTimeout: _requestTimeout,
      responseTimeout: _requestTimeout,
      extraHeaders: {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Origin': CampusServiceEndpoints.portalBase,
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36',
        'sec-ch-ua':
            '"Not;A=Brand";v="8", "Chromium";v="150", "Google Chrome";v="150"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        ...route.cardHeaders,
        if (pageViewHeaders) ...route.pageViewHeaders,
      },
    );
  }

  Exception _unrecognizedPortalResponse(String rawBody) {
    AppLogger.warn(
      '门户接口返回无法识别的数据：长度=${rawBody.length}，'
      'HTML=${PortalApiParser.looksLikeHtml(rawBody)}，'
      '登录页=${PortalApiParser.looksLikeAuthenticationPage(rawBody)}',
    );
    if (PortalApiParser.looksLikeAuthenticationPage(rawBody)) {
      return const PortalAuthenticationException('门户会话需要刷新');
    }
    return const PortalApiException('门户服务返回了无法识别的数据');
  }
}

String _formatAmount(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

/// Pure response parsers kept public for regression tests and endpoint changes.
class PortalApiParser {
  static const _personalDataKindsById = <String, PortalInfoKind>{
    'eb825a9112134b5985b7070e7a326896': PortalInfoKind.campusCard,
    'ab21f2c2049f509813146b066e1a5d7e': PortalInfoKind.email,
    '401a3a23226c9a53b0f41a7049dff670': PortalInfoKind.library,
  };

  static const _personalDataKindsByTitle = <String, PortalInfoKind>{
    '校园卡': PortalInfoKind.campusCard,
    '邮箱': PortalInfoKind.email,
    '图书借阅': PortalInfoKind.library,
  };

  /// Extracts the current account's card configuration from the portal page.
  ///
  /// Card IDs are stable feature identifiers, while card WIDs are assigned by
  /// the portal page layout and can differ between accounts or deployments.
  static Map<String, Map<String, dynamic>> parsePageCards(Object? raw) {
    final map = _asMap(raw);
    _throwIfFailed(map);
    final data = _asMap(map['data']);
    final pageContext = _asMap(data['pageContext']);
    final pageInfo = _asMap(pageContext['pageInfoEntity']);
    final layout = _decodeNestedJson(pageInfo['cardLayout']);
    if (layout is! List) {
      throw const PortalApiException('门户页面卡片配置格式异常');
    }

    final cards = <String, Map<String, dynamic>>{};
    _collectPageCards(layout, cards);
    if (cards.isEmpty) {
      throw const PortalApiException('门户页面卡片配置为空');
    }
    return cards;
  }

  static void _collectPageCards(
    Object? value,
    Map<String, Map<String, dynamic>> cards,
  ) {
    if (value is List) {
      for (final item in value) {
        _collectPageCards(item, cards);
      }
      return;
    }
    if (value is! Map) return;

    final map = Map<String, dynamic>.from(value);
    final cardId = _string(map['cardId']);
    final cardWid = _string(map['cardWid']);
    if (cardId.isNotEmpty && cardWid.isNotEmpty) {
      cards[cardId] = map;
    }
    for (final child in map.values) {
      _collectPageCards(child, cards);
    }
  }

  static String parseTaskCenterCardWid(Object? raw) {
    final map = _asMap(raw);
    _throwIfFailed(map);
    final data = _asMap(_decodeNestedJson(map['data']));
    final cardWid = _string(data['mytask']);
    if (cardWid.isEmpty) {
      throw const PortalApiException('任务中心卡片配置格式异常');
    }
    return cardWid;
  }

  static List<PortalPersonalDataSeed> parsePersonalSeeds(Object? raw) {
    final map = _asMap(raw);
    _throwIfFailed(map);
    final data = map['data'];
    if (data is! List) {
      throw const PortalApiException('个人数据列表格式异常');
    }
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(
          (item) => PortalPersonalDataSeed(
            id: _string(item['wid']),
            title: _string(item['title']),
            extraInfo: item['extraInfo'],
            mainInfo: _string(item['mainInfo']),
            subInfo: _string(item['subInfo']),
            needRetrieve: _bool(item['needRetrieve'], defaultValue: true),
          ),
        )
        .where((seed) => seed.id.isNotEmpty && seed.title.isNotEmpty)
        .toList(growable: false);
  }

  /// Uses the card's stable IDs first because some portal responses vary the
  /// localized title. The title remains a fallback for future card revisions.
  static Map<PortalInfoKind, PortalPersonalDataSeed> selectPersonalDataSeeds(
    Iterable<PortalPersonalDataSeed> seeds,
  ) {
    final selected = <PortalInfoKind, PortalPersonalDataSeed>{};
    for (final seed in seeds) {
      final kind =
          _personalDataKindsById[seed.id] ??
          _personalDataKindsByTitle[seed.title];
      if (kind != null) selected[kind] = seed;
    }
    return selected;
  }

  static PortalPersonalInfo parsePersonalInfo(
    Object? raw,
    PortalInfoKind kind,
  ) {
    final map = _asMap(raw);
    _throwIfFailed(map);
    final data = _asMap(map['data']);
    return PortalPersonalInfo(
      kind: kind,
      title: _string(data['title']),
      mainInfo: _string(data['mainInfo']),
      subInfo: _string(data['subInfo']),
    );
  }

  @visibleForTesting
  static PortalPersonalInfo personalInfoFromSeed(
    PortalInfoKind kind,
    PortalPersonalDataSeed seed,
  ) => PortalPersonalInfo(
    kind: kind,
    title: seed.title,
    mainInfo: seed.mainInfo,
    subInfo: seed.subInfo,
  );

  static PortalPersonalInfo parseTaskCenterSummary(Object? raw) {
    final map = _asMap(raw);
    _throwIfFailed(map);
    final data = _asMap(map['data']);
    final taskInfo = data['taskInfo'];
    if (taskInfo is! List) {
      throw const PortalApiException('任务中心数据格式异常');
    }

    var todoCount = 0;
    var doneCount = 0;
    for (final item in taskInfo.whereType<Map>()) {
      todoCount += _int(item['todoCount']);
      doneCount += _int(item['doneCount']);
    }
    return PortalPersonalInfo(
      kind: PortalInfoKind.taskCenter,
      title: '任务中心',
      mainInfo: todoCount == 0 ? '暂无待办任务' : '待办 $todoCount 项',
      subInfo: '已办 $doneCount 项',
    );
  }

  static Object? _decodeNestedJson(Object? value) {
    var decoded = value;
    for (var index = 0; index < 3 && decoded is String; index++) {
      final text = decoded.trim();
      if (text.isEmpty) return decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        return decoded;
      }
    }
    return decoded;
  }

  static void throwIfFailedResponse(Object? raw) => _throwIfFailed(_asMap(raw));

  /// 解析门户响应 JSON，兼容服务端偶发附带的 UTF-8 BOM；正文不是有效
  /// JSON 时返回 null（不抛异常），由调用方决定重试或归类错误。
  static Object? decodeJsonObject(String rawBody) {
    final body = rawBody.startsWith('\uFEFF') ? rawBody.substring(1) : rawBody;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// 响应正文是否为 HTML（用于区分 JSON 接口的 HTML 兜底返回）。
  static bool looksLikeHtml(String rawBody) {
    final lower = rawBody.toLowerCase();
    return lower.contains('<!doctype') || lower.contains('<html');
  }

  /// 非 JSON 正文是否属于门户登录/认证页（会话失效时服务端返回的 HTML）。
  static bool looksLikeAuthenticationPage(String rawBody) {
    final lower = rawBody.toLowerCase();
    return lower.contains('authserver/login') ||
        lower.contains('统一身份认证') ||
        lower.contains('cas login') ||
        lower.contains('protocol/openid-connect') ||
        (looksLikeHtml(rawBody) && lower.contains('登录'));
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const PortalApiException('门户数据格式异常');
  }

  static int _int(Object? value) => int.tryParse(_string(value)) ?? 0;

  static bool _bool(Object? value, {required bool defaultValue}) {
    if (value is bool) return value;
    final text = _string(value).toLowerCase();
    if (text == '1' || text == 'true') return true;
    if (text == '0' || text == 'false') return false;
    return defaultValue;
  }

  static void _throwIfFailed(Map<String, dynamic> map) {
    final errorCode = map['errcode'];
    if (errorCode != null && errorCode.toString() != '0') {
      final message = _string(map['errmsg']);
      if (_looksLikeAuthenticationFailure(message)) {
        throw PortalAuthenticationException(message);
      }
      throw PortalApiException(message.isEmpty ? '门户服务请求失败' : message);
    }

    final code = map['code'];
    if (code != null && code.toString() != '0') {
      final message = _string(map['msg']);
      if (_looksLikeAuthenticationFailure(message)) {
        throw PortalAuthenticationException(message);
      }
      throw PortalApiException(message.isEmpty ? '门户服务请求失败' : message);
    }
  }

  static bool _looksLikeAuthenticationFailure(String message) {
    final lower = message.toLowerCase();
    return lower.contains('login') ||
        lower.contains('session') ||
        lower.contains('credential') ||
        lower.contains('token') ||
        message.contains('登录') ||
        message.contains('未登录') ||
        message.contains('凭证') ||
        message.contains('认证') ||
        message.contains('无权限') ||
        message.contains('无权') ||
        message.contains('权限不足');
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';
}

class _PortalPageContext {
  final String? userAccount;
  final Map<String, Map<String, dynamic>> cards;

  const _PortalPageContext({required this.userAccount, required this.cards});

  Map<String, dynamic> card(String cardId) {
    final value = cards[cardId];
    if (value == null) {
      throw const PortalApiException('门户页面缺少必要卡片配置');
    }
    return value;
  }

  String cardWid(String cardId) {
    final value = card(cardId)['cardWid']?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw const PortalApiException('门户卡片缺少动态 WID');
    }
    return value;
  }
}
