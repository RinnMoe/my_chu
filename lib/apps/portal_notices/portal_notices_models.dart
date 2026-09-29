typedef PortalNoticesLoader = Future<List<PortalNotice>> Function();

class PortalNotice {
  final String id;
  final String title;
  final String department;
  final String publishedAt;
  final String detailUrl;
  final String type;
  final String column;
  final String tagId;
  final bool pinned;
  final bool read;

  const PortalNotice({
    required this.id,
    required this.title,
    required this.department,
    required this.publishedAt,
    this.detailUrl = '',
    this.type = '',
    this.column = '',
    this.tagId = '',
    this.pinned = false,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'department': department,
    'publishedAt': publishedAt,
    'detailUrl': detailUrl,
    'type': type,
    'column': column,
    'tagId': tagId,
    'pinned': pinned,
    'read': read,
  };

  static PortalNotice fromJson(Map<String, dynamic> json) => PortalNotice(
    id: _string(json['id']),
    title: _string(json['title']),
    department: _string(json['department']),
    publishedAt: _string(json['publishedAt']),
    detailUrl: _string(json['detailUrl']),
    type: _string(json['type']),
    column: _string(json['column']),
    tagId: _string(json['tagId']),
    pinned: json['pinned'] == true,
    read: json['read'] == true,
  );

  static String _string(Object? value) => value?.toString() ?? '';
}

class PortalNoticePage {
  final List<PortalNotice> items;
  final int totalSize;
  final int pageNumber;
  final int pageSize;

  const PortalNoticePage({
    required this.items,
    required this.totalSize,
    required this.pageNumber,
    required this.pageSize,
  });

  bool get hasMore => totalSize > 0
      ? pageNumber * pageSize < totalSize
      : items.length == pageSize;
}
