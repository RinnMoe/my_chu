class MobileCampusNoticeColumn {
  final String tagId;
  final String tagName;

  const MobileCampusNoticeColumn({required this.tagId, required this.tagName});
}

class MobileCampusNoticeSearchGroup {
  final String tagId;
  final String tagName;
  final int count;
  final String latestTitle;
  final String type;

  const MobileCampusNoticeSearchGroup({
    required this.tagId,
    required this.tagName,
    required this.count,
    required this.latestTitle,
    this.type = '',
  });
}

class MobileCampusNoticeDetail {
  final String messageId;
  final String tagId;
  final String title;
  final String department;
  final String publishedAt;
  final String contentHtml;
  final bool read;

  const MobileCampusNoticeDetail({
    required this.messageId,
    required this.tagId,
    required this.title,
    required this.department,
    required this.publishedAt,
    required this.contentHtml,
    required this.read,
  });
}
