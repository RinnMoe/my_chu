import 'dart:async';

/// Stable, non-secret catalog and availability types shared by all consumers.
enum ChargingPileArea {
  chaohui('朝晖体育场南', '渭水-朝晖体育场南'),
  northGate('北门', '渭水-北门'),
  building20('20号楼', '渭水-20号楼'),
  propertyCenter('物业服务中心', '渭水-物业服务中心'),

  /// Fallback for a catalog entry whose location has no mapping yet. A stale
  /// catalog degrades to one "未分区" group instead of failing the whole page.
  unknown('未分区', '');

  const ChargingPileArea(this.label, this.location);
  final String label;
  final String location;
}

class ChargingPileDevice {
  const ChargingPileDevice({
    required this.id,
    required this.code,
    required this.name,
    required this.location,
  });
  final String id;
  final String code;
  final String name;
  final String location;
  String get campusId => 'weishui';
  ChargingPileArea get area => ChargingPileArea.values.firstWhere(
    (area) => area.location == location,
    orElse: () => ChargingPileArea.unknown,
  );
}

class ChargingPileSlot {
  const ChargingPileSlot({required this.slotId, required this.status});
  final int slotId;

  /// Keep the upstream value; only 0 (free) and 1 (occupied) are classified.
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

  /// Time of the successful response, never batch start or a failed attempt.
  final DateTime fetchedAt;
  int get freeSlots => slots.where((slot) => slot.free).length;
  int get occupiedSlots => slots.where((slot) => slot.occupied).length;
  int get otherSlots => slots.length - freeSlots - occupiedSlots;
}

enum ChargingPileFailure {
  credentialUnavailable,
  credentialSync,
  network,
  rateLimited,
  malformed,
  platform,
  storage,
  cancelled,
  consentRequired;

  String get message => switch (this) {
    credentialUnavailable => '共享凭证暂不可用，待源站更新后重试。',
    credentialSync => '共享凭证同步失败，请稍后重试。',
    network => '网络暂时无法连接，请稍后重试。',
    rateLimited => '平台请求受限，已暂停查询，请稍后重试。',
    malformed => '平台返回的数据无法识别，请稍后重试。',
    platform => '设备暂不可用，请稍后重试。',
    storage => '本机凭证存储不可用，请重试。',
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

class ChargingPileDeviceState {
  const ChargingPileDeviceState({this.status, this.failure});
  final ChargingPileDeviceStatus? status;
  final ChargingPileFailure? failure;
}

/// How much a known status can be trusted when it is shown to a user.
///
/// [unavailable] always means "no confirmed status": never queried, or the last
/// query failed. It is not an availability answer, so it must not be rendered
/// as "已占满".
enum ChargingPileStatusFreshness {
  /// Confirmed within the live window: safe to show as a current answer.
  live,

  /// Confirmed earlier than the live window: still informative, no longer live.
  stale,

  /// Older than the stale window: keep as context, re-query before trusting.
  expired,

  /// No confirmed status at all.
  unavailable;

  bool get isKnown => this != unavailable;
}

/// 面向用户的可用性结论。
///
/// 只有实时确认过的状态才能给出 [free] / [occupied]；未查询、查询失败、
/// 陈旧与过期一律 [unknown]，不能因为缓存里还留着旧数字就当作当前答案。
enum ChargingPileAvailability { unknown, free, occupied }

/// 把状态与新鲜度折算成唯一结论。
///
/// 地图图层与应用页共用本函数，避免同一份缓存在不同界面给出不同答案。
ChargingPileAvailability chargingPileAvailabilityOf(
  ChargingPileDeviceState state,
  ChargingPileStatusFreshness freshness,
) {
  final status = state.status;
  if (status == null || freshness != ChargingPileStatusFreshness.live) {
    return ChargingPileAvailability.unknown;
  }
  if (status.freeSlots > 0) return ChargingPileAvailability.free;
  if (status.occupiedSlots > 0 && status.otherSlots == 0) {
    return ChargingPileAvailability.occupied;
  }
  return ChargingPileAvailability.unknown;
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
