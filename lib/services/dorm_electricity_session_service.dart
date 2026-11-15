import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'privacy_agreement_service.dart';
import 'logging/logger.dart';
import 'remote_feature_policy/feature_access_guard.dart';
import 'remote_feature_policy/remote_feature_policy_service.dart';
import 'scoped_cookie_jar.dart';

const dormElectricityFeatureId = 'feature.dorm.electricity';

enum DormElectricityQuery { balance, bill, daily }

/// Deliberately contains no server text, identifiers or request details.
class DormElectricityException implements Exception {
  const DormElectricityException(this.code);
  final String code;

  String get message => switch (code) {
    'cancelled' => '查询已取消，请重试。',
    'blocked' => '当前无法使用宿舍电费，请检查协议或功能状态。',
    'empty' => '该房间暂未查到电表，请核对房间或使用表号查询。',
    'storage' => '记录未能保存到本机，请重试。',
    'network' => '电费服务暂时无法连接，请稍后重试。',
    _ => '电费服务返回异常，请稍后重试。',
  };

  @override
  String toString() => 'DormElectricityException($code)';
}

class DormElectricityRequest {
  bool _cancelled = false;
  final Set<void Function()> _closers = {};
  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    for (final close in _closers.toList()) {
      close();
    }
  }

  void check() {
    if (_cancelled) throw const DormElectricityException('cancelled');
  }
}

/// Non-secret response. Cookies and transport headers never leave the host.
class DormElectricityResponse {
  const DormElectricityResponse(this.body, {this.month});
  final String body;
  final String? month;
}

/// Independent anonymous third-party session, never a campus/CAS identity.
/// Each transaction owns its client and in-memory jar and closes both together.
/// It deliberately does not reuse `public_http_client.dart`: this host needs
/// per-request `followRedirects = false`, an in-memory jar and its own byte and
/// time caps, which the shared public client does not expose.
class DormElectricitySessionService {
  DormElectricitySessionService({
    http.Client Function()? clientFactory,
    Future<bool> Function()? allowed,
    int Function()? gateRevision,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _allowed = allowed ?? _defaultAllowed,
       _gateRevision = gateRevision ?? _defaultRevision;

  static const _origin = 'http://bd.bdfairy.cn';
  static const _timeout = Duration(seconds: 20);
  static const _maxBytes = 2 * 1024 * 1024;
  static const _paths = {
    '/',
    '/selectarea',
    '/phonejcbd',
    '/login',
    '/selectmeter',
    '/meter_main',
    '/electricbill',
    '/electricdetail',
  };
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 12; M2012K11AC Build/SKQ1.211006.001; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Version/4.0 Chrome/107.0.5304.141 Mobile Safari/537.36 '
      'XWEB/5169 MMWEBSDK/20220903 MMWEBID/3905 '
      'MicroMessenger/8.0.28.2240(0x28001C35) WeChat/arm64 Weixin '
      'NetType/WIFI Language/zh_CN ABI/arm64';

  final http.Client Function() _clientFactory;
  final Future<bool> Function() _allowed;
  final int Function() _gateRevision;

  static int _defaultRevision() =>
      PrivacyAgreementService.revision.value * 1000000 +
      RemoteFeaturePolicyService.instance.revision.value;

  static Future<bool> _defaultAllowed() async {
    if (!await PrivacyAgreementService.isAccepted()) return false;
    await RemoteFeaturePolicyService.instance.initialize();
    final decision = FeatureAccessGuard.instance.decide(
      featureId: dormElectricityFeatureId,
    );
    return decision.canLaunch && decision.isEntryVisible;
  }

  Future<DormElectricityResponse> resolveRoom({
    required String roomId,
    required String buildingInfo,
    required DormElectricityRequest request,
  }) => _transaction(request, (send) async {
    if (!RegExp(r'^\d{24}$').hasMatch(roomId) || buildingInfo.length > 300) {
      throw const DormElectricityException('malformed');
    }
    final result = _object(
      await send(
        '/login',
        json: {'buildingID': roomId, 'buildingInfo': buildingInfo},
      ),
    );
    if (!_expectedPath(result['href'], '/selectmeter')) {
      throw const DormElectricityException('empty');
    }
    return DormElectricityResponse(await send('/selectmeter'));
  });

  Future<DormElectricityResponse> query({
    required String meter,
    required DormElectricityQuery kind,
    String? month,
    required DormElectricityRequest request,
  }) => _transaction(request, (send) async {
    if (!RegExp(r'^\d{8,32}$').hasMatch(meter) ||
        (kind != DormElectricityQuery.balance &&
            (month == null ||
                !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)))) {
      throw const DormElectricityException('malformed');
    }
    final selected = _object(
      await send(
        '/selectmeter',
        json: {'comAddress': meter, 'hidType': '电表', 'room': ''},
      ),
    );
    if (!_expectedPath(selected['url'], '/meter_main')) {
      throw const DormElectricityException('empty');
    }
    final balance = await send('/meter_main');
    if (kind == DormElectricityQuery.balance) {
      return DormElectricityResponse(balance);
    }
    if (kind == DormElectricityQuery.bill) {
      // The GET initializes the site's billing page context; the POST chooses
      // the actual month, so a default-month page cannot be relabelled.
      await send('/electricbill');
      return DormElectricityResponse(
        await send(
          '/electricbill',
          json: {'month': month, 'comAddress': meter},
        ),
        month: month,
      );
    }
    return DormElectricityResponse(
      await send(
        '/electricdetail',
        form: {'month': month!, 'comAddress': meter},
      ),
      month: month,
    );
  });

  Future<T> _transaction<T>(
    DormElectricityRequest request,
    Future<T> Function(_Send send) action,
  ) async {
    request.check();
    final revision = _gateRevision();
    http.Client? client;
    var stage = 'entry';
    int? statusCode;
    void recordFailure(Object error, StackTrace stack) => AppLogger.error(
      error,
      stackTrace: stack,
      context: '电费查询失败 ($stage, HTTP $statusCode)',
    );
    void close() => client?.close();
    Future<void> check() async {
      request.check();
      if (revision != _gateRevision() || !await _allowed()) {
        throw const DormElectricityException('blocked');
      }
      request.check();
      if (revision != _gateRevision()) {
        throw const DormElectricityException('blocked');
      }
    }

    var jar = ScopedCookieJar();
    Future<String> send(
      String path, {
      Map<String, Object?>? json,
      Map<String, String>? form,
    }) async {
      await check();
      final uri = Uri.parse('$_origin$path');
      if (uri.host != 'bd.bdfairy.cn' ||
          !_paths.contains(uri.path) ||
          uri.hasFragment ||
          uri.userInfo.isNotEmpty ||
          (uri.hasQuery && uri.query != 'id=65')) {
        throw const DormElectricityException('malformed');
      }
      client ??= _clientFactory();
      stage = switch (uri.path) {
        '/selectarea' => 'area',
        '/phonejcbd' => 'reset',
        '/login' => 'room',
        '/selectmeter' => 'meter',
        '/meter_main' => 'balance',
        '/electricbill' => 'bill',
        '/electricdetail' => 'daily',
        _ => 'entry',
      };
      statusCode = null;
      final outgoing =
          http.Request(json == null && form == null ? 'GET' : 'POST', uri)
            ..followRedirects = false
            ..headers.addAll({
              'User-Agent': _userAgent,
              'X-Requested-With': 'com.tencent.mm',
              'Accept': 'application/json, text/html, */*',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              if (json != null || form != null) 'Origin': _origin,
              'Referer':
                  '$_origin${switch (uri.path) {
                    '/selectarea' => '/selectArea',
                    '/phonejcbd' => '/selectPhoneMeter',
                    '/login' => '/login',
                    '/selectmeter' => '/login',
                    '/meter_main' => '/selectmeter',
                    '/electricbill' when json != null => '/electricbill',
                    _ => '/meter_main',
                  }}',
            });
      final cookie = jar.headerFor(uri);
      if (cookie.isNotEmpty) outgoing.headers['Cookie'] = cookie;
      if (json != null) {
        outgoing.headers['Content-Type'] = 'application/json';
        outgoing.body = jsonEncode(json);
      } else if (form != null) {
        outgoing.bodyFields = form;
      }
      final incoming = await client!.send(outgoing).timeout(_timeout);
      statusCode = incoming.statusCode;
      final entryRedirect =
          uri.path == '/' &&
          incoming.statusCode == 302 &&
          _isEntryRedirect(incoming.headers['location']);
      if (incoming.statusCode != 200 && !entryRedirect) {
        throw const DormElectricityException('server');
      }
      final bytes = <int>[];
      await for (final chunk in incoming.stream.timeout(_timeout)) {
        if (bytes.length + chunk.length > _maxBytes) {
          throw const DormElectricityException('malformed');
        }
        bytes.addAll(chunk);
        request.check();
      }
      await check();
      final cookies = incoming.headers['set-cookie'];
      if (cookies != null) {
        jar.collectSetCookieHeaders(
          uri,
          cookies.split(RegExp(r',(?=\s*[^;,=\s]+=)')),
        );
      }
      return utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
    }

