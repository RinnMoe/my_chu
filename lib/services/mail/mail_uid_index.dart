/// 文件夹内真实 UID 列表的分页索引。
///
/// IMAP UID 不连续，按数字区间翻页会在稀疏邮箱中产生大量空页；这里用
/// `UID SEARCH ALL` 的结果做游标，保证每页都有内容且不重复。
class MailUidSlice {
  final List<int> uids;
  final int? nextBeforeUid;
  final bool hasMore;

  const MailUidSlice({
    required this.uids,
    required this.nextBeforeUid,
    required this.hasMore,
  });
}

class MailUidIndex {
  MailUidIndex({required this.uidValidity, required List<int> uidsAscending})
    : uidsDesc = List.unmodifiable(
        (uidsAscending.toSet().toList()..sort((a, b) => b.compareTo(a))),
      );

  final int? uidValidity;

  /// 降序排列的 UID，首页从索引 0 开始。
  final List<int> uidsDesc;

  bool get isEmpty => uidsDesc.isEmpty;

  /// 返回从 [beforeUid] 之前（不含）开始的下一页。
  ///
  /// [beforeUid] 为空表示第一页；返回 null 表示没有更多数据。
  MailUidSlice? slice({int? beforeUid, int limit = 20}) {
    if (limit < 1 || uidsDesc.isEmpty) return null;
    var start = 0;
    if (beforeUid != null) {
      start = uidsDesc.indexWhere((uid) => uid < beforeUid);
      if (start < 0) return null;
    }
    if (start >= uidsDesc.length) return null;

    final end = (start + limit).clamp(0, uidsDesc.length);
    final page = uidsDesc.sublist(start, end);
    return MailUidSlice(
      uids: page,
      nextBeforeUid: page.last,
      hasMore: end < uidsDesc.length,
    );
  }

  /// 判断索引是否还能代表服务器当前状态。
  ///
  /// 新邮件会让 `uidNext` 变大，删除会让 `messagesExists` 变小，两者任一
  /// 变化都重建索引；`uidValidity` 变化时必须丢弃旧索引。
  bool isStale({int? uidValidity, int? uidNext, int? messagesExists}) {
    if (this.uidValidity != null &&
        uidValidity != null &&
        this.uidValidity != uidValidity) {
      return true;
    }
    if (messagesExists != null && messagesExists != uidsDesc.length) {
      return true;
    }
    if (uidsDesc.isEmpty) return (uidNext ?? 0) > 1;
    if (uidNext != null && uidNext - 1 > uidsDesc.first) return true;
    return false;
  }
}
