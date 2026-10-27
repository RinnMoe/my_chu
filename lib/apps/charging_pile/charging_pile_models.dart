/// Data models for the read-only charging-pile availability app.
library;

/// A physical charging pile in the built-in campus catalog.
class ChargingPileDevice {
  final String id;
  final String code;
  final String name;
  final String location;

  const ChargingPileDevice({
    required this.id,
    required this.code,
    required this.name,
    required this.location,
  });
}

/// One slot returned by the third-party platform.
///
/// The upstream API reports `status == 0` for a free slot; every other value
/// is treated as occupied or otherwise unavailable.
class ChargingPileSlot {
  final int slotId;
  final bool free;

  const ChargingPileSlot({required this.slotId, required this.free});
}

/// A successfully queried pile.
class ChargingPileDeviceStatus {
  final ChargingPileDevice device;
  final List<ChargingPileSlot> slots;
  final DateTime fetchedAt;

  const ChargingPileDeviceStatus({
    required this.device,
    required this.slots,
    required this.fetchedAt,
  });

  int get freeSlots => slots.where((slot) => slot.free).length;
  int get occupiedSlots => slots.length - freeSlots;
  bool get hasFreeSlot => freeSlots > 0;
}

/// A pile that could not be queried in the current refresh.
class ChargingPileDeviceFailure {
  final ChargingPileDevice device;
  final String message;
  final bool authFailure;
  final DateTime fetchedAt;

  const ChargingPileDeviceFailure({
    required this.device,
    required this.message,
    this.authFailure = false,
    required this.fetchedAt,
  });
}

/// Outcome of one refresh round.
class ChargingPileRefreshResult {
  final DateTime fetchedAt;
  final List<ChargingPileDeviceStatus> statuses;
  final List<ChargingPileDeviceFailure> failures;
  final bool authFailed;

  const ChargingPileRefreshResult({
    required this.fetchedAt,
    required this.statuses,
    required this.failures,
    this.authFailed = false,
  });
}

enum ChargingPileTokenState { none, invalid, expired, expiringSoon, valid, opaque }

/// Local interpretation of the user-provided JWT.
///
/// The token itself is deliberately not part of this model so it never enters
/// UI state, logs, or error reports.
class ChargingPileTokenInfo {
  final ChargingPileTokenState state;
  final DateTime? expiresAt;

  const ChargingPileTokenInfo({required this.state, this.expiresAt});

  static const none = ChargingPileTokenInfo(state: ChargingPileTokenState.none);

  bool get exists => state != ChargingPileTokenState.none;
}
