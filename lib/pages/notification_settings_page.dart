import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../capabilities/time_reminder_registry.dart';
import '../services/time_reminder_service.dart';
import '../services/host_permission_service.dart';
import '../services/platform_compatibility_service.dart';
import '../widgets/apple_window_controls.dart';
import 'host_permission_purpose_overlay.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  Map<TimeReminderCategory, TimeReminderSetting>? _settings;
  TimeReminderStatus _status = const TimeReminderStatus();
  bool _busy = false;
  bool _error = false;
  @override
  void initState() {
    super.initState();
    registerTimeReminders();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      if (refresh) await TimeReminderService.refreshAll();
      final settings = await TimeReminderService.settings();
      final status = await TimeReminderService.status();
      if (mounted) {
        setState(() {
          _settings = settings;
          _status = status;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _change(
    TimeReminderCategory category,
    TimeReminderSetting setting,
  ) async {
    setState(() => _busy = true);
    try {
      await TimeReminderService.updateSetting(category, setting);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存提醒设置失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(
    TimeReminderCategory category,
    TimeReminderSetting setting,
  ) async {
    var input = '${setting.advance}';
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<int>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('提前多久提醒？'),
            content: Form(
              key: formKey,
              child: TextFormField(
                initialValue: input,
                onChanged: (value) => input = value,
                autofocus: true,
                validator: (input) {
                  final value = int.tryParse(input ?? '');
                  if (value == null ||
                      value < category.minLead ||
                      value > category.maxLead) {
                    return '请输入 ${category.minLead}–${category.maxLead} 之间的数值';
                  }
                  return null;
                },
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  suffixText: category.unit,
                  helperText:
                      '${category.minLead}–${category.maxLead} ${category.unit}',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(context, int.parse(input));
                  }
                },
                child: const Text('保存'),
              ),
            ],
          ),
    );
    if (value != null && mounted) {
      await _change(
        category,
        TimeReminderSetting(enabled: setting.enabled, advance: value),
      );
    }
  }

  Future<void> _notificationPermission() async {
    final granted = await hostPermissionService.requestNotificationPermission(
      presentPurpose:
          (purpose) => presentHostPermissionPurpose(context, purpose),
    );
    if (!granted.granted) await openAppSettings();
    await _load(refresh: true);
  }

  Future<void> _exactPermission() async {
    await PlatformCompatibilityService.openExactAlarmSettings();
    if (mounted) await _load(refresh: true);
  }

  Widget _permissionNotice(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final supported = _status.supported;
    final notificationsMissing = !_status.notifications;
    final title =
        !supported
            ? '此设备暂不支持提醒'
            : notificationsMissing
            ? '通知权限未开启'
            : '允许按时提醒';
    final message =
        !supported
            ? '时间提醒目前支持 Android、iPhone 和 iPad。'
            : notificationsMissing
            ? '开启通知权限，才能收到课程、考试和待办提醒。'
            : '请在系统设置中允许“闹钟和提醒”，以便在设定时间提醒你。';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.notifications_off_outlined,
                color: colors.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                    if (supported) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed:
                            _busy
                                ? null
                                : notificationsMissing
                                ? _notificationPermission
                                : _exactPermission,
                        child: const Text('去开启'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reminderGroup(BuildContext context, TimeReminderCategory category) {
    final setting = _settings![category]!;
    final colors = Theme.of(context).colorScheme;
    final editable = !_busy && _status.supported;
    final (icon, description) = switch (category) {
      TimeReminderCategory.course => (Icons.school_outlined, '提醒上课时间和教室'),
      TimeReminderCategory.exam => (Icons.edit_calendar_outlined, '提前提醒，安心备考'),
      TimeReminderCategory.deadline => (
        Icons.task_alt_outlined,
        '提醒有截止时间的未完成待办',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SwitchListTile(
              key: ValueKey('reminder-switch-${category.name}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              secondary: Icon(icon, color: colors.primary),
              title: Text(category.label),
              subtitle: Text(description),
              value: setting.enabled,
              onChanged:
                  !editable
                      ? null
                      : (value) => _change(
                        category,
                        TimeReminderSetting(
                          enabled: value,
                          advance: setting.advance,
                        ),
                      ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            ListTile(
              key: ValueKey('reminder-advance-${category.name}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
              enabled: editable && setting.enabled,
              title: const Text('提前时间'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${setting.advance} ${category.unit}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color:
                          setting.enabled && editable
                              ? colors.primary
                              : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              onTap:
                  editable && setting.enabled
                      ? () => _advance(category, setting)
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('时间提醒')),
      ),
      body:
          _error
              ? Center(
                child: TextButton(
                  onPressed: _load,
                  child: const Text('加载失败，点击重试'),
                ),
              )
              : _settings == null
              ? const Center(child: CircularProgressIndicator())
              : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      if (!_status.ready) _permissionNotice(context),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          '提醒事项',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      for (final category in TimeReminderCategory.values)
                        _reminderGroup(context, category),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Text(
                          '定期打开应用，保持提醒更新。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
