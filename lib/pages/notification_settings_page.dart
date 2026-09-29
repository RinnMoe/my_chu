import 'package:flutter/material.dart';

import '../capabilities/alert_center.dart';
import '../capabilities/alert_models.dart';
import '../capabilities/alert_registry.dart';
import '../capabilities/live_update.dart';
import '../services/auth_service.dart';
import '../services/live_update_service.dart';
import '../services/local_notification_bridge.dart';
import '../services/platform_compatibility_service.dart';
import '../services/platform_environment.dart';
import '../services/scheduled_alert_service.dart';
import 'alert_visuals.dart';
import '../widgets/adaptive_action_sheet.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

/// 通知与提醒设置页：按来源分组展示提醒订阅与跨平台系统实时动态。
class NotificationSettingsPage extends StatefulWidget {
  final DeviceFamily? deviceFamilyOverride;

  const NotificationSettingsPage({super.key, this.deviceFamilyOverride});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  String _accountKey = 'anonymous';
  List<AlertProvider> _providers = const [];
  Map<String, AlertSubscription> _subscriptions = {};
  List<SystemLiveActivityDefinition> _liveUpdateDefinitions = const [];
  Map<String, bool> _liveUpdateEnabled = {};
  String? _selectedSource;
  bool _loading = true;
  bool _promotedSupported = false;
  bool _canPostPromotedNotifications = false;
  bool _exactAlarmRequested = false;
  bool _exactAlarmAuthorized = false;
  bool _exactAlarmSupported = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    ensureBuiltInAlertProvidersRegistered();
    WidgetsBinding.instance.addObserver(this);
    AlertSubscriptionStore.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlertSubscriptionStore.revision.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final account = await AuthService.getCurrentAccount();
    final accountKey = account?.accountKey ?? 'anonymous';
    final liveUpdateDefinitions = LiveUpdateService.definitions;
    final subscriptionsFuture = AlertSubscriptionStore.read(accountKey);
    final enabledIdsFuture = LiveUpdatePreferences.enabledDefinitionIds(
      accountKey,
      liveUpdateDefinitions.map((definition) => definition.id),
    );
    final liveUpdateStatusFuture = LiveUpdateService.platformStatus();
    final exactAlarmStatusFuture =
        PlatformCompatibilityService.exactAlarmStatus();

