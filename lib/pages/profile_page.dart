import '../capabilities/host_login.dart';
import 'package:mychu/widgets/campus_auth_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/account.dart';
import '../services/auth_service.dart';
import '../services/app_remote_services_service.dart';
import '../services/auth_lifecycle_service.dart';
import '../services/ip_status_service.dart';
import '../services/portal_identity_service.dart';
import '../services/campus_settings_service.dart';
import '../services/updates/app_update_service.dart';
import '../widgets/adaptive_confirmation_dialog.dart';
import '../widgets/adaptive_settings.dart';
import 'about_page.dart';
import 'app_update_section.dart';
import 'appearance_theme_page.dart';
import 'campus_settings_sheet.dart';
import 'channel_account_page.dart';
import 'fenfa_dialogs.dart' show showAppRemoteServicesDisabledMessage;
import 'fenfa_feedback_page.dart';
import 'notification_settings_page.dart';
import 'page_management_page.dart';
import 'profile/profile_widgets.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback onSignedOut;
  final AppUpdateService? updates;

  const ProfilePage({super.key, required this.onSignedOut, this.updates});

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

  @override
  void initState() {
    super.initState();
    CampusSettingsService.revision.addListener(_updateCampusLabel);
    _load();
    _loadCampusLabel();
    _loadNetworkStatus();
    _loadVersion();
  }

  @override
  void dispose() {
    CampusSettingsService.revision.removeListener(_updateCampusLabel);
    super.dispose();
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

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _openFeedback() async {
    if (!await AppRemoteServicesService.isEnabled()) {
      if (mounted) showAppRemoteServicesDisabledMessage(context);
      return;
    }
    if (mounted) _push(const FenfaFeedbackPage());
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
                    trailingValue: _versionLabel.isEmpty ? null : _versionLabel,
                    onTap: () => _push(const AboutPage()),
                  ),
                  ProfileSettingTile(
                    icon: Icons.feedback_outlined,
                    title: '建言献策',
                    onTap: _openFeedback,
                  ),
                ],
              ),
              AppUpdateSection(service: widget.updates),
              const SizedBox(height: 8),
              if (_account != null)
                SignOutAction(onPressed: _confirmSignOut)
              else
                FilledButton.icon(
                  onPressed: () => HostLogin.open(context),
                  icon: const Icon(Icons.login),
                  label: const Text('登录校园账号'),
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
