import 'dart:async';

/// 一个 WGS84 点位。目录里的坐标是 GCJ-02，解析时已转过一次。
class ChargingPileGeoPoint {
  const ChargingPileGeoPoint({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is ChargingPileGeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// 分区。由站点目录驱动，不再是对应站点分区的编译期 `enum`：
/// 站点新增一个分区时，目录里多一条，App 就能显示、筛选、落图。
///
/// [areaId] 与站点 `devices[].location` 逐字一致（例如 `渭水-住宅`）；
/// [key] 是站点内部的分区键（`chaohui` / `zhu` …），也是 `/api/stats` 的区键；
/// [name] 是地址胶囊上的短名。
class ChargingPileArea {
  const ChargingPileArea({
    required this.areaId,
    required this.key,
    required this.name,
    required this.campusId,
    this.statsKey,
  });

  /// 目录里没有该分区时的兜底。`areaId` 为空串。
  static const ChargingPileArea unknown = ChargingPileArea(
    areaId: '',
    key: '',
    name: '未分区',
    campusId: '',
  );

  final String areaId;
  final String key;
  final String name;

  /// 该分区所属校区，由站点 `location` 前缀派生（`渭水-` → `weishui`）。
  /// 站点不单独下发校区字段，而地图按校区渲染，所以这层派生是必须的。
  final String campusId;

  /// 站点 `/api/stats` 的 `areas` 键；该分区没有统计时为 null。
  final String? statsKey;

  String get label => name;

  /// 兼容旧调用点：历史上 `area.location` 就是分区全名。
  String get location => areaId;

  @override
  bool operator ==(Object other) =>
      other is ChargingPileArea && other.areaId == areaId;

  @override
  int get hashCode => areaId.hashCode;

  @override
  String toString() => 'ChargingPileArea($areaId)';
}

/// 设备背后的数据源平台。`zm` 是住芒（站点未写 `src` 的默认值）。
enum ChargingPileSource {
  zhumang('zm'),
  lvcc('lvcc');

  const ChargingPileSource(this.wireValue);

  /// 与站点 `/api/pile` 请求体 `src` 字段一致的取值。
  final String wireValue;

  /// 站点目录里缺省 `src` 表示住芒；未知取值返回 null，由调用方决定降级。
  static ChargingPileSource? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return zhumang;
    for (final source in ChargingPileSource.values) {
      if (source.wireValue == raw) return source;
    }
    return null;
  }
}

/// 目录里的一台设备。字段与站点 `catalog.json` 的 `devices[]` 一一对应。
class ChargingPileDevice {
  const ChargingPileDevice({
    required this.id,
    required this.code,
    required this.name,
    required this.area,
    this.source = ChargingPileSource.zhumang,
    this.portCount,
    this.point,
  });

  final String id;

  /// 站点桩号（`TY-01` / `A03` / `E-24` / `Z-01`），地图落点与排序键。
  final String code;

  final String name;

  final ChargingPileArea area;

  final ChargingPileSource source;

  /// 平台标称口数。只用于「查询失败时按应有口数计入无效」，
  /// 真实口数一律以平台返回为准。
  final int? portCount;

  final ChargingPileGeoPoint? point;

  String get location => area.areaId;

  /// 所属校区；地图按它把设备分到各自的校区底图上。
  String get campusId => area.campusId;

  @override
  bool operator ==(Object other) =>
      other is ChargingPileDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChargingPileDevice($id/$code)';
}

class ChargingPileSlot {
  const ChargingPileSlot({required this.slotId, required this.status});
  final int slotId;

  /// 平台原值，但已按站点口径归一：0 空闲 / 1 占用 / 2 其他（异常、离线等）。
  final int status;
  bool get free => status == 0;
  bool get occupied => status == 1;
}

class ChargingPileDeviceStatus {
  ChargingPileDeviceStatus({
    required this.device,
    required List<ChargingPileSlot> slots,
    required this.fetchedAt,
  }) : slots = List.unmodifiable(slots);
  final ChargingPileDevice device;
  final List<ChargingPileSlot> slots;

  /// 成功响应的时间，既不是批次开始时间，也不是失败尝试的时间。
  final DateTime fetchedAt;
  int get freeSlots => slots.where((slot) => slot.free).length;
  int get occupiedSlots => slots.where((slot) => slot.occupied).length;
  int get otherSlots => slots.length - freeSlots - occupiedSlots;
}

enum ChargingPileFailure {
  credentialUnavailable,
  network,
  rateLimited,
  throttled,
  malformed,
  platform,
  storage,
  cancelled,
  consentRequired;

  String get message => switch (this) {
    credentialUnavailable => '共享凭证暂不可用，待源站更新后重试。',
    network => '网络暂时无法连接，请稍后重试。',
    rateLimited => '这一分钟查得太多，先用最近一次的结果，过十几秒再点。',
    throttled => '这一分钟查得太多，先用最近一次的结果，过十几秒再点。',
    malformed => '平台返回的数据无法识别，请稍后重试。',
    platform => '设备暂不可用，请稍后重试。',
    storage => '本机存储不可用，请重试。',
    cancelled => '查询已停止。',
    consentRequired => '请先同意用户协议。',
  };
}

class ChargingPileException implements Exception {
  const ChargingPileException(this.failure);
  final ChargingPileFailure failure;
  @override
  String toString() => 'ChargingPileException(${failure.name})';
}

/// 一台设备的展示状态。
///
/// 与站点口径一致：**查询失败不保留上一次的成功数据**——站点在失败时把
/// `ports` 清空并显示「未知」，这里同样只保留 [failure]，由 UI 显示未知。
class ChargingPileDeviceState {
  const ChargingPileDeviceState({this.status, this.failure});
  final ChargingPileDeviceStatus? status;
  final ChargingPileFailure? failure;
}

/// 有数据时持续使用最近一次成功结果；无数据时不推断可用性。
enum ChargingPileStatusFreshness { live, unavailable }

/// 面向用户的可用性结论，不随数据年龄改变。
enum ChargingPileAvailability { unknown, free, occupied }

ChargingPileAvailability chargingPileAvailabilityOf(
  ChargingPileDeviceState state,
  ChargingPileStatusFreshness freshness,
) {
  final status = state.status;
  if (status == null) return ChargingPileAvailability.unknown;
  if (status.freeSlots > 0) return ChargingPileAvailability.free;
  return ChargingPileAvailability.occupied;
}

/// Cooperative cancellation shared by queues, retry delays and response fences.
class ChargingPileCancellation {
  final _done = Completer<void>();
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    _cancelled = true;
    if (!_done.isCompleted) _done.complete();
  }

  void check() {
    if (_cancelled) {
      throw const ChargingPileException(ChargingPileFailure.cancelled);
    }
  }
}
