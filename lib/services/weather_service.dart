import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'public_http_client.dart';

/// 校园天气：通过公开免费的 Open-Meteo API 获取，无需密钥。
///
/// 天气不随账号变化，但跟随账号校区偏好；使用短时内存缓存（约 15 分钟），
/// 首页不因天气阻塞。走共享公开 HTTP 客户端（[PublicHttpClient]），与账号会话隔离。
class WeatherService {
  WeatherService({http.Client? client})
    : _http = client == null ? _sharedHttp : PublicHttpClient(client: client);

  final PublicHttpClient _http;
  static final PublicHttpClient _sharedHttp = PublicHttpClient();

  static const _cacheTtl = Duration(minutes: 15);

  static final Map<String, _WeatherCacheEntry> _cache = {};

  @visibleForTesting
  static void resetCache() => _cache.clear();

  /// 拉取指定校区当前天气；TTL 内返回缓存，[force] 时绕过缓存。
  Future<WeatherInfo> fetchWeather({
    required String campusId,
    required String city,
    required double latitude,
    required double longitude,
    bool force = false,
  }) async {
    final cached = _cache[campusId];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached.info;
    }

    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
      queryParameters: {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'current': 'temperature_2m,weather_code',
        'timezone': 'Asia/Shanghai',
      },
    );
    final response = await _http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw WeatherException('天气服务暂不可用（HTTP ${response.statusCode}）');
    }

    final weather = parseWeather(response.body, city: city);
    _cache[campusId] = _WeatherCacheEntry(weather, DateTime.now());
    return weather;
  }

  /// 解析 Open-Meteo 当前天气响应；结构异常时抛出格式错误。
  static WeatherInfo parseWeather(String body, {required String city}) {
    final decoded = PublicHttpClient.decodeJsonMap(body);
    final current = decoded['current'];
    if (current is! Map<String, dynamic>) {
      throw const FormatException('天气接口缺少 current 数据');
    }
    final temperature = current['temperature_2m'];
    final code = current['weather_code'];
    if (temperature is! num || code is! num) {
      throw const FormatException('天气接口缺少温度或天气代码');
    }
    return WeatherInfo(
      city: city,
      temperatureC: temperature.toDouble(),
      weatherCode: code.toInt(),
    );
  }
}

class _WeatherCacheEntry {
  final WeatherInfo info;
  final DateTime fetchedAt;

  const _WeatherCacheEntry(this.info, this.fetchedAt);
}

class WeatherInfo {
  final String city;
  final double temperatureC;
  final int weatherCode;

  const WeatherInfo({
    required this.city,
    required this.temperatureC,
    required this.weatherCode,
  });

  String get temperatureLabel => '${temperatureC.round()}°C';

  String get label => weatherLabel(weatherCode);
}

/// WMO 天气代码 → 中文天气描述。
String weatherLabel(int code) {
  if (code == 0 || code == 1) return '晴';
  if (code == 2) return '多云';
  if (code == 3) return '阴';
  if (code == 45 || code == 48) return '雾';
  if (code == 51 || code == 53 || code == 55) return '毛毛雨';
  if (code == 56 || code == 57 || code == 66 || code == 67) return '冻雨';
  if (code == 61) return '小雨';
  if (code == 63) return '中雨';
  if (code == 65) return '大雨';
  if (code == 71) return '小雪';
  if (code == 73) return '中雪';
  if (code == 75 || code == 77) return '雪';
  if (code >= 80 && code <= 82) return '阵雨';
  if (code == 85 || code == 86) return '阵雪';
  if (code >= 95 && code <= 99) return '雷阵雨';
  return '未知';
}

class WeatherException implements Exception {
  final String message;

  const WeatherException(this.message);

  @override
  String toString() => message;
}
