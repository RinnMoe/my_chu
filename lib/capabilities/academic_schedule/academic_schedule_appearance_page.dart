import 'package:flutter/material.dart';
import '../../widgets/appearance_color_dialog.dart';
import '../../services/theme_service.dart';
import '../../theme/app_palette.dart';
import '../../widgets/apple_window_controls.dart';
import '../../widgets/setting_reset_region.dart';

import 'academic_schedule_appearance.dart';
import 'academic_schedule_background_store.dart';
import 'academic_schedule_cell_colors.dart';
import 'academic_schedule_style.dart';
import 'academic_schedule_appearance_preview.dart';

/// A local, live appearance editor. Changes never touch course data.
class AcademicScheduleAppearancePage extends StatefulWidget {
  const AcademicScheduleAppearancePage({
    super.key,
    required this.initial,
    required this.themeSettings,
    required this.onSave,
    this.pickBackgroundImage = AcademicScheduleBackgroundStore.pick,
    this.showNonCurrent = true,
    this.showSaturday = true,
    this.showSunday = true,
  });

  final Future<String?> Function() pickBackgroundImage;
  final AcademicScheduleAppearance initial;
  final Widget themeSettings;
  final bool showNonCurrent, showSaturday, showSunday;
  final Future<void> Function(AcademicScheduleAppearance) onSave;

  @override
  State<AcademicScheduleAppearancePage> createState() =>
      _AcademicScheduleAppearancePageState();
}

