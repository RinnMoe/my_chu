/// Typed, defensive models for the normal-user channel-resources API.
///
/// The service returns IDs as strings even when the server serializes them as
/// JSON numbers. This keeps long QQ/channel IDs lossless at the UI boundary.
class ChannelResourcesJson {
  const ChannelResourcesJson._();

  static Map<String, dynamic>? map(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static List<Object?>? list(Object? value) {
    if (value is! List) return null;
    return List<Object?>.from(value);
  }

  static String? string(Object? value) {
    if (value is String) return value;
    if (value is num) return value.toString();
    return null;
  }

  static String text(
    Map<String, dynamic> map,
    String key, {
    String fallback = '',
  }) => string(map[key]) ?? fallback;

  static int number(Map<String, dynamic> map, String key, {int fallback = 0}) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(string(value) ?? '') ?? fallback;
  }

  static bool boolean(
    Map<String, dynamic> map,
    String key, {
    bool fallback = false,
  }) {
    final value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return fallback;
  }

  static List<String> strings(Object? value) {
    if (value is String) {
      return value
          .split(RegExp(r'[,，\s]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final values = list(value);
    if (values == null) return const <String>[];
    return values
        .map(string)
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class ChannelResource {
  final String id;
  final String name;
  final String link;
  final String fakeId;
  final List<String> tags;
  final int points;
  final int downloads;
  final bool approved;
  final bool owned;

  const ChannelResource({
    required this.id,
    required this.name,
    required this.link,
    required this.fakeId,
    required this.tags,
    required this.points,
    required this.downloads,
    required this.approved,
    required this.owned,
  });

  factory ChannelResource.fromJson(
    Map<String, dynamic> json, {
    bool owned = false,
  }) => ChannelResource(
    id: ChannelResourcesJson.text(json, 'id'),
    name: ChannelResourcesJson.text(json, 'name', fallback: '未命名资料'),
    link: ChannelResourcesJson.text(json, 'link'),
    fakeId: ChannelResourcesJson.text(json, 'fake_id'),
    tags: ChannelResourcesJson.strings(json['tags']),
    points: ChannelResourcesJson.number(json, 'points'),
    downloads: ChannelResourcesJson.number(json, 'downloads'),
    approved: ChannelResourcesJson.boolean(json, 'approved', fallback: true),
    owned: owned,
  );
}

class ChannelResourcePage {
  final List<ChannelResource> resources;
  final int page;
  final int perPage;
  final int totalPages;
  final int totalResources;
  final String sortBy;
  final String sortNotice;

  const ChannelResourcePage({
    required this.resources,
    required this.page,
    required this.perPage,
    required this.totalPages,
    required this.totalResources,
    required this.sortBy,
    required this.sortNotice,
  });
}

class ChannelTag {
  final String id;
  final String name;

  const ChannelTag({required this.id, required this.name});

  factory ChannelTag.fromJson(Map<String, dynamic> json) => ChannelTag(
    id: ChannelResourcesJson.text(json, 'id'),
    name: ChannelResourcesJson.text(json, 'name'),
  );
}

class ChannelAnnouncement {
  final String id;
  final String title;
  final String content;
  final String publishedAt;

  const ChannelAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.publishedAt,
  });

  factory ChannelAnnouncement.fromJson(Map<String, dynamic> json) =>
      ChannelAnnouncement(
        id: ChannelResourcesJson.text(json, 'id'),
        title: ChannelResourcesJson.text(json, 'title', fallback: '校园公告'),
        content: ChannelResourcesJson.text(
          json,
          'content',
          fallback: ChannelResourcesJson.text(json, 'message'),
        ),
        publishedAt: ChannelResourcesJson.text(
          json,
          'published_at',
          fallback: ChannelResourcesJson.text(json, 'timestamp'),
        ),
      );
}

class ChannelLink {
  final String id;
  final String name;
  final String url;

  const ChannelLink({required this.id, required this.name, required this.url});

  factory ChannelLink.fromJson(Map<String, dynamic> json) => ChannelLink(
    id: ChannelResourcesJson.text(json, 'id'),
    name: ChannelResourcesJson.text(json, 'name', fallback: '校园链接'),
    url: ChannelResourcesJson.text(json, 'url'),
  );
}

class ChannelMessage {
  final String id;
  final String content;
  final String createdAt;

  const ChannelMessage({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  factory ChannelMessage.fromJson(Map<String, dynamic> json) => ChannelMessage(
    id: ChannelResourcesJson.text(json, 'id'),
    content: ChannelResourcesJson.text(json, 'content'),
    createdAt: ChannelResourcesJson.text(json, 'created_at'),
  );
}

class ChannelAdmin {
  final String id;
  final String nickname;

  const ChannelAdmin({required this.id, required this.nickname});

  factory ChannelAdmin.fromJson(Map<String, dynamic> json) => ChannelAdmin(
    id: ChannelResourcesJson.text(json, 'id'),
    nickname: ChannelResourcesJson.text(json, 'nickname', fallback: '管理员'),
  );
}

class ChannelReviewStats {
  final Map<String, int> counts;

  const ChannelReviewStats(this.counts);
}

class ChannelCheckinResult {
  final bool alreadyCheckedIn;
  final int rewardPoints;
  final int points;

  const ChannelCheckinResult({
    required this.alreadyCheckedIn,
    required this.rewardPoints,
    required this.points,
  });
}
