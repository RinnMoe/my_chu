/// 地图展示与业务跳转的共享模型。
///
/// 地点与教室数据来自 semantic layer；
/// 选中状态和 renderer marker 由地图能力管理。
library;

import "../campus_places/campus_places.dart";
import "../external_navigation/external_navigation.dart";

/// 选中结果：保存地图展示与导航所需的地点数据。
class ResolvedPlaceSelection {
  final String campusId;
  final CampusPlace? place;
  final CampusClassroom? classroom;
  final ExternalNavigationTarget? externalNavigationTarget;
  final bool showInfoCard;
  final bool showExternalNavigation;

  const ResolvedPlaceSelection({
    required this.campusId,
    this.place,
    this.classroom,
    this.externalNavigationTarget,
    this.showInfoCard = true,
    this.showExternalNavigation = true,
  });
}

/// Unified bottom-card model for campus places.
class MapPlacePresentation {
  final String title;
  final String? subtitle;
  final CampusPlace? campusPlace;
  final ExternalNavigationTarget? navigationTarget;
  final bool showInfoCard;
  final bool showExternalNavigation;

  const MapPlacePresentation({
    required this.title,
    this.subtitle,
    this.campusPlace,
    this.navigationTarget,
    this.showInfoCard = true,
    this.showExternalNavigation = true,
  });

  factory MapPlacePresentation.fromResolvedSelection(
    ResolvedPlaceSelection selection, {
    String? campusName,
  }) {
    final place = selection.place;
    final classroom = selection.classroom;
    return MapPlacePresentation(
      title: place?.name ?? campusName ?? "已识别地点",
      subtitle: classroom != null ? _classroomSubtitle(classroom) : null,
      campusPlace: place,
      navigationTarget: selection.externalNavigationTarget,
      showInfoCard: selection.showInfoCard,
      showExternalNavigation: selection.showExternalNavigation,
    );
  }

  /// 教室副标题：只输出完整标准编号，楼层有意义时追加“ · X层”。
  ///
  /// 不再把解析器内部的 座别/区域/房间号片段 直接暴露给用户。
  static String? _classroomSubtitle(CampusClassroom classroom) {
    final code = classroom.classroomId.trim().toUpperCase();
    if (code.isEmpty) return null;
    final floor = classroom.floor;
    return floor == null ? code : "$code · $floor层";
  }
}