    request._closers.add(close);
    try {
      Future<Map<String, dynamic>> selectArea() async {
        // The entry legitimately returns an OAuth redirect AND connect.sid.
        // Consume its cookie, never navigate to OAuth, then select the school.
        await send('/?id=65');
        return _object(
          await send('/selectarea', json: {'areaId': '65', 'areaName': '长安大学'}),
        );
      }

      bool bound(Map<String, dynamic> area) =>
          '${area['band']}' == '1' ||
          {
            'selectmeter',
            'selectPhoneMeter',
            'meter_main',
          }.contains(area['data']);
      var area = await selectArea();
      if (bound(area)) {
        // Only this transaction's freshly created anonymous cookie is sent.
        // No persisted app/WeChat session can be unbound by this recovery.
        await send('/phonejcbd', json: {});
        close();
        client = null;
        jar = ScopedCookieJar();
        area = await selectArea();
        if (bound(area)) throw const DormElectricityException('session');
      }
      final result = await action(send);
      await check();
      return result;
    } on DormElectricityException catch (error, stack) {
      recordFailure(error, stack);
      rethrow;
    } on FormatException catch (error, stack) {
      recordFailure(error, stack);
      throw const DormElectricityException('malformed');
    } catch (error, stack) {
      recordFailure(error, stack);
      request.check();
      throw const DormElectricityException('network');
    } finally {
      request._closers.remove(close);
      close();
    }
  }

  static Map<String, dynamic> _object(String body) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const DormElectricityException('malformed');
    }
    return value;
  }

  static bool _expectedPath(Object? value, String expected) =>
      value == expected || value == expected.substring(1);

  static bool _isEntryRedirect(String? location) {
    final uri = location == null ? null : Uri.tryParse(location);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'open.weixin.qq.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.path == '/connect/oauth2/authorize';
  }
}

typedef _Send =
    Future<String> Function(
      String path, {
      Map<String, Object?>? json,
      Map<String, String>? form,
    });
