/// The business feature only receives non-secret responses from this host
/// capability. No campus account, cookie jar or network client is exposed.
library;

export '../services/dorm_electricity_session_service.dart'
    show
        DormElectricityException,
        DormElectricityRequest,
        DormElectricityResponse,
        DormElectricityQuery,
        dormElectricityFeatureId;

import '../services/dorm_electricity_session_service.dart';

class DormElectricityCapability {
  DormElectricityCapability({DormElectricitySessionService? session})
    : _session = session ?? DormElectricitySessionService();
  final DormElectricitySessionService _session;

  Future<DormElectricityResponse> resolveRoom({
    required String roomId,
    required String buildingInfo,
    required DormElectricityRequest request,
  }) => _session.resolveRoom(
    roomId: roomId,
    buildingInfo: buildingInfo,
    request: request,
  );

  Future<DormElectricityResponse> query({
    required String meter,
    required DormElectricityQuery kind,
    String? month,
    required DormElectricityRequest request,
  }) =>
      _session.query(meter: meter, kind: kind, month: month, request: request);
}
