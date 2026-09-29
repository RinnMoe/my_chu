import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/campus_session.dart';
import '../../services/service_endpoints.dart';
import 'wozaichangda_models.dart';

class WozaichangdaService {
  static const serviceId = CampusServices.campusApp;
  static final _client = CampusSession.client(serviceId);

  static Future<List<WozaichangdaCategory>> fetchApps() async {
    final response = await _client.request(
      'POST',
      CampusServiceEndpoints.campusHomeAppsUri.toString(),
      body: const {},
      extraHeaders: {
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Origin': CampusServiceEndpoints.campusAppBase,
        'Referer': CampusServiceEndpoints.campusHomePageUri.toString(),
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/147.0.0.0 Safari/537.36',
        'sec-ch-ua':
            '"Google Chrome";v="147", "Not.A/Brand";v="8", '
            '"Chromium";v="147"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
      },
      throwOnHttpError: false,
    );
    if (response.statusCode != 200) {
      throw WozaichangdaApiException('请求失败（HTTP ${response.statusCode}）');
    }
    return parseApps(response.body);
  }

  @visibleForTesting
  static List<WozaichangdaCategory> parseApps(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (error) {
      throw WozaichangdaParseException('响应不是有效 JSON：$error');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const WozaichangdaParseException('响应根节点不是对象');
    }
    if (decoded['code'] != 0) {
      throw WozaichangdaApiException('API 返回错误：${decoded['code']}');
    }

    final data = decoded['data'];
    final Object? rawHome;
    if (data is List) {
      rawHome = data;
    } else if (data is Map<String, dynamic>) {
      rawHome = data['home'];
    } else {
      throw const WozaichangdaParseException('响应缺少有效 data');
    }
    if (rawHome == null) return const [];
    if (rawHome is! List) {
      throw const WozaichangdaParseException('data.home 不是数组');
    }

    return [
      for (var index = 0; index < rawHome.length; index++)
        _parseCategory(rawHome[index], index),
    ];
  }

  static WozaichangdaCategory _parseCategory(Object? raw, int index) {
    if (raw is! Map<String, dynamic>) {
      throw WozaichangdaParseException('分类 $index 不是对象');
    }
    final rawApps = raw['apps'];
    if (rawApps is! List) {
      throw WozaichangdaParseException('分类 $index 缺少 apps 数组');
    }
    return WozaichangdaCategory(
      name: _stringValue(raw['name']),
      apps: [
        for (var appIndex = 0; appIndex < rawApps.length; appIndex++)
          _parseApp(rawApps[appIndex], index, appIndex),
      ],
    );
  }

  static WozaichangdaApp _parseApp(
    Object? raw,
    int categoryIndex,
    int appIndex,
  ) {
    if (raw is! Map<String, dynamic>) {
      throw WozaichangdaParseException('分类 $categoryIndex 的应用 $appIndex 不是对象');
    }
    return WozaichangdaApp(
      name: _stringValue(raw['name']),
      icon: _stringValue(raw['icon']),
      page: _stringValue(raw['page']),
      path: _stringValue(raw['path']),
      id: _stringValue(raw['id']),
      appType: _stringValue(raw['appType']),
    );
  }

  static String _stringValue(Object? value) => value is String ? value : '';

  static Uri? resolveAppUri(WozaichangdaApp app) {
    final target = (app.page.isNotEmpty ? app.page : app.path).trim();
    if (target.isEmpty) return null;

    final parsed = Uri.tryParse(target);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;
    if (target.startsWith('//')) return Uri.parse('https:$target');

    final origin = CampusServiceEndpoints.campusAppOriginUri;
    final routeBase = CampusServiceEndpoints.campusAppH5RouteBaseUri;
    if (target.startsWith('/')) {
      if (target.startsWith('/h5/') || target.startsWith('/basicinfo/')) {
        return origin.resolve(target);
      }
      return Uri.parse('${routeBase.toString()}$target');
    }
    if (target.startsWith('h5/') || target.startsWith('basicinfo/')) {
      return origin.resolve('/$target');
    }
    return Uri.parse('${routeBase.toString()}/$target');
  }
}

class WozaichangdaApiException implements Exception {
  final String message;

  const WozaichangdaApiException(this.message);

  @override
  String toString() => message;
}

class WozaichangdaParseException implements Exception {
  final String message;

  const WozaichangdaParseException(this.message);

  @override
  String toString() => message;
}
