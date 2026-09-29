import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/user_error_message.dart';
import '../information_portal/information_portal_models.dart';
import '../information_portal/information_portal_service.dart';
import 'portal_todos_view.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

typedef PortalPersonalDataLoader =
    Future<Map<PortalInfoKind, PortalPersonalInfo>> Function({
      required bool force,
    });

/// 个人数据页面的两个 Tab 宿主。
class PortalPersonalPage extends StatefulWidget {
  final int initialTabIndex;

  const PortalPersonalPage({super.key, this.initialTabIndex = 0});

  @override
  State<PortalPersonalPage> createState() => _PortalPersonalPageState();
}

class _PortalPersonalPageState extends State<PortalPersonalPage>
    with SingleTickerProviderStateMixin {
  final _personalStatusKey = GlobalKey<PortalPersonalStatusPanelState>();
  late int _selectedTab;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTabIndex.clamp(0, 1).toInt();
    _tabController = TabController(
      length: 2,
      initialIndex: _selectedTab,
      vsync: this,
    )..addListener(_onMaterialTabChanged);
  }

  void _onMaterialTabChanged() {
    final index = _tabController.index;
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onMaterialTabChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _refreshPersonalStatus() async {
    await _personalStatusKey.currentState?.refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex.clamp(0, 1).toInt(),
      child: Scaffold(
        appBar: WindowControlsAwareAppBar(
          child: AppBar(
            title: const Text('个人数据'),
            actions: [
              IconButton(
                tooltip: '刷新个人数据',
                onPressed: _refreshPersonalStatus,
                icon: const Icon(Icons.refresh),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [Tab(text: '个人状态'), Tab(text: '课程待办')],
            ),
          ),
        ),
        body: _buildMaterialTabView(),
      ),
    );
  }

  Widget _buildMaterialTabView() {
    return TabBarView(
      controller: _tabController,
      children: [
        PortalPersonalStatusPanel(
          key: _personalStatusKey,
          active: _selectedTab == 0,
        ),
        PortalTodosView(active: _selectedTab == 1),
      ],
    );
  }
}

/// Personal data state, refresh behavior, balance preference, and platform UI.
class PortalPersonalStatusPanel extends StatefulWidget {
  final PortalPersonalDataLoader? loader;

  final bool active;

  const PortalPersonalStatusPanel({super.key, this.loader, this.active = true});

  @override
  PortalPersonalStatusPanelState createState() =>
      PortalPersonalStatusPanelState();
}

class PortalPersonalStatusPanelState extends State<PortalPersonalStatusPanel>
    with AutomaticKeepAliveClientMixin {
  static const _balanceHiddenKeyPrefix = 'information_portal.balance_hidden.v1';

  Map<PortalInfoKind, PortalPersonalInfo>? _data;
  String? _error;
  String? _accountId;
  bool _balanceHidden = false;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_load());
    unawaited(_initializeBalanceHidden());
  }

  @override
  void didUpdateWidget(covariant PortalPersonalStatusPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && _data == null && !_loading) {
      unawaited(_load());
    }
  }

  /// Refresh the panel. User initiated refreshes pass force=true.
  Future<void> refresh({bool force = false}) => _load(force: force);

  Future<void> _initializeBalanceHidden() async {
    final accountId = (await AuthService.getCurrentAccount())?.id;
    final prefs = await SharedPreferences.getInstance();
    final hidden =
        prefs.getBool('$_balanceHiddenKeyPrefix.${accountId ?? 'anonymous'}') ??
        false;
    if (!mounted) return;
    setState(() {
      _accountId = accountId;
      _balanceHidden = hidden;
    });
  }

  Future<void> _load({bool force = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader;
      final data =
          loader == null
              ? await PortalApiService().fetchPersonalData(force: force)
              : await loader(force: force);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted) return;
      if (widget.active) {
        logUserFacingError(
          UserErrorContext.network,
          error,
          operation: 'personal',
        );
      }
      setState(() => _error = userFacingError(UserErrorContext.network, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setBalanceHidden(bool hidden) async {
    setState(() => _balanceHidden = hidden);
    final accountId = _accountId ?? (await AuthService.getCurrentAccount())?.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      '$_balanceHiddenKeyPrefix.${accountId ?? 'anonymous'}',
      hidden,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return _buildMaterialPersonalTab();
  }

  Widget _buildMaterialPersonalTab() {
    final data = _data;
    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && data == null) {
      return _FullPageError(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_error != null) _InlineIssue(message: _error!, onRetry: _load),
          _PersonalStatusPanel(
            data: data ?? const {},
            balanceHidden: _balanceHidden,
            onToggleBalance: () => _setBalanceHidden(!_balanceHidden),
          ),
        ],
      ),
    );
  }
}

class _PersonalStatusPanel extends StatelessWidget {
  final Map<PortalInfoKind, PortalPersonalInfo> data;
  final bool balanceHidden;
  final VoidCallback onToggleBalance;

  const _PersonalStatusPanel({
    required this.data,
    required this.balanceHidden,
    required this.onToggleBalance,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final card = data[PortalInfoKind.campusCard];
    final email = data[PortalInfoKind.email];
    final library = data[PortalInfoKind.library];
    final taskCenter = data[PortalInfoKind.taskCenter];
    final rows = <Widget>[];
    void addRow(bool visible, Widget row) {
      if (!visible) return;
      if (rows.isNotEmpty) rows.add(const Divider(height: 1));
      rows.add(row);
    }

    addRow(
      _hasDisplayValue(card),
      _PersonalStatusRow(
        icon: Icons.account_balance_wallet_outlined,
        title: '校园卡余额',
        value: _balanceValue(card),
        trailing: IconButton(
          tooltip: balanceHidden ? '显示余额' : '隐藏余额',
          onPressed: onToggleBalance,
          icon: Icon(
            balanceHidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
    if (email != null && _hasDisplayValue(email)) {
      addRow(
        true,
        _PersonalStatusRow(
          icon: Icons.mail_outline,
          title: '校园邮箱',
          value: email.mainInfo,
          subtitle: _emailAddress(email.subInfo),
        ),
      );
    }
    addRow(
      _hasDisplayValue(library),
      _PersonalStatusRow(
        icon: Icons.menu_book_outlined,
        title: '图书借阅',
        value: _libraryValue(library),
      ),
    );
    addRow(
      _hasDisplayValue(taskCenter),
      _PersonalStatusRow(
        icon: Icons.task_alt_outlined,
        title: '任务中心',
        value: taskCenter?.mainInfo ?? '',
        subtitle: taskCenter?.subInfo,
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: rows),
    );
  }

  String _balanceValue(PortalPersonalInfo? info) {
    if (info == null) return '暂不可用';
    return balanceHidden ? '***' : '${info.homeValue} 元';
  }

  String _libraryValue(PortalPersonalInfo? info) {
    if (info == null) return '暂不可用';
    return '${info.homeValue} 本未还';
  }

  bool _hasDisplayValue(PortalPersonalInfo? info) {
    if (info == null) return false;
    return info.mainInfo.trim().isNotEmpty || info.subInfo.trim().isNotEmpty;
  }

  String? _emailAddress(String? value) {
    final address = value?.replaceFirst(RegExp(r'^账号[：:]\s*'), '').trim();
    return address == null || address.isEmpty ? null : address;
  }
}

class _PersonalStatusRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final Widget? trailing;

  const _PersonalStatusRow({
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _InlineIssue extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _InlineIssue({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _FullPageError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _FullPageError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: colors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
