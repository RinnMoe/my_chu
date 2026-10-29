import '../fenfa/fenfa_client.dart';
import 'app_announcement.dart';

/// 应用公告只读数据源。
///
/// 实现只负责传输与解析，不持有缓存、门禁或聚合逻辑；这些策略集中在
/// `AppContentService`，便于两个后端共用同一套行为。
abstract interface class AnnouncementRepository {
  Future<List<AppAnnouncement>> fetchAnnouncements();
}

/// Fenfa 公告数据源（迁移前的既有实现）。
class FenfaAnnouncementRepository implements AnnouncementRepository {
  FenfaAnnouncementRepository({FenfaClient? client})
    : _client = client ?? FenfaClient();

  final FenfaClient _client;

  @override
  Future<List<AppAnnouncement>> fetchAnnouncements() async {
    final items = await _client.fetchAnnouncements();
    return [
      for (final item in items)
        AppAnnouncement(id: item.id, title: item.title, content: item.content),
    ];
  }
}
