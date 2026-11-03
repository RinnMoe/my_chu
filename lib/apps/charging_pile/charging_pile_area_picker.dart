import 'package:flutter/material.dart';

import 'charging_pile_models.dart';

/// 一次校区/分区选择的结果。
class ChargingPileAreaSelection {
  const ChargingPileAreaSelection({required this.campusId, this.area});

  final String campusId;

  /// `null` 表示该校区下的「全部分区」。
  final ChargingPileArea? area;
}

/// 统一的校区 + 分区选择面板。
///
/// 校区是横向胶囊筛选、分区是下面的列表：选校区只切换列表内容，选中分区时
/// 校区与分区一起生效并关闭面板。校区不再是独立的下拉，避免「先切校区、
/// 再切分区」两次操作互相打断。
Future<ChargingPileAreaSelection?> showChargingPileAreaPicker(
  BuildContext context, {
  required List<ChargingPileArea> areas,
  required String activeCampusId,
  required ChargingPileArea? activeArea,
  required String Function(String campusId) campusLabel,
}) => showModalBottomSheet<ChargingPileAreaSelection>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder:
      (context) => _AreaPickerSheet(
        areas: areas,
        activeCampusId: activeCampusId,
        activeArea: activeArea,
        campusLabel: campusLabel,
      ),
);

class _AreaPickerSheet extends StatefulWidget {
  const _AreaPickerSheet({
    required this.areas,
    required this.activeCampusId,
    required this.activeArea,
    required this.campusLabel,
  });

  final List<ChargingPileArea> areas;
  final String activeCampusId;
  final ChargingPileArea? activeArea;
  final String Function(String campusId) campusLabel;

  @override
  State<_AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends State<_AreaPickerSheet> {
  late String _campusId;

  @override
  void initState() {
    super.initState();
    final campuses = _campuses;
    _campusId =
        campuses.contains(widget.activeCampusId)
            ? widget.activeCampusId
            : campuses.firstOrNull ?? '';
  }

  /// 目录里出现过的校区，按首次出现顺序。
  List<String> get _campuses {
    final seen = <String>{};
    return <String>[
      for (final area in widget.areas)
        if (seen.add(area.campusId)) area.campusId,
    ];
  }

  List<ChargingPileArea> get _areasInCampus =>
      widget.areas.where((area) => area.campusId == _campusId).toList();

  void _pick(ChargingPileArea? area) {
    Navigator.of(context).pop(
      ChargingPileAreaSelection(campusId: _campusId, area: area),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('选择校区与分区', style: theme.textTheme.titleMedium),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final campusId in _campuses) ...[
                    ChoiceChip(
                      label: Text(
                        campusId.isEmpty
                            ? '未归属校区'
                            : widget.campusLabel(campusId),
                      ),
                      selected: campusId == _campusId,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _campusId = campusId),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  _PickerRow(
                    label: '全部分区',
                    selected:
                        widget.activeArea == null &&
                        _campusId == widget.activeCampusId,
                    onTap: () => _pick(null),
                  ),
                  for (final area in _areasInCampus)
                    _PickerRow(
                      label: area.label,
                      selected: area == widget.activeArea,
                      onTap: () => _pick(area),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(
        label,
        style:
            selected
                ? theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                )
                : theme.textTheme.bodyLarge,
      ),
      trailing:
          selected
              ? Icon(Icons.check, size: 20, color: theme.colorScheme.primary)
              : null,
      onTap: onTap,
    );
  }
}
