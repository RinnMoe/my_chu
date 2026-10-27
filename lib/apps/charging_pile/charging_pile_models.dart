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
