/// 坐标体系转换（外部导航用）：WGS84 → GCJ-02 / BD-09。
///
/// 权威坐标统一为 WGS84（地点主数据）；调起外部地图时按目标转换：
/// 高德用 GCJ-02，百度用 BD-09，系统地图按实测（本项目按 WGS84 输出 `geo:`）。
/// 算法为标准开源实现（coordtransform/eviltransform 等价），不依赖任何 SDK。
library;

import "dart:math" as math;

/// 经纬度（double，度）。
class NavCoordinate {
  final double longitude;
  final double latitude;

  const NavCoordinate({required this.longitude, required this.latitude});

  bool get isValid =>
      longitude >= -180 &&
      longitude <= 180 &&
      latitude >= -90 &&
      latitude <= 90;

  bool get isOrigin => longitude == 0 && latitude == 0;
}

/// WGS84 到外部地图坐标的转换（纯函数，可单测）。
class CoordinateConverter {
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;
  static const double _pi = 3.1415926535897932384626;

  const CoordinateConverter();

  static bool _outOfChina(double longitude, double latitude) {
    if (longitude < 72.004 || longitude > 137.8347) return true;
    if (latitude < 0.8293 || latitude > 55.8271) return true;
    return false;
  }

  /// WGS84 → GCJ-02。
  NavCoordinate wgs84ToGcj02(NavCoordinate source) => _transform(source);

  /// WGS84 → BD-09（经 GCJ-02）。
  NavCoordinate wgs84ToBd09(NavCoordinate source) =>
      _gcj02ToBd09(wgs84ToGcj02(source));

  NavCoordinate _gcj02ToBd09(NavCoordinate source) {
    final x = source.longitude;
    final y = source.latitude;
    final z =
        math.sqrt(x * x + y * y) + 0.00002 * math.sin(y * _pi * 3000.0 / 180.0);
    final theta =
        math.atan2(y, x) + 0.000003 * math.cos(x * _pi * 3000.0 / 180.0);
    final bdLng = z * math.cos(theta) + 0.0065;
    final bdLat = z * math.sin(theta) + 0.006;
    return NavCoordinate(longitude: bdLng, latitude: bdLat);
  }

  NavCoordinate _transform(NavCoordinate source) {
    if (_outOfChina(source.longitude, source.latitude)) return source;
    double dLat = _transformLat(
      source.longitude - 105.0,
      source.latitude - 35.0,
    );
    double dLng = _transformLng(
      source.longitude - 105.0,
      source.latitude - 35.0,
    );
    final radLat = source.latitude / 180.0 * _pi;
    double magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * math.cos(radLat) * _pi);
    return NavCoordinate(
      longitude: source.longitude + dLng,
      latitude: source.latitude + dLat,
    );
  }

  double _transformLat(double x, double y) {
    var ret =
        -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret +=
        (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) *
        2.0 /
        3.0;
    ret +=
        (20.0 * math.sin(y * _pi) + 40.0 * math.sin(y / 3.0 * _pi)) * 2.0 / 3.0;
    ret +=
        (160.0 * math.sin(y / 12.0 * _pi) + 320 * math.sin(y * _pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  double _transformLng(double x, double y) {
    var ret =
        300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret +=
        (20.0 * math.sin(6.0 * x * _pi) + 20.0 * math.sin(2.0 * x * _pi)) *
        2.0 /
        3.0;
    ret +=
        (20.0 * math.sin(x * _pi) + 40.0 * math.sin(x / 3.0 * _pi)) * 2.0 / 3.0;
    ret +=
        (150.0 * math.sin(x / 12.0 * _pi) + 300.0 * math.sin(x / 30.0 * _pi)) *
        2.0 /
        3.0;
    return ret;
  }
}
