import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/account.dart';
import '../services/auth_service.dart';
import '../services/auth_lifecycle_service.dart';
import '../services/ip_status_service.dart';
import '../services/portal_identity_service.dart';
import '../services/theme_service.dart';
import '../services/campus_settings_service.dart';
import '../widgets/adaptive_confirmation_dialog.dart';
import '../widgets/adaptive_settings.dart';
import 'about_page.dart';
import 'campus_settings_sheet.dart';
import 'channel_account_page.dart';
import 'notification_settings_page.dart';
import 'page_management_page.dart';
import 'profile/profile_widgets.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback onSignedOut;

  const ProfilePage({super.key, required this.onSignedOut});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

enum _AccountPhase { loading, signedIn, signedOut, failed }

class _ProfilePageState extends State<ProfilePage> {
  _AccountPhase _accountPhase = _AccountPhase.loading;
  Account? _account;
  CampusNetworkStatus? _networkStatus;
  bool _networkLoading = true;
  String _themeLabel = '跟随系统';
  String _campusLabel = '渭水校区';
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    themePreferencesNotifier.addListener(_updateThemeLabel);
    CampusSettingsService.revision.addListener(_updateCampusLabel);
    _themeLabel = _labelFor(themePreferencesNotifier.value);
    _load();
    _loadNetworkStatus();
    _loadVersion();
  }

  @override
  void dispose() {
    themePreferencesNotifier.removeListener(_updateThemeLabel);
    CampusSettingsService.revision.removeListener(_updateCampusLabel);
    super.dispose();
  }

  String _labelFor(ThemePreferences preferences) {
    return switch (preferences.mode) {
      AppThemeMode.light => '浅色',
      AppThemeMode.dark => '深色',
      AppThemeMode.system => '跟随系统',
    };
  }

  void _updateThemeLabel() {
    final label = _labelFor(themePreferencesNotifier.value);
    if (_themeLabel == label) return;
    if (!mounted) return;
    setState(() => _themeLabel = label);
  }

  void _updateCampusLabel() {
    final accountKey = _account?.accountKey;
    if (!mounted || accountKey == null) return;
    unawaited(_loadCampusLabel(accountKey));
  }

  Future<void> _loadCampusLabel(String accountKey) async {
    final campusId = await campusSettingsService.read(accountKey);
    final campus = await campusSettingsService.campusFor(campusId);
    final label = campus?.displayName ?? '渭水校区';
    if (!mounted ||
        _account?.accountKey != accountKey ||
        label == _campusLabel) {
      return;
    }
    setState(() => _campusLabel = label);
  }

  Future<void> _showCampusSettingsSheet() async {
    final accountKey = _account?.accountKey;
    if (accountKey == null || !mounted) return;

    await showCampusSettingsSheet(context, accountKey: accountKey);
    if (mounted && _account?.accountKey == accountKey) {
      await _loadCampusLabel(accountKey);
    }
  }

  Future<void> _load() async {
    try {
      final account = await AuthService.getCurrentAccount();
      if (!mounted) return;
      if (account == null) {
        setState(() {
          _account = null;
          _accountPhase = _AccountPhase.signedOut;
        });
      } else {
        setState(() {
          _account = account;
          _accountPhase = _AccountPhase.signedIn;
        });
        unawaited(_loadCampusLabel(account.accountKey));
        if (!PortalIdentityService.hasDisplayName(account.name) ||
            account.uid == null ||
            !PortalIdentityService.hasIdentity(account.identity)) {
          unawaited(_refreshAccountName(account));
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _accountPhase = _AccountPhase.failed);
    }
  }

  Future<void> _refreshAccountName(Account account) async {
    final updated = await PortalIdentityService.refreshAccountName();
    if (!mounted ||
        updated == null ||
        _account?.accountKey != account.accountKey) {
      return;
    }
    if (updated.name != _account?.name ||
        updated.uid != _account?.uid ||
        updated.identity != _account?.identity) {
      setState(() => _account = updated);
    }
  }

  Future<void> _loadNetworkStatus() async {
    final status = await IpStatusService().fetchStatus();
    if (!mounted) return;
    setState(() {
      _networkStatus = status;
      _networkLoading = false;
    });
  }

  Future<CampusNetworkStatus?> _refreshNetworkStatus() async {
    final status = await IpStatusService().fetchStatus(force: true);
    if (!mounted) return status;
    setState(() {
      _networkStatus = status;
      _networkLoading = false;
    });
    return status;
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = 'v${info.version}');
    } catch (_) {
      // Version display is optional; AboutPage still loads it independently.
    }
  }

  Future<void> _showThemeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return ValueListenableBuilder<ThemePreferences>(
          valueListenable: themePreferencesNotifier,
          builder:
              (context, preferences, _) => SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '主题',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      RadioGroup<AppThemeMode>(
                        groupValue: preferences.mode,
                        onChanged: (mode) {
                          if (mode == null) return;
                          themePreferencesNotifier.setMode(mode);
                          Navigator.pop(sheetContext);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const RadioListTile<AppThemeMode>(
                              title: Text('跟随系统'),
                              value: AppThemeMode.system,
                            ),
                            const RadioListTile<AppThemeMode>(
                              title: Text('浅色'),
                              value: AppThemeMode.light,
                            ),
                            const RadioListTile<AppThemeMode>(
                              title: Text('深色'),
                              value: AppThemeMode.dark,
                            ),
                            SwitchListTile(
                              title: const Text('动态取色'),
                              subtitle:
                                  preferences.dynamicColorSupported
                                      ? null
                                      : const Text('仅Android12+可用'),
                              value: preferences.dynamicColorEnabled,
                              onChanged:
                                  preferences.dynamicColorSupported
                                      ? (enabled) {
                                        themePreferencesNotifier
                                            .setDynamicColorEnabled(enabled);
                                      }
                                      : null,
                            ),
                            if (!kIsWeb &&
                                defaultTargetPlatform == TargetPlatform.android)
                              SwitchListTile(
                                key: const ValueKey(
                                  'predictive-back-animation-setting',
                                ),
                                title: const Text('预测性返回动画'),
                                subtitle: const Text('部分国产系统可能不兼容'),
                                value: preferences.predictiveBackEnabled,
                                onChanged: (enabled) {
                                  themePreferencesNotifier
                                      .setPredictiveBackEnabled(enabled);
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        );
      },
    );
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _confirmSignOut() async {
    const signOutMessage = '退出登录会清除已保存的登录信息。';
    final confirmation = showAdaptiveConfirmationDialog(
      context,
      title: '退出登录',
      message: signOutMessage,
      confirmLabel: '退出登录',
      destructive: true,
    );
    final confirmed = await confirmation;
    if (confirmed != true) return;
    await AuthLifecycleService.signOut();
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final content = CustomScrollView(
      slivers: [
        const SliverAppBar.medium(title: Text('我的')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverList.list(
            children: [
              ProfileIdentityCard(
                loading: _accountPhase == _AccountPhase.loading,
                loadFailed: _accountPhase == _AccountPhase.failed,
                name: _account?.name,
                uid: _account?.uid,
                identity: _account?.identity,
                networkStatus: _networkStatus,
                networkLoading: _networkLoading,
                onRetryAccount:
                    _accountPhase == _AccountPhase.failed
                        ? () {
                          setState(() => _accountPhase = _AccountPhase.loading);
                          _load();
                        }
                        : null,
                onOpenNetworkDetails:
                    _networkLoading
                        ? null
                        : () => showNetworkStatusSheet(
                          context,
                          status: _networkStatus,
                          refresh: _refreshNetworkStatus,
                        ),
              ),
              const SizedBox(height: 24),
              AdaptiveSettingsSection(
                title: '账号',

                margin: EdgeInsets.zero,
                children: [
                  ProfileSettingTile(
                    icon: Icons.forum_outlined,
                    title: '频道账号',
                    subtitle: '管理校园频道账号',
                    onTap: () => _push(const ChannelAccountPage()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AdaptiveSettingsSection(
                title: '偏好设置',

                margin: EdgeInsets.zero,
                children: [
                  ProfileSettingTile(
                    icon: Icons.palette_outlined,
                    title: '主题',
                    trailingValue: _themeLabel,
                    onTap: _showThemeSheet,
                  ),
                  ProfileSettingTile(
                    icon: Icons.location_city_outlined,
                    title: '校区设置',
                    trailingValue: _campusLabel,
                    onTap: _showCampusSettingsSheet,
                  ),
                  ProfileSettingTile(
                    icon: Icons.tune_outlined,
                    title: '页面显示',
                    onTap: () => _push(const PageManagementPage()),
                  ),
                  ProfileSettingTile(
                    icon: Icons.notifications_outlined,
                    title: '通知与提醒',
                    onTap: () => _push(const NotificationSettingsPage()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AdaptiveSettingsSection(
                title: '其他',

                margin: EdgeInsets.zero,
                children: [
                  ProfileSettingTile(
                    icon: Icons.info_outline,
                    title: '关于',
                    trailingValue:
                        _versionLabel.isEmpty ? null : _versionLabel,
                    onTap: () => _push(const AboutPage()),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SignOutAction(onPressed: _confirmSignOut),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: content,
        ),
      ),
    );
  }
}
