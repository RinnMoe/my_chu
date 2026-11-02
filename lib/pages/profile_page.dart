import '../capabilities/host_login.dart';
import '../capabilities/qq_group_join_capability.dart';
import 'package:mychu/widgets/campus_auth_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/account.dart';
import '../services/auth_service.dart';
import '../services/app_remote_services_service.dart';
import '../services/auth_lifecycle_service.dart';
import '../services/ip_status_service.dart';
import '../services/logger_service.dart';
import '../services/portal_identity_service.dart';
import '../services/campus_settings_service.dart';
import '../services/updates/app_update_service.dart';
import '../widgets/adaptive_confirmation_dialog.dart';
import '../widgets/adaptive_settings.dart';
import 'about_page.dart';
import 'app_update_section.dart';
import 'app_update_prompts.dart';
import 'appearance_theme_page.dart';
import 'campus_settings_sheet.dart';
import 'channel_account_page.dart';
import 'feedback_community_page.dart';
import 'fenfa_dialogs.dart' show showAppRemoteServicesDisabledMessage;
import 'notification_settings_page.dart';
import 'page_preferences_page.dart';
import 'profile/profile_widgets.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback onSignedOut;
  final AppUpdateService? updates;

  /// 加群调起可注入，测试不需要真实的系统 QQ。
  final QqGroupJoinCapability qqGroup;

  const ProfilePage({
    super.key,
    required this.onSignedOut,
    this.updates,
    this.qqGroup = const QqGroupJoinCapability(),
  });

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
  final _updateCardKey = GlobalKey();
  bool _signOutDialogOpen = false;
  bool _signingOut = false;

  Future<void> _checkForUpdates() => presentAppUpdateCheck(
    context,
    service: widget.updates,
    manual: true,
    onUpdateAvailable: () async {
      // The service notification must lay out the newly inserted card first.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final cardContext = _updateCardKey.currentContext;
      if (cardContext != null && cardContext.mounted) {
        await Scrollable.ensureVisible(
          cardContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    },
  );

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
    if (mounted) _push(const FeedbackCommunityPage());
  }

  /// 调起手机 QQ 加群；QQ 不可用时提示群号，避免入口变成死路。
  Future<void> _joinQqGroup() async {
    final opened = await widget.qqGroup.joinGroup();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '未能唤起 QQ，可在 QQ 中搜索群号 ${QqGroupJoinCapability.groupNumber}',
        ),
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    if (_signOutDialogOpen || _signingOut) return;
    _signOutDialogOpen = true;
    try {
      const signOutMessage = '退出登录会清除本机保存的登录信息、课程提醒和桌面课表小组件。';
      final confirmation = showAdaptiveConfirmationDialog(
        context,
        title: '退出登录',
        message: signOutMessage,
        confirmLabel: '退出登录',
        destructive: true,
        // A second tap while the dialog opens must not dismiss the destructive
        // confirmation through the barrier; only the explicit buttons decide.
        barrierDismissible: false,
      );
      final confirmed = await confirmation;
      if (confirmed != true || !mounted) return;
      setState(() => _signingOut = true);
      var signOutFailed = false;
      try {
        await AuthLifecycleService.signOut();
      } catch (error) {
        signOutFailed = true;
        AppLogger.recordSafeFailure(
          level: 'WARN',
          code: 'profile.sign_out_failed',
          message: '退出登录失败',
          error: error,
          domain: 'profile',
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('退出登录未完成，请重试')));
        }
      } finally {
        // The confirmation dialog is a separate route, so the page-level auth
        // listener can skip its deferred refresh while the dialog is current.
        // Reload from storage in all cases: after a successful sign-out this
        // shows the signed-out state immediately, and after a partial failure
        // it shows the actual remaining account state.
        if (mounted) await _load();
        if (mounted) setState(() => _signingOut = false);
      }
      if (mounted && !signOutFailed) widget.onSignedOut();
    } finally {
      _signOutDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = CustomScrollView(
      slivers: [
        const SliverAppBar.medium(pinned: true, title: Text('选项')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          sliver: SliverList.list(
            children: [
              AppUpdateSection(key: _updateCardKey, service: widget.updates),
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
                    icon: Icons.forum_outlined,
                    title: '频道账号',
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
                title: '关于本应用',
                margin: EdgeInsets.zero,
                children: [
                  ProfileSettingTile(
                    icon: Icons.update_rounded,
                    title: '检查更新',
                    trailingValue: _versionLabel.isEmpty ? null : _versionLabel,
                    onTap: _checkForUpdates,
                  ),
                  ProfileSettingTile(
                    icon: Icons.info_outline,
                    title: '关于',
                    onTap: () => _push(const AboutPage()),
                  ),
                  ProfileSettingTile(
                    icon: Icons.feedback_outlined,
                    title: '建言献策',
                    onTap: _openFeedback,
                  ),
                  ProfileSettingTile(
                    icon: Icons.groups_outlined,
                    title: 'QQ交流群',
                    trailingValue: QqGroupJoinCapability.groupNumber,
                    onTap: _joinQqGroup,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_account != null)
                SignOutAction(onPressed: _signingOut ? null : _confirmSignOut)
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
