import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'charging_pile_catalog.dart';
import 'charging_pile_models.dart';

/// Persists the last known per-device status so a cold start can show data
/// without waiting for a network round trip.
///
/// The document is versioned and validated as a whole before anything is
/// restored: a corrupt, truncated or unknown-schema value is ignored, and a
/// single malformed device entry is dropped instead of poisoning the snapshot.
/// Slot payloads are validated with the same bounds as the API decoder
/// (`slotId` 1..20, `status` 0..9, no duplicates) so restored data can never
/// contradict a live response.
///
/// Storage is best effort. Reads and writes never throw: a broken preferences
/// store must not break a refresh, it only loses the shortcut. No credential or
/// request material is ever written here.
class ChargingPileStatusCache {
  ChargingPileStatusCache({
    List<ChargingPileDevice>? catalog,
    Future<SharedPreferences> Function()? preferences,
  }) : _devices = {
         for (final device in catalog ?? kChargingPileDevices)
           device.id: device,
       },
       _preferences = preferences ?? SharedPreferences.getInstance;

  /// Versioned once; bump together with [schemaVersion] on an incompatible
  /// document change so old values are ignored instead of misread.
  static const storageKey = 'charging_pile.status_cache.v1';
  static const schemaVersion = 1;

  /// Upper bounds for one persisted document. The catalog is ~109 devices.
  static const maxDevices = 200;
  static const maxSlotsPerDevice = 20;

  static const int _minSlotId = 1;
  static const int _maxSlotId = 20;
  static const int _minSlotStatus = 0;
  static const int _maxSlotStatus = 9;

  final Map<String, ChargingPileDevice> _devices;
  final Future<SharedPreferences> Function() _preferences;

  /// Restored states, keyed by device id. Devices that are no longer in the
  /// catalog are skipped so a removed pile cannot resurrect on screen.
  Future<Map<String, ChargingPileDeviceState>> load() async {
    try {
      final preferences = await _preferences();
      final raw = preferences.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        return <String, ChargingPileDeviceState>{};
      }
      return _decode(raw);
    } catch (_) {
      return <String, ChargingPileDeviceState>{};
    }
  }

  /// Writes the statuses that are still confirmed. Failures are swallowed.
  Future<void> save(Map<String, ChargingPileDeviceState> states) async {
    try {
      final preferences = await _preferences();
      final entries = _encodeEntries(states);
      if (entries.isEmpty) {
        await preferences.remove(storageKey);
        return;
      }
      await preferences.setString(
        storageKey,
        jsonEncode({'schemaVersion': schemaVersion, 'devices': entries}),
      );
    } catch (_) {
      // Best effort: the next successful refresh retries the write.
    }
  }

  List<Map<String, Object>> _encodeEntries(
    Map<String, ChargingPileDeviceState> states,
  ) {
    final ids =
        states.keys.where((id) {
            final status = states[id]?.status;
            return status != null &&
                status.slots.isNotEmpty &&
                _devices.containsKey(id);
          }).toList()
          ..sort();
    final entries = <Map<String, Object>>[];
    for (final id in ids) {
      if (entries.length >= maxDevices) break;
      final status = states[id]!.status!;
      final slots = status.slots
          .take(maxSlotsPerDevice)
          .toList(growable: false);
      entries.add({
        'deviceId': id,
        'fetchedAt': status.fetchedAt.millisecondsSinceEpoch,
        'slots': [
          for (final slot in slots)
            {'slotId': slot.slotId, 'status': slot.status},
        ],
      });
    }
    return entries;
  }

  Map<String, ChargingPileDeviceState> _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, ChargingPileDeviceState>{};
    if (decoded['schemaVersion'] != schemaVersion) {
      return <String, ChargingPileDeviceState>{};
    }
    final entries = decoded['devices'];
    if (entries is! List) return <String, ChargingPileDeviceState>{};
    final states = <String, ChargingPileDeviceState>{};
    for (final entry in entries) {
      if (states.length >= maxDevices) break;
      if (entry is! Map) continue;
      final id = entry['deviceId'];
      if (id is! String) continue;
      final device = _devices[id];
      if (device == null) continue;
      final fetchedAt = _decodeFetchedAt(entry['fetchedAt']);
      if (fetchedAt == null) continue;
      final slots = _decodeSlots(entry['slots']);
      if (slots == null) continue;
      states[id] = ChargingPileDeviceState(
        status: ChargingPileDeviceStatus(
          device: device,
          slots: slots,
          fetchedAt: fetchedAt,
        ),
      );
    }
    return states;
  }

  /// Keeps the real observation time. The value is never rewritten to "now",
  /// otherwise a restarted app would claim stale data is live.
  static DateTime? _decodeFetchedAt(Object? value) {
    if (value is! int || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  static List<ChargingPileSlot>? _decodeSlots(Object? value) {
    if (value is! List || value.isEmpty || value.length > maxSlotsPerDevice) {
      return null;
    }
    final slots = <ChargingPileSlot>[];
    final seen = <int>{};
    for (final item in value) {
      if (item is! Map) return null;
      final slotId = item['slotId'];
      final status = item['status'];
      if (slotId is! int ||
          slotId < _minSlotId ||
          slotId > _maxSlotId ||
          !seen.add(slotId) ||
          status is! int ||
          status < _minSlotStatus ||
          status > _maxSlotStatus) {
        return null;
      }
      slots.add(ChargingPileSlot(slotId: slotId, status: status));
    }
    return slots..sort((a, b) => a.slotId.compareTo(b.slotId));
  }
}
