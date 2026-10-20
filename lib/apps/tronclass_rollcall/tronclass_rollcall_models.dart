enum TronclassRollcallType { number, qr, radar, unknown }

class TronclassRollcall {
  const TronclassRollcall({
    required this.id,
    required this.courseId,
    required this.courseTitle,
    required this.type,
  });

  final String id;
  final String courseId;
  final String courseTitle;
  final TronclassRollcallType type;

  String get typeLabel => switch (type) {
    TronclassRollcallType.number => '数字点名',
    TronclassRollcallType.qr => '扫码点名',
    TronclassRollcallType.radar => '雷达点名',
    TronclassRollcallType.unknown => '畅课点名',
  };

  static List<TronclassRollcall> parseList(Object? json) {
    if (json is! Map || json['rollcalls'] is! List) {
      throw const FormatException('Invalid rollcall response');
    }
    final result = <String, TronclassRollcall>{};
    for (final raw in json['rollcalls'] as List) {
      if (raw is! Map) throw const FormatException('Invalid rollcall');
      if (raw['rollcall_status'] != 'in_progress' ||
          raw['is_expired'] != false ||
          raw['status'] != 'absent') {
        continue;
      }
      final id = rollcallIdentifier(raw['rollcall_id']);
      final courseId = rollcallIdentifier(raw['course_id']);
      if (id == null || courseId == null) {
        throw const FormatException('Invalid rollcall identifier');
      }
      result.putIfAbsent(
        id,
        () => TronclassRollcall(
          id: id,
          courseId: courseId,
          courseTitle:
              raw['course_title'] is String
                  ? (raw['course_title'] as String).trim()
                  : '',
          type: switch (raw['source']) {
            'number' => TronclassRollcallType.number,
            'qr' => TronclassRollcallType.qr,
            'radar' => TronclassRollcallType.radar,
            _ => TronclassRollcallType.unknown,
          },
        ),
      );
    }
    return List.unmodifiable(result.values);
  }
}

String? rollcallIdentifier(Object? value) {
  if (value is! String && value is! int) return null;
  final text = '$value';
  if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;
  final number = int.tryParse(text);
  return number != null && number > 0 ? '$number' : null;
}

enum RollcallFailure {
  network,
  authentication,
  invalidResponse,
  rejected,
  ended,
  uncertain,
}

class RollcallException implements Exception {
  const RollcallException(this.failure);
  final RollcallFailure failure;

  String get message => switch (failure) {
    RollcallFailure.network => '签到暂时无法更新，请稍后重试。',
    RollcallFailure.authentication => '畅课登录已失效，请重新登录后再操作。',
    RollcallFailure.invalidResponse => '畅课返回异常，请刷新后重试。',
    RollcallFailure.rejected => '应答未成功，请核对签到码或重新扫码。',
    RollcallFailure.ended => '本次点名已结束。',
    RollcallFailure.uncertain => '应答结果待确认，请刷新签到状态后查看。',
  };
}
