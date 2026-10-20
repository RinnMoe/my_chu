import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../capabilities/time_reminder_registry.dart';
import '../services/course_live_activity_service.dart';
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

  /// Course live activity is an independent feature: its state is loaded and
  /// reported separately so a failure here can never hide the reminder groups.
  bool? _liveEnabled;
  bool _liveSupported = false;
  bool _liveBusy = false;
  bool _liveError = false;
  int _liveLoadToken = 0;
  CourseLiveActivityStatus _liveStatus = const CourseLiveActivityStatus();

  @override
  void initState() {
    super.initState();
    registerTimeReminders();
    WidgetsBinding.instance.addObserver(this);
    CourseLiveActivityService.revision.addListener(_onLiveActivityRevision);
    _load();
  }

  @override
  void dispose() {
    CourseLiveActivityService.revision.removeListener(_onLiveActivityRevision);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The service bumps its revision whenever the switch or the projected plan
  /// changes, so the page never has to poll.
  void _onLiveActivityRevision() {
    if (mounted) _loadLiveActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(refresh: true);
  }

  /// The two features are independent: each half publishes its own state, so
  /// neither one can delay, hide or fail the other.
  Future<void> _load({bool refresh = false}) => Future.wait([
    _loadLiveActivity(),
    _loadReminders(refresh: refresh),
  ]);

  Future<void> _loadReminders({required bool refresh}) async {
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

  /// Reads the switch, the device capability snapshot and the channel actually
  /// in use. Only the most recently started read may publish its result, so a
  /// stale value can never overwrite a newer one.
  Future<void> _loadLiveActivity() async {
    final token = ++_liveLoadToken;
    try {
      final supported = CourseLiveActivityService.isSupported;
      final enabled = await CourseLiveActivityService.isEnabled();
      final status = await CourseLiveActivityService.status();
      if (!mounted || token != _liveLoadToken) return;
      setState(() {
        _liveSupported = supported;
        _liveEnabled = enabled;
        _liveStatus = status;
        _liveError = false;
      });
    } catch (_) {
      if (mounted && token == _liveLoadToken) {
        setState(() => _liveError = true);
      }
    }
  }

  Future<void> _toggleLiveActivity(bool enabled) async {
    setState(() => _liveBusy = true);
    try {
      await CourseLiveActivityService.updateEnabled(enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('课程实时动态保存失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _liveBusy = false);
    }
    // Always read back the persisted value: the switch must never show a state
    // the service did not actually save.
    await _loadLiveActivity();
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
    if (mounted) await _load();
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

  /// Reports the observed Android result, not a requested or assumed promotion.
  Widget _liveChannelRow(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = _liveEnabled != false && _liveSupported && _liveStatus.notifications;
    final code = !enabled ? 'none' : _liveStatus.promoted ? 'promoted' : 'standardNotification';
    final label = _liveEnabled == false ? '已关闭' : !enabled ? '不可用'
        : _liveStatus.promoted ? 'Android 实时动态' : '系统持续通知（未晋升）';
    return Row(
      key: const ValueKey('course-live-activity-channel'),
      children: [
        Icon(Icons.campaign_outlined, size: 18, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text('当前状态：$label',
          key: ValueKey('course-live-activity-channel-$code'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
      ],
    );
  }

  Widget _liveNotice(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    Future<void> Function()? onAction,
    bool blocking = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final background =
        blocking ? colors.secondaryContainer : colors.surfaceContainerHighest;
    final foreground =
        blocking ? colors.onSecondaryContainer : colors.onSurfaceVariant;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: foreground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: foreground),
                    ),
                    if (actionLabel != null && onAction != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _liveBusy ? null : () => onAction(),
                          style: TextButton.styleFrom(
                            foregroundColor: foreground,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: Text(actionLabel),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveActivityGroup(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final liveOn = _liveEnabled != false;
    final editable = _liveSupported && !_liveBusy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SwitchListTile(
              key: const ValueKey('course-live-activity-switch'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              secondary: Icon(
                Icons.notifications_active_outlined,
                color: colors.primary,
              ),
              title: const Text('课程实时动态'),
              subtitle: const Text('课前显示时间与教室，课中显示上课进度'),
              value: _liveEnabled ?? true,
              onChanged: editable ? _toggleLiveActivity : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _liveChannelRow(context),
                  if (!_liveSupported)
                    _liveNotice(
                      context,
                      key: const ValueKey('course-live-activity-unsupported'),
                      icon: Icons.phonelink_off_outlined,
                      title: '此设备暂不支持课程实时动态',
                      message: '课程实时动态目前只在 Android 设备上展示。',
                    ),
                  if (_liveSupported && liveOn && !_liveStatus.notifications)
                    _liveNotice(
                      context,
                      key: const ValueKey(
                        'course-live-activity-notification-note',
                      ),
                      icon: Icons.notifications_off_outlined,
                      title: '通知权限未开启',
                      message: '没有通知权限，课程实时动态不会出现，请先允许通知。',
                      actionLabel: '去开启',
                      onAction: _notificationPermission,
                      blocking: true,
                    ),
                  if (_liveSupported && liveOn && !_liveStatus.exact)
                    _liveNotice(
                      context,
                      key: const ValueKey('course-live-activity-exact-note'),
                      icon: Icons.alarm_off_outlined,
                      title: '精确闹钟权限未开启',
                      message: '后台预约会暂停，前台仍会展示当前课程；开启“闹钟和提醒”后可按时预约。',
                      actionLabel: '去开启',
                      onAction: _exactPermission,
                    ),
                  if (_liveError)
                    _liveNotice(
                      context,
                      key: const ValueKey('course-live-activity-error'),
                      icon: Icons.error_outline,
                      title: '课程实时动态状态读取失败',
                      message: '提醒设置仍可正常使用，可稍后重试。',
                      actionLabel: '重试',
                      onAction: _loadLiveActivity,
                    ),
                ],
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
              key: const ValueKey('course-live-activity-settings'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 4,
              ),
              enabled: _liveSupported,
              leading: Icon(
                Icons.settings_outlined,
                color: colors.onSurfaceVariant,
              ),
              title: const Text('系统设置'),
              subtitle: const Text('在系统设置中允许通知与精确闹钟'),
              trailing: Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              onTap: _liveSupported ? _openSystemSettings : null,
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
                      for (final category in TimeReminderCategory.values.where(
                        (category) => !PlatformCompatibilityService.isAndroid ||
                            category != TimeReminderCategory.course))
                        _reminderGroup(context, category),
                      _liveActivityGroup(context),
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
