import 'package:mychu/widgets/campus_auth_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/account.dart';
import '../services/auth_service.dart';
import '../services/file_save_service.dart';
import '../services/ip_status_service.dart';
import '../services/logging/logger.dart';
import '../services/portal_identity_service.dart';
import '../services/campus_settings_service.dart';
import '../capabilities/chat_demo/chat_demo_brand.dart';
import '../services/deepseek_api_settings_service.dart';
import '../services/updates/app_update_service.dart';
import '../widgets/adaptive_settings.dart';
import '../widgets/app_glass_app_bar.dart';
import 'about_page.dart';
import 'account_management_page.dart';
import 'app_update_section.dart';
import 'appearance_theme_page.dart';
import 'campus_settings_sheet.dart';
import 'deepseek_api_settings_page.dart';
import 'notification_settings_page.dart';
import 'page_preferences_page.dart';
import 'profile/profile_widgets.dart';
import 'release_notes_page.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback? onSignedOut;
  final AppUpdateService? updates;

  const ProfilePage({super.key, this.onSignedOut, this.updates});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

enum _AccountPhase { loading, signedIn, signedOut, failed }

class _ProfilePageState extends State<ProfilePage>
    with CampusAuthRefresh<ProfilePage> {
  @override
  Future<void> onCampusAuthChanged() => _load();

  _AccountPhase _accountPhase = _AccountPhase.loading;
  Account? _account;
  CampusNetworkStatus? _networkStatus;
  bool _networkLoading = true;
  String _campusLabel = '渭水校区';
  String _versionLabel = '';
  bool _deepSeekConfigured = false;

  @override
  void initState() {
    super.initState();
    CampusSettingsService.revision.addListener(_updateCampusLabel);
    DeepSeekApiSettingsService.instance.revision.addListener(
      _loadDeepSeekStatus,
    );
    _load();
    _loadCampusLabel();
    _loadNetworkStatus();
    _loadVersion();
    _loadDeepSeekStatus();
  }

  @override
  void dispose() {
    CampusSettingsService.revision.removeListener(_updateCampusLabel);
    DeepSeekApiSettingsService.instance.revision.removeListener(
      _loadDeepSeekStatus,
    );
    super.dispose();
  }

  Future<void> _loadDeepSeekStatus() async {
    bool configured;
    try {
      configured = await DeepSeekApiSettingsService.instance.read() != null;
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      configured = false;
    }
    if (!mounted || configured == _deepSeekConfigured) return;
    setState(() => _deepSeekConfigured = configured);
  }

  void _updateCampusLabel() {
    if (!mounted) return;
    unawaited(_loadCampusLabel());
  }

  Future<void> _loadCampusLabel() async {
    final campusId = await campusSettingsService.read();
    final campus = await campusSettingsService.campusFor(campusId);
    final label = campus?.displayName ?? '渭水校区';
    if (!mounted || label == _campusLabel) {
      return;
    }
    setState(() => _campusLabel = label);
  }

  Future<void> _showCampusSettingsSheet() async {
    if (!mounted) return;

    await showCampusSettingsSheet(context);
    if (mounted) {
      await _loadCampusLabel();
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
        unawaited(_loadCampusLabel());
        if (!PortalIdentityService.hasDisplayName(account.name) ||
            account.uid == null ||
            !PortalIdentityService.hasIdentity(account.identity)) {
          unawaited(_refreshAccountName(account));
        }
      }
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
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
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      // Version display is optional; AboutPage still loads it independently.
    }
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _openAccountManagement() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const AccountManagementPage()),
    );
    if (mounted) await _load();
  }

  Future<void> _shareApp() async {
    final opened = await FileSaveService.shareText(
      text: '点击下载MyCHU: https://mychu.rinn.moe',
    );
    if (!mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('未能打开系统分享，请重试')));
  }

  @override
  Widget build(BuildContext context) {
    // 玻璃底栏浮在内容上，滚动留白跟随底栏高度。
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final content = CustomScrollView(
      slivers: [
        const AppGlassSliverAppBar(title: '选项'),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + bottomInset),
          sliver: SliverList.list(
            children: [
              AppUpdateSection(service: widget.updates),
              const SizedBox(height: 24),
              AdaptiveSettingsSection(
                title: '账号',
                margin: EdgeInsets.zero,
                children: [
                  ProfileIdentityRow(
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
                              setState(
                                () => _accountPhase = _AccountPhase.loading,
                              );
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
                  ProfileSettingTile(
                    icon: Icons.manage_accounts_outlined,
                    title: '账号管理',
                    onTap: _openAccountManagement,
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
                    title: '外观与主题',
                    onTap: () => _push(const AppearanceThemePage()),
                  ),
                  ProfileSettingTile(
                    icon: Icons.location_city_outlined,
                    title: '校区设置',
                    trailingValue: _campusLabel,
                    onTap: _showCampusSettingsSheet,
                  ),
                  ProfileSettingTile(
                    icon: Icons.tune_outlined,
                    title: '底栏与页面偏好',
                    onTap: () => _push(const PagePreferencesPage()),
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
                title: askYuiName,
                margin: EdgeInsets.zero,
                children: [
                  ProfileSettingTile(
                    icon: Icons.auto_awesome_outlined,
                    title: '聊天设置',
                    trailingValue: _deepSeekConfigured ? 'API 已配置' : 'API 未配置',
                    onTap: () => _push(const DeepSeekApiSettingsPage()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AdaptiveSettingsSection(
                title: '关于本应用',
                margin: EdgeInsets.zero,
                children: [
                  ProfileSettingTile(
                    icon: Icons.new_releases_outlined,
                    title: '更新日志',
                    trailingValue: _versionLabel.isEmpty ? null : _versionLabel,
                    onTap:
                        () => _push(ReleaseNotesPage(updates: widget.updates)),
                  ),
                  ProfileSettingTile(
                    icon: Icons.info_outline,
                    title: '关于',
                    onTap: () => _push(const AboutPage()),
                  ),
                  ProfileSettingTile(
                    icon: Icons.share_outlined,
                    title: '分享本应用',
                    onTap: _shareApp,
                  ),
                ],
              ),
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
