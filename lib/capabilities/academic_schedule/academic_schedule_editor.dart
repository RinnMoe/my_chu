import 'package:flutter/material.dart';

import '../../apps/academic_affairs/academic_affairs_models.dart';
import '../../widgets/adaptive_confirmation_dialog.dart';

typedef AcademicScheduleEditorSave =
    Future<bool> Function(AcademicPersonalScheduleEntry entry);
typedef AcademicScheduleEditorDelete = Future<bool> Function();

/// Compact editor used from the timetable detail sheet and the app-bar
/// “添加课程” action.  Persistence and conflict policy stay with the page so
/// this widget remains usable with a fake store in tests.
class AcademicScheduleEditor extends StatefulWidget {
  final AcademicPersonalScheduleEntry? initialEntry;
  final int maxWeek;
  final AcademicScheduleEditorSave onSave;
  final AcademicScheduleEditorDelete? onDelete;

  const AcademicScheduleEditor({
    super.key,
    this.initialEntry,
    required this.maxWeek,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<AcademicScheduleEditor> createState() => _AcademicScheduleEditorState();
}

class _AcademicScheduleEditorState extends State<AcademicScheduleEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _teacherController;
  late final TextEditingController _locationController;
  late final TextEditingController _weeksController;
  late int _weekday;
  late int _startPeriod;
  late int _endPeriod;
  bool _working = false;

  AcademicPersonalScheduleEntry? get _initial => widget.initialEntry;

  @override
  void initState() {
    super.initState();
    final entry = _initial;
    _nameController = TextEditingController(text: entry?.courseName ?? '');
    _teacherController = TextEditingController(text: entry?.teacher ?? '');
    _locationController = TextEditingController(text: entry?.location ?? '');
    _weeksController = TextEditingController(
      text: entry == null ? '' : _normalizedWeeksText(entry.weeks),
    );
    _weekday = entry?.weekday.clamp(1, 7) ?? 1;
    _startPeriod = entry?.startPeriod.clamp(1, 11) ?? 1;
    _endPeriod = entry?.endPeriod.clamp(1, 11) ?? _startPeriod;
    if (_endPeriod < _startPeriod) _endPeriod = _startPeriod;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _locationController.dispose();
    _weeksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    final isNew = _initial == null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isNew ? '添加课程' : '编辑课程',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (!isNew && widget.onDelete != null)
                    IconButton(
                      tooltip: '删除课程',
                      onPressed: _working ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '课程名',
                  hintText: '例如 高等数学',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teacherController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '教师',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _locationController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '地点',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(
                  labelText: '星期',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var day = 1; day <= 7; day++)
                    DropdownMenuItem(
                      value: day,
                      child: Text('星期${_weekdayLabel(day)}'),
                    ),
                ],
                onChanged:
                    _working
                        ? null
                        : (value) => setState(() => _weekday = value ?? 1),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _periodDropdown('开始节次', _startPeriod, (value) {
                      setState(() {
                        _startPeriod = value;
                        if (_endPeriod < value) _endPeriod = value;
                      });
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _periodDropdown('结束节次', _endPeriod, (value) {
                      setState(() => _endPeriod = value);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _weeksController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: '周次',
                  hintText: '例如 1-8,10；留空表示每周',
                  helperText: '支持 1-8、1,3,5；本学期最多 ${widget.maxWeek} 周',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _working ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(isNew ? '添加到课表' : '保存修改'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodDropdown(String label, int value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (var period = 1; period <= 11; period++)
          DropdownMenuItem(value: period, child: Text('第$period节')),
      ],
      onChanged:
          _working
              ? null
              : (next) {
                if (next != null) onChanged(next);
              },
    );
  }

  Future<void> _save() async {
    final courseName = _nameController.text.trim();
    if (courseName.isEmpty) {
      await _showMessage('请填写课程名');
      return;
    }
    final weeks = _parseWeeks(_weeksController.text, widget.maxWeek);
    if (weeks == null) {
      await _showMessage('周次格式不正确，请使用 1-8 或 1,3,5');
      return;
    }
    if (_startPeriod > _endPeriod) {
      await _showMessage('结束节次不能早于开始节次');
      return;
    }
    setState(() => _working = true);
    try {
      final entry = (_initial ??
              AcademicPersonalScheduleEntry(
                courseSequence:
                    'local-${DateTime.now().microsecondsSinceEpoch}',
                courseCode: '',
                courseName: courseName,
                teacher: '',
                location: '',
                weekday: _weekday,
                startPeriod: _startPeriod,
                endPeriod: _endPeriod,
                weeksText: '',
                weeks: const [],
                practiceWeeks: const [],
              ))
          .copyWith(
            courseName: courseName,
            teacher: _teacherController.text.trim(),
            location: _locationController.text.trim(),
            weekday: _weekday,
            startPeriod: _startPeriod,
            endPeriod: _endPeriod,
            weeksText: _normalizedWeeksText(weeks),
            weeks: weeks,
          );
      final saved = await widget.onSave(entry);
      if (saved && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showAdaptiveConfirmationDialog(
      context,
      title: '删除这门课程？',
      message: '删除只影响你的个人课表，之后可以通过恢复原始课表找回远程课程。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true || widget.onDelete == null) return;
    setState(() => _working = true);
    try {
      final deleted = await widget.onDelete!();
      if (deleted && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    return Future<void>.value();
  }

  static List<int>? _parseWeeks(String raw, int maxWeek) {
    final text = raw.trim();
    if (text.isEmpty) return <int>[];
    final normalized = text
        .replaceAll('周', '')
        .replaceAll('，', ',')
        .replaceAll('、', ',')
        .replaceAll('；', ',')
        .replaceAll(';', ',')
        .replaceAll('～', '-')
        .replaceAll('~', '-');
    final values = <int>{};
    for (final part in normalized.split(',')) {
      final item = part.trim();
      if (item.isEmpty) continue;
      final range = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(item);
      if (range != null) {
        final begin = int.parse(range.group(1)!);
        final end = int.parse(range.group(2)!);
        if (begin < 1 || end < begin || end > maxWeek) return null;
        for (var week = begin; week <= end; week++) {
          values.add(week);
        }
      } else {
        final week = int.tryParse(item);
        if (week == null || week < 1 || week > maxWeek) return null;
        values.add(week);
      }
    }
    final result = values.toList()..sort();
    return result;
  }

  static String _normalizedWeeksText(List<int> weeks) {
    if (weeks.isEmpty) return '';
    final ranges = <String>[];
    var start = weeks.first;
    var previous = start;
    for (final week in weeks.skip(1)) {
      if (week == previous + 1) {
        previous = week;
        continue;
      }
      ranges.add(start == previous ? '$start' : '$start-$previous');
      start = previous = week;
    }
    ranges.add(start == previous ? '$start' : '$start-$previous');
    return ranges.join(',');
  }

  static String _weekdayLabel(int weekday) =>
      const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];
}
