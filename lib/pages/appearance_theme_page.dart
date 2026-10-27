import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/appearance_color_dialog.dart';

import '../capabilities/academic_schedule/academic_schedule_appearance.dart';
import '../capabilities/academic_schedule/academic_schedule_appearance_page.dart';
import '../capabilities/academic_schedule/academic_schedule_store.dart';
import '../services/theme_service.dart';
import '../theme/app_palette.dart';
import '../widgets/apple_window_controls.dart';
import '../widgets/setting_reset_region.dart';

/// Appearance settings opened from Profile.
class AppearanceThemePage extends StatefulWidget {
  const AppearanceThemePage({super.key});

  @override
  State<AppearanceThemePage> createState() => _AppearanceThemePageState();
}

class _AppearanceThemePageState extends State<AppearanceThemePage> {
  late final Future<Widget> editor = _editor();

  Future<Widget> _editor() async {
    final appearance = await AcademicScheduleAppearanceStore.read();
    final nonCurrent =
        await AcademicScheduleDisplayPreferences.readShowNonCurrent();
    final hideWeekend =
        await AcademicScheduleDisplayPreferences.readHideWeekend();
    return AcademicScheduleAppearancePage(
      initial: appearance,
      showNonCurrent: nonCurrent,
      showSaturday: !hideWeekend,
      showSunday: !hideWeekend,
      onSave: AcademicScheduleAppearanceStore.save,
      themeSettings: const _ThemeSettings(),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: editor,
    builder: (context, snapshot) {
      if (snapshot.hasData) return snapshot.data!;
      return Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(title: const Text('外观与主题')),
        ),
        body:
            snapshot.hasError
                ? Center(
                  child: TextButton(
                    onPressed:
                        () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const AppearanceThemePage(),
                          ),
                        ),
                    child: const Text('加载失败，重试'),
                  ),
                )
                : const Center(child: CircularProgressIndicator()),
      );
    },
  );
}

class _ThemeSettings extends StatelessWidget {
  const _ThemeSettings();
  Future<void> _change(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('主题保存失败，请重试')));
      }
    }
  }

  Future<void> _custom(BuildContext context, Color initial) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => AppearanceColorDialog(initial: initial),
    );
    if (result != null && context.mounted) {
      await _change(
        context,
        () => themePreferencesNotifier.setSeedColor(result),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<ThemePreferences>(
    valueListenable: themePreferencesNotifier,
    builder: (context, preferences, _) {
      final scheme = Theme.of(context).colorScheme;
      final seed = preferences.seedColor ?? AppBrand.seed;
      Widget heading(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
      Widget card(String title, Color color, {bool custom = false}) {
        final selected =
            !preferences.useDynamicColors &&
            (custom ? seed != AppBrand.seed : seed == color);
        final preview = resolveAppColorScheme(
          scheme.brightness,
          seedColor: color,
        );
        return Semantics(
          selected: selected,
          child: Material(
            color:
                selected
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onLongPress:
                  () => _change(
                    context,
                    () => themePreferencesNotifier.setSeedColor(AppBrand.seed),
                  ),
              onTap:
                  () =>
                      custom
                          ? _custom(context, seed)
                          : _change(
                            context,
                            () => themePreferencesNotifier.setSeedColor(color),
                          ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (final swatch in [
                          preview.primaryContainer,
                          preview.secondaryContainer,
                          preview.tertiaryContainer,
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              width: 26,
                              height: 28,
                              decoration: BoxDecoration(
                                color: swatch,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Text(title)),
                        SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              selected
                                  ? const Icon(Icons.check, size: 20)
                                  : custom
                                  ? const Icon(Icons.add, size: 20)
                                  : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('明暗模式'),
            Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SettingResetRegion(
                      onReset:
                          () => _change(
                            context,
                            () => themePreferencesNotifier.setMode(
                              AppThemeMode.system,
                            ),
                          ),
                      child: SegmentedButton<AppThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: AppThemeMode.system,
                            label: Text('自动'),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.light,
                            label: Text('浅色'),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.dark,
                            label: Text('深色'),
                          ),
                        ],
                        selected: {preferences.mode},
                        onSelectionChanged:
                            (selection) => _change(
                              context,
                              () => themePreferencesNotifier.setMode(
                                selection.single,
                              ),
                            ),
                      ),
                    ),
                  ),
                  SettingResetRegion(
                    onReset:
                        () => _change(
                          context,
                          () => themePreferencesNotifier.setPureBlackEnabled(
                            false,
                          ),
                        ),
                    child: SwitchListTile(
                      key: const ValueKey('pure-black-setting'),
                      title: const Text('深色纯黑背景'),
                      subtitle: const Text('适用于 OLED 屏幕'),
                      value: preferences.pureBlackEnabled,
                      onChanged:
                          (enabled) => _change(
                            context,
                            () => themePreferencesNotifier.setPureBlackEnabled(
                              enabled,
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
            heading('主题色彩'),
            if (preferences.dynamicColorSupported) ...[
              Material(
                color:
                    preferences.useDynamicColors
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: const ValueKey('wallpaper-dynamic-color'),
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: const Text('跟随壁纸配色'),
                  selected: preferences.useDynamicColors,
                  trailing:
                      preferences.useDynamicColors
                          ? const Icon(Icons.check)
                          : null,
                  onLongPress:
                      () => _change(
                        context,
                        () => themePreferencesNotifier.setSeedColor(
                          AppBrand.seed,
                        ),
                      ),
                  onTap:
                      () => _change(
                        context,
                        () => themePreferencesNotifier.setDynamicColorEnabled(
                          true,
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(width: width, child: card('霓裳蓝', AppBrand.seed)),
                    SizedBox(
                      width: width,
                      child: card('自定义', seed, custom: true),
                    ),
                  ],
                );
              },
            ),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
              heading('交互'),
              Material(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: SettingResetRegion(
                  onReset:
                      () => _change(
                        context,
                        () => themePreferencesNotifier.setPredictiveBackEnabled(
                          true,
                        ),
                      ),
                  child: SwitchListTile(
                    key: const ValueKey('predictive-back-animation-setting'),

                    title: const Text('返回手势动画'),
                    subtitle: const Text('部分系统可能不支持'),
                    value: preferences.predictiveBackEnabled,
                    onChanged:
                        (enabled) => _change(
                          context,
                          () => themePreferencesNotifier
                              .setPredictiveBackEnabled(enabled),
                        ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
