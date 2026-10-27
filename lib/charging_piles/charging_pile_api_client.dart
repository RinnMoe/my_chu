import 'dart:convert';

import '../services/charging_credential_service.dart';
import '../services/public_http_client.dart';
import 'charging_pile_models.dart';

abstract interface class ChargingPileApi {
  Future<List<ChargingPileSlot>> queryDevice(
    String id,
    ChargingPileCancellation cancellation,
  );
}

class ChargingPileApiClient implements ChargingPileApi {
  ChargingPileApiClient(this.credentials);
  final ChargingCredentialService credentials;

  @override
  Future<List<ChargingPileSlot>> queryDevice(
    String id,
    ChargingPileCancellation cancellation,
  ) async {
    try {
      final response = await credentials.queryDevice(id, cancellation);
      cancellation.check();
      if (response.statusCode == 429) {
        throw const ChargingPileException(ChargingPileFailure.rateLimited);
      }
      if (response.statusCode >= 500 || response.statusCode == 408) {
        throw const ChargingPileException(ChargingPileFailure.network);
      }
      if (response.statusCode != 200) {
        throw const ChargingPileException(ChargingPileFailure.platform);
      }
      final body = PublicHttpClient.decodeJsonMap(
        utf8.decode(response.bodyBytes),
      );
      final code = body['code'].toString();
      if (code == '429' ||
          code == '503' ||
          (code != '200' &&
              RegExp(
                r'频繁|限流|too many|rate.limit',
                caseSensitive: false,
              ).hasMatch(
                body['message'] is String ? body['message'] as String : '',
              ))) {
        throw const ChargingPileException(ChargingPileFailure.rateLimited);
      }
      if (code != '200') {
        throw const ChargingPileException(ChargingPileFailure.platform);
      }
      final data = body['data'];
      if (data is! Map<String, dynamic>) throw const FormatException();
      final raw = data['slotsData'];
      if (raw is! List || raw.isEmpty || raw.length > 20)
        throw const FormatException();
      final slots = <ChargingPileSlot>[];
      final seen = <int>{};
      for (final item in raw) {
        if (item is! Map) throw const FormatException();
        final id = int.tryParse(item['slotId'].toString());
        final status = int.tryParse(item['status'].toString());
        if (id == null ||
            id < 1 ||
            id > 20 ||
            !seen.add(id) ||
            status == null ||
            status < 0 ||
            status > 9)
          throw const FormatException();
        slots.add(ChargingPileSlot(slotId: id, status: status));
      }
      return slots..sort((a, b) => a.slotId.compareTo(b.slotId));
    } on ChargingPileException {
      rethrow;
    } on PublicHttpException {
      throw const ChargingPileException(ChargingPileFailure.network);
    } catch (_) {
      throw const ChargingPileException(ChargingPileFailure.malformed);
    }
  }
}