    final subscriptions = await subscriptionsFuture;
    final enabledIds = await enabledIdsFuture;
    final liveUpdateStatus = await liveUpdateStatusFuture;
    final exactAlarmStatus = await exactAlarmStatusFuture;
    if (exactAlarmStatus.requested) {
      await ScheduledAlertService.reschedule();
    }
    final liveUpdateEnabled = <String, bool>{
      for (final definition in liveUpdateDefinitions)
        definition.id: enabledIds.contains(definition.id),
    };
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _accountKey = accountKey;
      _providers = AlertCenterService.providers;
      _subscriptions = {
        for (final subscription in subscriptions)
          subscription.providerId: subscription,
      };
      _liveUpdateDefinitions = liveUpdateDefinitions;
      _liveUpdateEnabled = liveUpdateEnabled;
      if (_selectedSource == null ||
          !_providers.any((provider) => provider.source == _selectedSource)) {
        _selectedSource = _providers.isEmpty ? null : _providers.first.source;
      }
      _promotedSupported = liveUpdateStatus['promotedSupported'] == true;
      _canPostPromotedNotifications =
          liveUpdateStatus['canPostPromotedNotifications'] == true;
      _exactAlarmRequested = exactAlarmStatus.requested;
      _exactAlarmAuthorized = exactAlarmStatus.authorized;
      _exactAlarmSupported = exactAlarmStatus.supported;
      _loading = false;
    });
  }

  AlertSubscription _defaultFor(AlertProvider provider) {
    final subscription = provider.defaultSubscription();
    if (!PlatformCompatibilityService.isApple &&
        !PlatformCompatibilityService.isHarmony) {
      return subscription;
    }
    // Apple and Harmony settings must not present an unrequested notification
    // authorization as an already-enabled banner preference.
    return subscription.copyWith(systemBanner: false);
  }

  Future<AlertSubscription> _update(
    AlertProvider provider,
    AlertSubscription Function(AlertSubscription current) update,
  ) async {
    final current = _subscriptions[provider.id] ?? _defaultFor(provider);
    var next = update(current);
    if ((PlatformCompatibilityService.isApple ||
            PlatformCompatibilityService.isHarmony) &&
        next.enabled &&
        next.systemBanner &&
        !current.systemBanner) {
      // Apple never asks for notification permission during cold start. A
      // user enabling a system banner is an explicit, contextual request.
      final granted = await LocalNotificationBridge.requestPermission();
      next = next.copyWith(systemBanner: granted);
    }
    await AlertSubscriptionStore.upsert(_accountKey, next);
    if (!next.enabled || !next.systemBanner) {
      await AlertCenterService.clearScheduled(_accountKey, provider.id);
    } else {
      await AlertCenterService.refreshScheduled(_accountKey, provider.id);
    }
    if (!mounted) return next;
    setState(() => _subscriptions[provider.id] = next);
    return next;
  }

  Future<void> _setExactAlarmRequested(bool requested) async {
    try {
      await PlatformCompatibilityService.setExactAlarmRequested(requested);
    } finally {
      await _load();
    }
  }

  Future<void> _updateLiveUpdate(
    SystemLiveActivityDefinition definition,
    bool enabled,
  ) async {
    await LiveUpdatePreferences.setEnabled(_accountKey, definition.id, enabled);
    if (!mounted) return;
    setState(() => _liveUpdateEnabled[definition.id] = enabled);
    await LiveUpdateService.refreshIfEnabled();
  }

  Future<void> _openGroup(_ProviderGroup group) async {
    final page = _NotificationSourcePage(
      group: group,

      subscriptions: Map<String, AlertSubscription>.from(_subscriptions),
      defaultFor: _defaultFor,
      onUpdate: _update,
    );
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _buildProviderGroups(_providers);

    final environment = PlatformEnvironment.fromContext(
      context,
      deviceFamilyOverride: widget.deviceFamilyOverride,
    );
    if (!_loading &&
        environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded) {
      return _buildMaterialTabletScaffold(groups);
    }

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('通知与提醒')),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildMaterialBody(groups),
    );
  }

  Widget _buildMaterialBody(List<_ProviderGroup> groups) {
    final hasDeliverySettings =
        _exactAlarmSupported || _liveUpdateDefinitions.isNotEmpty;
    return ListView(
      key: const ValueKey('notification-settings-material-scroll'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const _PageIntro(
          title: '选择需要提醒的内容',
          description: '提醒默认开启，你可以按来源单独关闭，也可以调整提醒条件。',
        ),
        const SizedBox(height: 24),
        if (groups.isEmpty)
          const _EmptyAlertState()
        else ...[
          const _SettingsSectionHeader(title: '提醒来源', subtitle: '按来源查看和管理提醒内容'),
          const SizedBox(height: 8),
          _SettingsCard(
            key: const ValueKey('notification-source-list'),
            children: [
              for (final group in groups)
                _SourceSummaryRow(
                  rowKey: ValueKey('notification-source-${group.source}'),
                  group: group,
                  subscriptions: _subscriptions,
                  defaultFor: _defaultFor,
                  onTap: () => _openGroup(group),
                ),
            ],
          ),
        ],
        if (hasDeliverySettings) ...[
          const SizedBox(height: 24),
          const _SettingsSectionHeader(
            title: '送达方式',
            subtitle: '控制提醒送达时间和系统通知显示方式',
          ),
          const SizedBox(height: 8),
          _buildMaterialDeliveryCard(),
        ],
      ],
    );
  }

  Widget _buildMaterialTabletScaffold(List<_ProviderGroup> groups) {
    final selected =
        groups.where((group) => group.source == _selectedSource).firstOrNull;
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('通知与提醒')),
      ),
      body: Row(
        children: [
          SizedBox(
            key: const ValueKey('notification-settings-source-pane'),
            width: 300,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('提醒来源', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (groups.isEmpty)
                  const _EmptyAlertState()
                else
                  _SettingsCard(
                    children: [
                      for (final group in groups)
                        _SourceSummaryRow(
                          rowKey: ValueKey(
                            'notification-tablet-source-${group.source}',
                          ),
                          group: group,
                          subscriptions: _subscriptions,
                          defaultFor: _defaultFor,
                          selected: group.source == _selectedSource,
                          onTap:
                              () => setState(
                                () => _selectedSource = group.source,
                              ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey('notification-settings-detail-pane'),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 24, 32),
                children: [
                  _PageIntro(
                    title: selected?.source ?? '通知与提醒',
                    description:
                        selected == null
                            ? '选择左侧来源查看设置。'
                            : _sourceSubtitle(selected.source),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _openGroup(selected),
                      icon: const Icon(Icons.tune),
                      label: const Text('打开来源详情'),
                    ),
                  ],
                  if (_liveUpdateDefinitions.isNotEmpty ||
                      _exactAlarmSupported) ...[
                    const SizedBox(height: 24),
                    const _SettingsSectionHeader(
                      title: '送达方式',
                      subtitle: '控制提醒送达时间和系统通知显示方式',
                    ),
                    const SizedBox(height: 8),
                    _buildMaterialDeliveryCard(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialDeliveryCard() {
    final children = <Widget>[];
    if (_exactAlarmSupported) {
      children.add(
        _DeliverySwitchRow(
          key: const ValueKey('notification-exact-alarm'),
          icon: Icons.alarm_outlined,
          title: '优先精确送达',
          subtitle:
              !_exactAlarmRequested
                  ? '默认关闭，使用低功耗的非精确调度'
                  : _exactAlarmAuthorized
                  ? '系统已授权精确闹钟'
                  : '尚未获得系统授权，将自动降级为大致时间',
          value: _exactAlarmRequested,
          onChanged: _setExactAlarmRequested,
        ),
      );
    }
    if (_liveUpdateDefinitions.isNotEmpty) {
      if (_promotedSupported) {
        children.add(
          _StatusSettingsRow(
            key: const ValueKey('notification-promoted-status'),
            icon:
                _canPostPromotedNotifications
                    ? Icons.check_circle_outline
                    : Icons.notification_important_outlined,
            iconColor:
                _canPostPromotedNotifications
                    ? null
                    : Theme.of(context).colorScheme.error,
            title: _canPostPromotedNotifications ? '状态栏实时动态已启用' : '启用状态栏实时动态',
            subtitle:
                _canPostPromotedNotifications
                    ? '系统已允许 MyCHU 显示 Status Chip'
                    : '需要在系统中允许推广通知，才能显示 Status Chip',
            onTap: () async {
              await LiveUpdateService.openPromotionSettings();
            },
          ),
        );
      }
      for (final definition in _liveUpdateDefinitions) {
        children.add(
          _LiveUpdateRow(
            key: ValueKey('notification-live-update-${definition.id}'),
            definition: definition,
            enabled: _liveUpdateEnabled[definition.id] ?? true,
            onChanged: (enabled) => _updateLiveUpdate(definition, enabled),
          ),
        );
      }
      children.add(
        const _StatusSettingsRow(
          key: ValueKey('notification-channel-settings'),
          icon: Icons.settings_outlined,
          title: '系统通知设置',
          subtitle: '调整课程实时动态的声音、振动和显示方式',
          onTap: LiveUpdateService.openChannelSettings,
        ),
      );
    }
    return _SettingsCard(children: children);
  }
}

List<_ProviderGroup> _buildProviderGroups(List<AlertProvider> providers) {
  final bySource = <String, List<AlertProvider>>{};
  for (final provider in providers) {
    bySource.putIfAbsent(provider.source, () => []).add(provider);
  }
  return [
    for (final entry in bySource.entries)
      _ProviderGroup(source: entry.key, providers: entry.value),
  ];
}

String _sourceSubtitle(String source) {
  return switch (source) {
    '教务' => '成绩更新与考试临近',
    '个人数据' => '校园卡余额与未读邮件',
    '畅课' => '课程待办与截止时间',
    '我的课表' => '明日早八与课前提醒',
    _ => '提醒内容',
  };
}

IconData _sourceIconFor(String source) {
  return switch (source) {
    '个人数据' => Icons.account_balance_wallet_outlined,
    '教务' => Icons.school_outlined,
    '畅课' => Icons.assignment_outlined,
    '我的课表' => Icons.calendar_month_outlined,
    _ => Icons.notifications_outlined,
  };
}

int _enabledProviderCount(
  _ProviderGroup group,
  Map<String, AlertSubscription> subscriptions,
  _DefaultAlertSubscription defaultFor,
) {
  return group.providers
      .where(
        (provider) =>
            (subscriptions[provider.id] ?? defaultFor(provider)).enabled,
      )
      .length;
}

class _ProviderGroup {
  final String source;
  final List<AlertProvider> providers;

  const _ProviderGroup({required this.source, required this.providers});
}

typedef _ProviderSubscriptionUpdater =
    Future<void> Function(
      AlertSubscription Function(AlertSubscription current) update,
    );

typedef _AlertSubscriptionUpdate =
    Future<AlertSubscription> Function(
      AlertProvider provider,
      AlertSubscription Function(AlertSubscription current) update,
    );

typedef _DefaultAlertSubscription =
    AlertSubscription Function(AlertProvider provider);

class _PageIntro extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const _PageIntro({
    required this.title,
    required this.description,
    this.icon = Icons.notifications_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SourceIcon(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SettingsSectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 72,
                endIndent: 16,
                color: colors.outlineVariant.withValues(alpha: 0.75),
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _EmptyAlertState extends StatelessWidget {
  const _EmptyAlertState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_outlined,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              '暂无可订阅的提醒',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceIcon extends StatelessWidget {
  final IconData icon;

  const _SourceIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: colors.onPrimaryContainer),
    );
  }
}

class _SeverityIcon extends StatelessWidget {
  final AlertSeverity severity;

  const _SeverityIcon({required this.severity});

  @override
  Widget build(BuildContext context) {
    final color = alertSeverityColor(context, severity);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(alertSeverityIcon(severity), size: 20, color: color),
    );
  }
}

class _SourceSummaryRow extends StatelessWidget {
  final Key? rowKey;
  final _ProviderGroup group;
  final Map<String, AlertSubscription> subscriptions;
  final _DefaultAlertSubscription defaultFor;
  final bool selected;
  final VoidCallback onTap;

  const _SourceSummaryRow({
    this.rowKey,
    required this.group,
    required this.subscriptions,
    required this.defaultFor,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabledCount = _enabledProviderCount(
      group,
      subscriptions,
      defaultFor,
    );
    final countLabel = '$enabledCount/${group.providers.length} 开启';
    return Semantics(
      container: true,
      button: true,
      label: '${group.source}，${_sourceSubtitle(group.source)}，$countLabel',
      child: ListTile(
        key: rowKey,
        selected: selected,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _SourceIcon(icon: _sourceIconFor(group.source)),
        title: Text(
          group.source,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(_sourceSubtitle(group.source)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              countLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _DeliverySwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DeliverySwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, color: colors.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _StatusSettingsRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _StatusSettingsRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, color: iconColor ?? colors.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _NotificationSourcePage extends StatefulWidget {
  final _ProviderGroup group;

  final Map<String, AlertSubscription> subscriptions;
  final _DefaultAlertSubscription defaultFor;
  final _AlertSubscriptionUpdate onUpdate;

  const _NotificationSourcePage({
    required this.group,

    required this.subscriptions,
    required this.defaultFor,
    required this.onUpdate,
  });

  @override
  State<_NotificationSourcePage> createState() =>
      _NotificationSourcePageState();
}

class _NotificationSourcePageState extends State<_NotificationSourcePage> {
  late final Map<String, AlertSubscription> _subscriptions =
      Map<String, AlertSubscription>.from(widget.subscriptions);

  Future<void> _updateProvider(
    AlertProvider provider,
    AlertSubscription Function(AlertSubscription current) update,
  ) async {
    final next = await widget.onUpdate(provider, update);
    if (!mounted) return;
    setState(() => _subscriptions[provider.id] = next);
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterialPage();
  }

  Widget _buildMaterialPage() {
    final group = widget.group;
    return Scaffold(
      key: ValueKey('notification-source-detail-${group.source}'),
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: Text(group.source)),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _PageIntro(
            title: group.source,
            description: _sourceSubtitle(group.source),
            icon: _sourceIconFor(group.source),
          ),
          const SizedBox(height: 24),
          const _SettingsSectionHeader(
            title: '提醒内容',
            subtitle: '每条提醒都可以单独开关和调整条件',
          ),
          const SizedBox(height: 8),
          _SettingsCard(
            key: const ValueKey('notification-provider-list'),
            children: [
              for (final provider in group.providers)
                _MaterialProviderControl(
                  provider: provider,
                  subscription: _subscriptions[provider.id],
                  defaultFor: widget.defaultFor,

                  onUpdate: (update) => _updateProvider(provider, update),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialProviderControl extends StatelessWidget {
  final AlertProvider provider;
  final AlertSubscription? subscription;
  final _DefaultAlertSubscription defaultFor;

  final _ProviderSubscriptionUpdater onUpdate;

  const _MaterialProviderControl({
    required this.provider,
    required this.subscription,
    required this.defaultFor,

    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final current = subscription ?? defaultFor(provider);
    final enabled = current.enabled;
    final showBanner = provider.severity != AlertSeverity.info;
    final showOptions = enabled && (provider.params.isNotEmpty || showBanner);
    final optionRows = <Widget>[
      for (final spec in provider.params)
        _ParameterSettingsRow(
          key: ValueKey('notification-param-${provider.id}-${spec.key}'),
          spec: spec,
          value: _paramValue(current, spec),
          onTap: () async {
            final value = await _editAlertParameter(
              context: context,
              spec: spec,
              current: current,
            );
            if (value != null) {
              await onUpdate(
                (item) =>
                    item.copyWith(params: {...item.params, spec.key: value}),
              );
            }
          },
        ),
    ];
    if (showBanner) {
      optionRows.add(
        _SystemBannerSettingsRow(
          key: ValueKey('notification-banner-${provider.id}'),
          value: current.systemBanner,
          onChanged:
              (value) => onUpdate((item) => item.copyWith(systemBanner: value)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: ValueKey('notification-provider-${provider.id}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: _SeverityIcon(severity: provider.severity),
          title: Text(
            provider.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(_kindLabel(provider.kind)),
          trailing: Switch(
            value: enabled,
            onChanged:
                (value) => onUpdate((item) => item.copyWith(enabled: value)),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child:
              showOptions
                  ? Padding(
                    padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                    child: _SettingsCard(
                      children: [
                        for (
                          var index = 0;
                          index < optionRows.length;
                          index++
                        ) ...[
                          if (index > 0)
                            Divider(
                              height: 1,
                              indent: 12,
                              endIndent: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.7),
                            ),
                          optionRows[index],
                        ],
                      ],
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ParameterSettingsRow extends StatelessWidget {
  final AlertParamSpec spec;
  final Object? value;
  final VoidCallback onTap;

  const _ParameterSettingsRow({
    super.key,
    required this.spec,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(spec.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_display(value)} ${spec.unit}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _SystemBannerSettingsRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SystemBannerSettingsRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(
        Icons.notifications_active_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('系统横幅提醒'),
      subtitle: const Text('在通知栏顶部弹出提醒'),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _LiveUpdateRow extends StatelessWidget {
  final SystemLiveActivityDefinition definition;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _LiveUpdateRow({
    super.key,
    required this.definition,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(
        Icons.notifications_active_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        definition.title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '系统界面持续显示课程进度；按设备能力提供支持',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Switch(value: enabled, onChanged: onChanged),
    );
  }
}

class _AlertParameterDialog extends StatefulWidget {
  final AlertParamSpec spec;

  final double initialValue;

  const _AlertParameterDialog({required this.spec, required this.initialValue});

  @override
  State<_AlertParameterDialog> createState() => _AlertParameterDialogState();
}

class _AlertParameterDialogState extends State<_AlertParameterDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _display(widget.initialValue));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _complete() {
    final parsed = double.tryParse(_controller.text.trim());
    Navigator.pop(
      context,
      parsed?.clamp(widget.spec.min, widget.spec.max).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.spec.label),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(suffixText: widget.spec.unit),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _complete, child: const Text('完成')),
      ],
    );
  }
}

Future<double?> _editAlertParameter({
  required BuildContext context,
  required AlertParamSpec spec,
  required AlertSubscription current,
}) async {
  final existing =
      (_paramValue(current, spec) as num?)?.toDouble() ?? spec.defaultValue;
  if (spec.type == AlertParamType.number) {
    return showDialog<double>(
      context: context,
      builder: (_) => _AlertParameterDialog(spec: spec, initialValue: existing),
    );
  }
  final options =
      spec.type == AlertParamType.hours
          ? const [6, 12, 24, 48, 72, 168]
          : const [10, 15, 30, 60, 120];
  final selectedOption =
      spec.type == AlertParamType.hours
          ? _nearestHours(existing)
          : _nearestMinutes(existing);
  final selected = await showAdaptiveActionSheet<int>(
    context,
    title: spec.label,

    options: [
      for (final option in options)
        AdaptiveActionSheetOption(
          label: '$option ${spec.unit}',
          value: option,
          selected: option == selectedOption,
        ),
    ],
  );
  return selected?.toDouble();
}

String _kindLabel(AlertKind kind) {
  return switch (kind) {
    AlertKind.event => '内容有变化时提醒',
    AlertKind.condition => '满足条件时提醒',
    AlertKind.deadline => '临近截止时提醒',
  };
}

Object? _paramValue(AlertSubscription? subscription, AlertParamSpec spec) {
  final raw = subscription?.params[spec.key];
  if (raw == null) return spec.defaultValue;
  return raw;
}

String _display(Object? value) {
  final number = value is num ? value.toDouble() : 0.0;
  return number == number.roundToDouble()
      ? number.toStringAsFixed(0)
      : number.toStringAsFixed(1);
}

int _nearestHours(double value) {
  const options = [6, 12, 24, 48, 72, 168];
  var best = 24;
  var bestDistance = double.infinity;
  for (final option in options) {
    final distance = (option - value).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = option;
    }
  }
  return best;
}

int _nearestMinutes(double value) {
  const options = [10, 15, 30, 60, 120];
  return options.reduce(
    (left, right) =>
        (left - value).abs() <= (right - value).abs() ? left : right,
  );
}