class _AcademicScheduleAppearancePageState
    extends State<AcademicScheduleAppearancePage> {
  late AcademicScheduleAppearance _appearance = widget.initial;
  int _section = 0;
  bool? _previewDark;
  bool _saving = false;
  AcademicScheduleAppearance? _draft;

  Future<bool> _save(AcademicScheduleAppearance next) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await widget.onSave(next);
      if (mounted) setState(() => _appearance = next);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('外观保存失败，请重试')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetStyle(String id) async {
    const fields = {
      'schedule-grid': 'showGrid',
      'schedule-period-time': 'showPeriodTime',
      'schedule-saturday': 'showSaturday',
      'schedule-sunday': 'showSunday',
      'schedule-noncurrent': 'showNonCurrent',
      'schedule-text-tint': 'tintCourseText',
      'schedule-border-course': 'borderUsesCourseColor',
      'schedule-header-size': 'headerFontSize',
      'schedule-cell-height': 'cellHeight',
      'schedule-cell-radius': 'cornerRadius',
      'schedule-cell-opacity': 'cellOpacity',
      'schedule-noncurrent-opacity': 'nonCurrentOpacity',
      'schedule-course-size': 'courseFontSize',
    };
    await _save(_appearance.withStyle(_appearance.style.reset(fields[id]!)));
  }

  bool _pickingBackground = false;

  Future<void> _background(bool dark) async {
    if (_saving || _pickingBackground) return;
    final type = await showDialog<bool>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: const Text('课表背景'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('图片背景'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('纯色背景'),
              ),
            ],
          ),
    );
    if (!mounted || type == null) return;
    if (!type) {
      await _editColor(null, dark);
      return;
    }
    setState(() => _pickingBackground = true);
    try {
      final image = await widget.pickBackgroundImage();
      if (image == null) return;
      if (!mounted) {
        await AcademicScheduleAppearanceStore.discardUnusedBackground(image);
        return;
      }
      if (!await _save(_appearance.withBackgroundImage(image, dark))) {
        await AcademicScheduleAppearanceStore.discardUnusedBackground(image);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片无法使用，请选择 20 MB 以内的图片')));
      }
    } finally {
      if (mounted) setState(() => _pickingBackground = false);
    }
  }

  Future<void> _resetBackground(bool dark) async {
    if (_pickingBackground) return;
    if (await _save(_appearance.withBackground(null, dark)) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已恢复默认背景')));
    }
  }

  Future<void> _editColor(int? slot, bool dark, {ScheduleInk? role}) async {
    final scheme = resolveAppColorScheme(
      dark ? Brightness.dark : Brightness.light,
      seedColor: themePreferencesNotifier.value.seedColor,
      pureBlack: themePreferencesNotifier.value.pureBlackEnabled,
    );
    final background =
        role != null
            ? _appearance.style.ink(role, dark) ?? scheme.onSurface
            : slot == null
            ? (dark
                    ? _appearance.darkBackground
                    : _appearance.lightBackground) ??
                scheme.surface
            : academicScheduleCellColors(
              slot,
              dark: dark,
              appearance: _appearance,
            ).background;
    AcademicScheduleAppearance update(Color color) =>
        role != null
            ? _appearance.withStyle(
              _appearance.style.withInk(role, color, dark),
            )
            : slot == null
            ? _appearance.withBackground(color, dark)
            : _appearance.withColor(slot, color, dark);
    final color = await showDialog<Color>(
      context: context,
      builder:
          (context) => AppearanceColorDialog(
            initial: background,
            allowAlpha: role != null,
            onChanged: (color) {
              if (mounted) setState(() => _draft = update(color));
            },
          ),
    );
    if (!mounted) return;
    setState(() => _draft = null);
    if (color != null) await _save(update(color));
  }

  Future<void> _number(
    String title,
    double value,
    double min,
    double max,
    int divisions,
    String unit,
    AcademicScheduleStyle Function(double) update,
  ) async {
    var current = value;
    final result = await showModalBottomSheet<double>(
      context: context,
      barrierColor: Colors.transparent,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setSheetState) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              '${(unit == '%' ? current * 100 : current).round()} $unit',
                            ),
                          ],
                        ),
                        Slider(
                          value: current,
                          min: min,
                          max: max,
                          divisions: divisions,
                          onChanged: (value) {
                            setSheetState(() => current = value);
                            setState(
                              () =>
                                  _draft = _appearance.withStyle(update(value)),
                            );
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, current),
                              child: const Text('应用'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
    if (!mounted) return;
    setState(() => _draft = null);
    if (result != null) await _save(_appearance.withStyle(update(result)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = _previewDark ?? scheme.brightness == Brightness.dark;
    final previewScheme = resolveAppColorScheme(
      dark ? Brightness.dark : Brightness.light,
      seedColor: themePreferencesNotifier.value.seedColor,
      pureBlack: themePreferencesNotifier.value.pureBlackEnabled,
    );
    final appearance = _draft ?? _appearance;
    final style = appearance.style;
    Widget group(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.labelLarge),
          ),
          Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
    Widget toggle(
      String id,
      String title,
      bool value,
      AcademicScheduleStyle Function(bool) update,
    ) => SettingResetRegion(
      onReset: () => _resetStyle(id),
      child: SwitchListTile(
        key: ValueKey(id),
        title: Text(title),
        value: value,
        onChanged: (value) => _save(_appearance.withStyle(update(value))),
      ),
    );
    Widget number(
      String id,
      String title,
      double value,
      double min,
      double max,
      int divisions,
      String unit,
      AcademicScheduleStyle Function(double) update,
    ) => ListTile(
      key: ValueKey(id),
      title: Text(title),
      trailing: Text('${(unit == '%' ? value * 100 : value).round()} $unit'),
      onTap: () => _number(title, value, min, max, divisions, unit, update),
      onLongPress: () => _resetStyle(id),
    );
    Widget ink(String title, ScheduleInk role) {
      final color = style.ink(role, dark);
      return ListTile(
        key: ValueKey('schedule-ink-${role.name}'),
        title: Text(title),
        trailing: Icon(Icons.circle, color: color ?? scheme.onSurfaceVariant),
        onTap: () => _editColor(null, dark, role: role),
        onLongPress:
            () => _save(_appearance.withStyle(style.withInk(role, null, dark))),
      );
    }

    final settings = AbsorbPointer(
      absorbing: _saving || _pickingBackground,
      child: SingleChildScrollView(
        primary: false,
        key: const ValueKey('schedule-appearance-settings'),
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 230,
              child: AcademicScheduleAppearancePreview(
                appearance: appearance,
                dark: dark,
                showSaturday: widget.showSaturday,
                showSunday: widget.showSunday,
                showNonCurrent: widget.showNonCurrent,
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
            group('课程配色', [
              for (final palette in AcademicSchedulePalette.values)
                ListTile(
                  key: ValueKey('schedule-preset-${palette.id}'),
                  title: Text(palette.label),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _PaletteStrip(palette: palette, dark: dark),
                  ),
                  selected:
                      appearance.palette == palette &&
                      appearance.lightColors.isEmpty &&
                      appearance.darkColors.isEmpty,
                  trailing:
                      appearance.palette == palette &&
                              appearance.lightColors.isEmpty &&
                              appearance.darkColors.isEmpty
                          ? const Icon(Icons.check)
                          : null,
                  onTap: () => _save(_appearance.withPalette(palette)),
                  onLongPress:
                      () => _save(
                        _appearance.withPalette(
                          AcademicSchedulePalette.classic,
                        ),
                      ),
                ),
              SettingResetRegion(
                onReset:
                    () => _save(
                      _appearance.withPalette(AcademicSchedulePalette.classic),
                    ),
                child: ExpansionTile(
                  key: const ValueKey('schedule-custom-palette'),
                  title: const Text('自定义配色'),
                  trailing:
                      appearance.lightColors.isNotEmpty ||
                              appearance.darkColors.isNotEmpty
                          ? const Icon(Icons.check)
                          : null,
                  childrenPadding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (
                          var i = 0;
                          i < academicScheduleCellPalettes.length;
                          i++
                        )
                          _ColorSlot(
                            index: i,
                            colors: academicScheduleCellColors(
                              i,
                              dark: dark,
                              appearance: appearance,
                            ),
                            onTap: () => _editColor(i, dark),
                            onReset:
                                () => _save(_appearance.withoutColor(i, dark)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
            group('背景与显示', [
              ListTile(
                key: const ValueKey('schedule-background'),
                title: const Text('课表背景'),
                subtitle:
                    _pickingBackground
                        ? const Text('正在处理图片…')
                        : appearance.backgroundImage(dark) != null
                        ? const Text('图片背景')
                        : null,
                trailing: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: appearance.canvas(previewScheme),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
                onTap: () => _background(dark),
                onLongPress: () => _resetBackground(dark),
              ),
              toggle(
                'schedule-grid',
                '显示网格线',
                style.showGrid,
                (v) => style.copyWith(showGrid: v),
              ),
              ink('界面文字颜色', ScheduleInk.axis),
              number(
                'schedule-header-size',
                '表头字号',
                style.headerFontSize,
                9,
                18,
                9,
                'sp',
                (v) => style.copyWith(headerFontSize: v),
              ),
              toggle(
                'schedule-period-time',
                '节次栏显示时间',
                style.showPeriodTime,
                (v) => style.copyWith(showPeriodTime: v),
              ),
              toggle(
                'schedule-saturday',
                '显示周六',
                style.showSaturday ?? widget.showSaturday,
                (v) => style.copyWith(showSaturday: v),
              ),
              toggle(
                'schedule-sunday',
                '显示周日',
                style.showSunday ?? widget.showSunday,
                (v) => style.copyWith(showSunday: v),
              ),
              toggle(
                'schedule-noncurrent',
                '显示非本周课程',
                style.showNonCurrent ?? widget.showNonCurrent,
                (v) => style.copyWith(showNonCurrent: v),
              ),
            ]),
            group('课程样式', [
              ink('课程文字颜色', ScheduleInk.course),
              toggle(
                'schedule-text-tint',
                '文字叠加格子颜色',
                style.tintCourseText,
                (v) => style.copyWith(tintCourseText: v),
              ),
              toggle(
                'schedule-border-course',
                '边框跟随课程颜色',
                style.borderUsesCourseColor,
                (v) => style.copyWith(borderUsesCourseColor: v),
              ),
              if (!style.borderUsesCourseColor)
                ink('格子边框颜色', ScheduleInk.border),
              number(
                'schedule-cell-height',
                '格子高度',
                style.cellHeight,
                40,
                100,
                60,
                'dp',
                (v) => style.copyWith(cellHeight: v),
              ),
              number(
                'schedule-cell-radius',
                '圆角',
                style.cornerRadius,
                0,
                20,
                20,
                'dp',
                (v) => style.copyWith(cornerRadius: v),
              ),
              number(
                'schedule-cell-opacity',
                '格子不透明度',
                style.cellOpacity,
                0,
                1,
                100,
                '%',
                (v) => style.copyWith(cellOpacity: v),
              ),
              number(
                'schedule-noncurrent-opacity',
                '非本周不透明比',
                style.nonCurrentOpacity,
                0,
                1,
                100,
                '%',
                (v) => style.copyWith(nonCurrentOpacity: v),
              ),
              number(
                'schedule-course-size',
                '课程字号',
                style.courseFontSize,
                9,
                18,
                9,
                'sp',
                (v) => style.copyWith(courseFontSize: v),
              ),
            ]),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('外观与主题'),
          actions: [
            IconButton(
              key: const ValueKey('appearance-help'),
              tooltip: '帮助',
              icon: const Icon(Icons.help_outline),
              onPressed:
                  () => showDialog<void>(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('设置帮助'),
                          content: const Text('长按任一设置项可恢复默认，不影响其他设置。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('知道了'),
                            ),
                          ],
                        ),
                  ),
            ),
            if (_section == 1)
              IconButton(
                tooltip: '切换预览明暗',
                icon: Icon(
                  dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                ),
                onPressed: () => setState(() => _previewDark = !dark),
              ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('应用主题')),
                        ButtonSegment(value: 1, label: Text('课表外观')),
                      ],
                      selected: {_section},
                      onSelectionChanged:
                          (selection) =>
                              setState(() => _section = selection.single),
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    key: const ValueKey('appearance-content-viewport'),
                    child: Material(
                      color: scheme.surface,
                      child: IndexedStack(
                        index: _section,
                        children: [
                          SingleChildScrollView(
                            key: const PageStorageKey('app-theme-settings'),
                            primary: false,
                            padding: const EdgeInsets.only(bottom: 24),
                            child: widget.themeSettings,
                          ),
                          settings,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteStrip extends StatelessWidget {
  const _PaletteStrip({required this.palette, required this.dark});
  final AcademicSchedulePalette palette;
  final bool dark;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 8; i++)
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 3),
            height: 12,
            decoration: BoxDecoration(
              color:
                  academicScheduleCellColors(
                    i,
                    dark: dark,
                    appearance: AcademicScheduleAppearance(palette: palette),
                  ).background,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
    ],
  );
}

class _ColorSlot extends StatelessWidget {
  const _ColorSlot({
    required this.index,
    required this.colors,
    required this.onTap,
    required this.onReset,
  });
  final int index;
  final AcademicScheduleCellColors colors;
  final VoidCallback onTap, onReset;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '修改第${index + 1}种课程颜色',
    button: true,
    child: Material(
      color: colors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onReset,
        child: const SizedBox(width: 52, height: 48),
      ),
    ),
  );
}
