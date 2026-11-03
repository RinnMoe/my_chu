import 'app_announcement.dart';

/// 应用公告只读数据源。
///
/// 实现只负责传输与解析，不持有缓存、门禁或聚合逻辑；这些策略集中在
/// `AppContentService`，替换数据源时行为保持一致。
abstract interface class AnnouncementRepository {
  Future<List<AppAnnouncement>> fetchAnnouncements();
}
