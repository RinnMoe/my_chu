import '../capabilities/academic_schedule/recent_schedule.dart';
import 'campus_session.dart';
import 'service_endpoints.dart';

class RoomisScheduleService {
  Future<RecentScheduleWindow> fetch(DateTime today) async {
    final uri = CampusServiceEndpoints.roomisSchedulesUri.replace(
      queryParameters: {
        'start': recentScheduleDate(today),
        'end': recentScheduleDate(today.add(const Duration(days: 6))),
        'status': 'ACTIVE',
      },
    );
    final response = await CampusSession.client(
      CampusServices.roomisSchedule,
    ).request(
      'GET',
      uri.toString(),
      extraHeaders: {'Accept': 'application/json'},
    );
    return parseRoomisSchedule(
      response.body,
      today,
      fetchedAt: DateTime.now().toUtc(),
    );
  }
}
