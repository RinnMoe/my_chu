import "../../capabilities/campus_places/campus_places.dart";

/// 从课表格子文本中提取地点并构造统一地点请求。
///
/// 我的课表页面复用本层，与考试、排课和地图搜索走同一
/// 地点解析与跳转链路。
class AcademicSchedulePlace {
  /// 地点特征关键词（第一阶段启发式：按优先级）。
  static const List<String> _locationKeywords = [
    "教学楼",
    "实验楼",
    "图书馆",
    "明远",
    "修远",
    "鸿远",
    "北院",
    "教室",
    "楼",
    '实验室',
  ];

  static const PlaceInputParser _inputParser = PlaceInputParser();

  /// 从课表格子描述文本中提取地点文本。
  ///
  /// 描述通常为多行（课程/周次/教师/地点混排），地点一般位于最后；
  /// 命中地点特征关键词的短行优先，其次由统一地点 parser 判断是否含编码。
  /// 找不到返回 null（调用方决定是否提示“未识别”）。
  static String? extractLocation(String description) {
    final trimmed = description.trim();
    if (trimmed.isEmpty) return null;

    final lines = trimmed
        .split(RegExp(r"[\n\r]+"))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return null;

    // 从后往前：地点通常在末尾。
    for (final line in lines.reversed) {
      if (_locationKeywords.any(line.contains)) return line;
    }

    // 编码行识别交给统一兼容层，避免课表维护第二套地点编码规则。
    for (final line in lines.reversed) {
      if (_inputParser.hasCodeCandidate(line)) return line;
    }
    return null;
  }
}
