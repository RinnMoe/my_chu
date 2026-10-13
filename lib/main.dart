import 'services/host_auth_state.dart';
import 'services/auth_service.dart';
import 'services/host_auth_coordinator.dart';
import 'widgets/campus_auth_boundary.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'capabilities/time_reminder_registry.dart';
import 'capabilities/authenticated_web_view_capability.dart';
import 'pages/apps_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/campus_settings_page.dart';
import 'capabilities/campus_map/campus_map_capability.dart';
import 'capabilities/academic_schedule/academic_schedule_capability.dart';
import 'capabilities/academic_schedule/academic_schedule_store.dart';
import 'capabilities/academic_schedule/recent_schedule_repository.dart';
import 'capabilities/academic_schedule/academic_schedule_alerts.dart';
import 'capabilities/desktop_widgets/desktop_widget_bridge.dart';
import 'capabilities/desktop_widgets/desktop_widget_models.dart';
import 'apps/app_registry.dart';
import 'apps/app_service.dart';
import 'services/login_required_notifier.dart';
import 'services/logger_service.dart';
import 'services/navigation_layout_service.dart';
import 'services/privacy_agreement_service.dart';
import 'services/usage_analytics_service.dart';
import 'services/time_reminder_service.dart';
import 'services/platform_compatibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'apps/portal_personal/portal_personal_page.dart';
import 'services/host_permission_service.dart';
import 'services/theme_service.dart';
import 'services/app_launch_service.dart';
import 'services/temporal_change_service.dart';
import 'services/root_navigation_service.dart';
import 'services/platform_environment.dart';
import 'services/campus_settings_service.dart';
import 'services/guide_preferences.dart';
import 'services/onboarding_flow_service.dart';
import 'theme/app_palette.dart';
import 'pages/fenfa_dialogs.dart';
import 'pages/privacy_agreement_dialog.dart';
import 'pages/app_sheet.dart';
import 'pages/host_permission_purpose_overlay.dart';
import 'widgets/adaptive_navigation_item.dart';
import 'widgets/adaptive_root_navigation.dart';
import 'widgets/adaptive_startup_splash.dart';
import 'widgets/apple_window_controls.dart';
import 'widgets/viewport_preview_host.dart';
import 'widgets/root_destination_active_scope.dart';

void main() {
  runZonedGuarded(_bootstrap, RuntimeErrorReporter.handleZoneError);
}

void _bootstrap() {
  RuntimeErrorReporter.install();
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Plugin debug callbacks serialize complete navigation requests, including
  // CAS tickets and short-lived access-token URLs. MyCHU emits its own
  // credential-free WebView lifecycle logs instead.
  PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  registerTimeReminders();
  unawaited(
    TimeReminderService.initialize().catchError((Object error) {
      AppLogger.warn('旧提醒清理失败 (${error.runtimeType})');
    }),
  );
  unawaited(themePreferencesNotifier.initialize());
  unawaited(AppLaunchService.initialize());
  TemporalChangeService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final Widget? initialHome;

  const MyApp({super.key, this.initialHome});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return ValueListenableBuilder<ThemePreferences>(
          valueListenable: themePreferencesNotifier,
          builder: (context, preferences, _) {
            final useDynamicColors = preferences.useDynamicColors;
            return _buildMaterialApp(
              preferences,
              lightDynamic: useDynamicColors ? lightDynamic : null,
              darkDynamic: useDynamicColors ? darkDynamic : null,
            );
          },
        );
      },
    );
  }

  Widget _buildMaterialApp(
    ThemePreferences preferences, {
    ColorScheme? lightDynamic,
    ColorScheme? darkDynamic,
  }) {
    final pageTransitionsTheme = _buildPageTransitionsTheme(
      preferences.predictiveBackEnabled,
    );

    return MaterialApp(
      title: 'MyCHU',
      debugShowCheckedModeBanner: false,
      builder:
          (context, child) => ScaffoldMessenger(
            child: AppleWindowControlsMetricsScope(
              child: ViewportPreviewHost(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
      themeMode: preferences.mode.materialThemeMode,
      theme: _buildTheme(
        Brightness.light,
        dynamicScheme: lightDynamic,
      ).copyWith(pageTransitionsTheme: pageTransitionsTheme),
      darkTheme: _buildTheme(
        Brightness.dark,
        dynamicScheme: darkDynamic,
      ).copyWith(pageTransitionsTheme: pageTransitionsTheme),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: const Locale('zh'),
      home: initialHome ?? const AppShell(),
    );
  }

  PageTransitionsTheme _buildPageTransitionsTheme(bool predictiveBackEnabled) {
    final androidBuilder =
        predictiveBackEnabled
            ? const PredictiveBackPageTransitionsBuilder()
            : const ZoomPageTransitionsBuilder();

    return PageTransitionsTheme(
      builders: {
        TargetPlatform.android: androidBuilder,
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: const ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: const ZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: const ZoomPageTransitionsBuilder(),
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness, {ColorScheme? dynamicScheme}) {
    final scheme = resolveAppColorScheme(
      brightness,
      dynamicScheme: dynamicScheme,
    );

    return ThemeData(
      colorScheme: scheme,
      extensions: [AppSemanticColors.forBrightness(brightness)],
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.pressed)) {
            return scheme.primary.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return scheme.primary.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: scheme.primary, width: 2);
          }
          return BorderSide(color: scheme.outlineVariant);
        }),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        hintStyle: WidgetStatePropertyAll(
          TextStyle(color: scheme.onSurfaceVariant),
        ),
        constraints: const BoxConstraints(minHeight: 56),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.16),
        selectionHandleColor: scheme.primary,
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _ready = false;
  int _restoreGeneration = 0;

  @override
  void initState() {
    super.initState();
    LoginRequiredNotifier.addListener(_onLoginRequired);
    unawaited(_refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FlutterNativeSplash.remove();
    });
  }

  @override
  void dispose() {
    _restoreGeneration++;
    LoginRequiredNotifier.removeListener(_onLoginRequired);
    super.dispose();
  }

  void _onLoginRequired(String reason) {
    HostAuthCoordinator.requireLogin();
    LoginRequiredNotifier.markPromptDismissed();
  }

  Future<void> _refresh() async {
    final generation = ++_restoreGeneration;
    if (!await _requirePrivacyAgreement(generation)) return;
    await HostAuthCoordinator.initialize();
    if (!mounted || generation != _restoreGeneration) return;
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _restoreGeneration) {
        unawaited(HostAuthCoordinator.check());
      }
    });
  }

  /// The basic privacy agreement precedes login, Main, analytics, and sessions.
  Future<bool> _requirePrivacyAgreement(int generation) async {
    if (!mounted || generation != _restoreGeneration) return false;
    try {
      if (!await PrivacyAgreementService.isAccepted()) {
        if (!mounted || generation != _restoreGeneration) return false;
        final decision = await presentPrivacyAgreement(context);
        if (decision != PrivacyAgreementDecision.accepted) {
          await SystemNavigator.pop();
          return false;
        }
        await PrivacyAgreementService.accept();
      }
      if (!mounted || generation != _restoreGeneration) return false;
      unawaited(UsageAnalyticsService.initializeIfEnabled());
      return true;
    } catch (error) {
      AppLogger.warn('隐私协议流程失败 (${error.runtimeType})');
      if (mounted && generation == _restoreGeneration) {
        setState(() {
          _ready = false;
        });
        _showAgreementRetry();
      }
      return false;
    }
  }

  void _showAgreementRetry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void retry() {
        unawaited(_refresh());
      }

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        unawaited(
          showDialog<void>(
            context: context,
            builder:
                (dialogContext) => AlertDialog(
                  title: const Text('暂时无法继续'),
                  content: const Text('无法读取隐私协议设置，请稍后重试。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('稍后'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        retry();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
          ),
        );
      } else {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('无法读取隐私协议设置，请稍后重试。'),
              action: SnackBarAction(label: '重试', onPressed: retry),
            ),
          );
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? MainScreen(onSignedOut: () {}) : const AdaptiveStartupSplash();
}

class MainScreen extends StatefulWidget {
  final VoidCallback onSignedOut;
  final DeviceFamily? deviceFamilyOverride;
  final WindowClass? windowClassOverride;

  const MainScreen({
    super.key,
    required this.onSignedOut,
    this.deviceFamilyOverride,
    this.windowClassOverride,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  List<_NavTab> _tabs = [];
  final Map<String, Widget?> _pages = {};
  String _currentKey = NavigationLayoutService.hostHomeKey;
  String? _accountKey;
  int _authContentRevision = HostAuthState.snapshot.value.contentRevision;
  bool _startupReady = false;
  bool _campusPromptRunning = false;
  bool _campusPromptAttempted = false;
  bool _onboardingFlowRunning = false;
  bool _onboardingFlowAttempted = false;
  Future<void>? _resumeSessionCheck;
  final GuidePreferences _guidePreferences = GuidePreferences();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NavigationLayoutService.revision.addListener(_reloadTabs);
    HostAuthState.snapshot.addListener(_onAuthSnapshotChanged);
    appCatalogNotifier.addListener(_reloadTabs);
    AppLaunchService.revision.addListener(_handleAppLaunch);
    RootNavigationService.revision.addListener(_handleRootNavigationRequest);
    TemporalChangeService.revision.addListener(_handleTemporalChange);
    AcademicScheduleStore.revision.addListener(_syncDesktopWidgetSnapshot);
    RecentScheduleRepository.instance.revision.addListener(
      _onRecentScheduleChanged,
    );
    unawaited(AppLaunchService.initialize());
    _reloadTabs();
    _handleAppLaunch();
    _syncDesktopWidgetSnapshot();
    // 进入主界面后异步执行 Fenfa 更新检查；公告由首页 Focus 加载。
    // 不阻塞登录与首页渲染；Fenfa 不可用时静默降级。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(RecentScheduleRepository.instance.refresh());
      if (mounted) unawaited(_runStartupChecksAndRequestHomePermissions());
    });
  }

  Future<void> _runStartupChecksAndRequestHomePermissions() async {
    await _runStartupChecks();
    if (!mounted) return;
    await hostPermissionService.requestInitialHomePermissions(
      presentPurpose:
          (purpose) => presentHostPermissionPurpose(context, purpose),
    );
    await _requestTimeReminderPermissions();
    if (mounted) {
      setState(() => _startupReady = true);
      _handleAppLaunch();
      // The first reconciliation is deliberately scheduled after the primary
      // UI and its startup permission flow are usable. It only reads the
      // host-owned, account-scoped data contract.
      unawaited(TimeReminderService.refreshAll());
    }
  }

  bool _requestingReminderPermissions = false;
  Future<void> _requestTimeReminderPermissions() async {
    if (_requestingReminderPermissions) return;
    _requestingReminderPermissions = true;
    try {
      if (mounted &&
          await AuthService.getCurrentAccount() != null &&
          TimeReminderService.isSupported &&
          await PrivacyAgreementService.isAccepted()) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('time_reminders.v2.permission_prompted') != true) {
          await prefs.setBool('time_reminders.v2.permission_prompted', true);
          await hostPermissionService.requestNotificationPermission(
            presentPurpose:
                (purpose) => presentHostPermissionPurpose(context, purpose),
          );
          if (mounted &&
              PlatformCompatibilityService.isAndroid &&
              (await TimeReminderService.status()).notifications &&
              !(await TimeReminderService.status()).exact) {
            await PlatformCompatibilityService.openExactAlarmSettings();
          }
        }
      }
    } catch (error) {
      AppLogger.warn('时间提醒权限初始化失败 (${error.runtimeType})');
    } finally {
      _requestingReminderPermissions = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    academicScheduleCapability.handleAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      _syncDesktopWidgetSnapshot();
      _restoreCampusSessionAfterResume();
      // Refresh local reminder candidates on a foreground opportunity.
      unawaited(TimeReminderService.refreshAll());
    }
  }

  void _restoreCampusSessionAfterResume() {
    if (_resumeSessionCheck != null) return;
    final check = _runCampusSessionRestoreAfterResume();
    _resumeSessionCheck = check;
    unawaited(
      check.whenComplete(() {
        if (identical(_resumeSessionCheck, check)) {
          _resumeSessionCheck = null;
        }
      }),
    );
  }

  Future<void> _runCampusSessionRestoreAfterResume() async {
    await HostAuthCoordinator.check();
    if (mounted) AuthenticatedWebViewCapability.notifyAppResumed();
    if (mounted && !HostAuthState.snapshot.value.blocksRequests) {
      await RecentScheduleRepository.instance.refresh();
    }
  }

  Future<void> _runStartupChecks() async {
    await presentFenfaStartupCheck(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NavigationLayoutService.revision.removeListener(_reloadTabs);
    HostAuthState.snapshot.removeListener(_onAuthSnapshotChanged);
    appCatalogNotifier.removeListener(_reloadTabs);
    AppLaunchService.revision.removeListener(_handleAppLaunch);
    RootNavigationService.revision.removeListener(_handleRootNavigationRequest);
    TemporalChangeService.revision.removeListener(_handleTemporalChange);
    AcademicScheduleStore.revision.removeListener(_syncDesktopWidgetSnapshot);
    RecentScheduleRepository.instance.revision.removeListener(
      _onRecentScheduleChanged,
    );
    super.dispose();
  }

  void _handleTemporalChange() {
    if (mounted) setState(() {});
  }

  void _onRecentScheduleChanged() {
    if (!mounted) return;
    _syncDesktopWidgetSnapshot();
    unawaited(_refreshRecentAlerts());
  }

  Future<void> _refreshRecentAlerts() async {
    if (!await PrivacyAgreementService.isAccepted()) return;
    final key = (await AuthService.getCurrentAccount())?.accountKey;
    if (key != null && mounted) await refreshRecentCourseAlerts(key);
  }

  void _syncDesktopWidgetSnapshot() {
    unawaited(DesktopWidgetSyncService.refresh());
  }

  void _handleRootNavigationRequest() {
    if (_tabs.isEmpty) return;
    final pendingId = RootNavigationService.pendingTabId;
    final pendingTarget =
        pendingId == null
            ? null
            : _tabs.where((tab) => tab.key == pendingId).firstOrNull;
    if (pendingTarget == null) return;
    final targetId = RootNavigationService.takePendingTab();
    if (targetId == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _tabs.where((tab) => tab.key == targetId).firstOrNull;
      if (target == null) return;
      setState(() {
        _pages[target.key] ??= target.builder(context);
        _currentKey = target.key;
      });
    });
  }

  void _handleAppLaunch() {
    // Keep a cold-start request pending until the root protocol/auth shell is ready.
    if (!_startupReady ||
        HostAuthState.snapshot.value.status == HostAuthStatus.checking) {
      return;
    }
    final reminder = AppLaunchService.takePendingReminder();
    if (reminder != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openTimeReminder(reminder));
      });
      return;
    }
    final widgetRequest = AppLaunchService.takePendingWidgetLaunchRequest();
    if (widgetRequest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openDesktopWidgetTarget(widgetRequest));
      });
      return;
    }
    final targetId = AppLaunchService.takePendingTarget();
    if (targetId == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(openTargetId(context, targetId));
    });
  }

  Future<void> _openTimeReminder(Map payload) async {
    try {
      if (!await TimeReminderService.acceptsLaunch(payload) || !mounted) return;
      await openTargetId(
        context,
        payload['targetAppId'] as String,
        appPageBuilder:
            payload['category'] == 'deadline'
                ? (_) => const PortalPersonalPage(initialTabIndex: 1)
                : null,
      );
    } catch (_) {
      /* Invalid/stale notification must never navigate. */
    }
  }

  Future<void> _openDesktopWidgetTarget(String request) async {
    final launch = DesktopWidgetLaunchRequestV1.tryDecode(request);
    if (!mounted || launch?.targetId != AcademicScheduleCapability.targetId) {
      return;
    }
    await openTargetId(context, launch!.targetId);
  }

  void _onAuthSnapshotChanged() {
    if (!mounted) return;
    _handleAppLaunch();
    final owner = HostAuthState.snapshot.value.accountKey;
    final ownerChanged = _accountKey != owner;
    final revision = HostAuthState.snapshot.value.contentRevision;
    final contentChanged = revision != _authContentRevision;
    _authContentRevision = revision;
    setState(() {
      if (_accountKey != owner) {
        for (final key in [
          NavigationLayoutService.hostHomeKey,
          NavigationLayoutService.hostProfileKey,
        ]) {
          _pages.remove(key);
          if (_currentKey == key) _pages[key] = _tabFor(key)?.builder(context);
        }
      }
      _accountKey = owner;
    });
    if ((ownerChanged || contentChanged) && owner != null) {
      unawaited(RecentScheduleRepository.instance.refresh());
      unawaited(_requestTimeReminderPermissions());
      unawaited(TimeReminderService.refreshAll());
    }
  }

  Future<void> _reloadTabs() async {
    final layout = await NavigationLayoutService.read();
    final tabs = <_NavTab>[];
    for (final key in NavigationLayoutService.resolveTabKeys(layout)) {
      final tab = _tabFor(key);
      if (tab != null) tabs.add(tab);
    }
    if (tabs.isEmpty) {
      tabs.addAll(_defaultTabs());
    }
    if (!mounted) return;
    setState(() {
      _accountKey = HostAuthState.snapshot.value.accountKey;
      _tabs = tabs;
      if (!tabs.any((tab) => tab.key == _currentKey)) {
        _currentKey = NavigationLayoutService.hostHomeKey;
      }
      // 启动时立即构建当前 Tab，避免底栏已出现但页面空白。
      final current = tabs.where((tab) => tab.key == _currentKey).firstOrNull;
      if (current != null) {
        _pages[_currentKey] ??= current.builder(context);
      }
    });
    _syncDesktopWidgetSnapshot();
    _handleRootNavigationRequest();
  }

  _NavTab? _tabFor(String key) {
    switch (key) {
      case NavigationLayoutService.hostHomeKey:
        return _NavTab(
          key: key,
          role: AdaptiveNavigationRole.home,
          label: '首页',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          builder:
              (_) => HomePage(
                deviceFamilyOverride: widget.deviceFamilyOverride,
                windowClassOverride: widget.windowClassOverride,
              ),
        );
      case NavigationLayoutService.hostAppsKey:
        return _NavTab(
          key: key,
          role: AdaptiveNavigationRole.apps,
          label: '功能',
          icon: Icons.apps_outlined,
          selectedIcon: Icons.apps,
          builder: (_) => const AppsPage(),
        );
      case NavigationLayoutService.hostMapKey:
        return _NavTab(
          key: key,
          role: AdaptiveNavigationRole.map,
          label: '地图',
          icon: Icons.map_outlined,
          selectedIcon: Icons.map,
          builder: (_) => campusMapCapability.createPage(asRootTab: true),
        );
      case NavigationLayoutService.academicScheduleKey:
        return _NavTab(
          key: key,
          role: AdaptiveNavigationRole.custom,
          label: academicScheduleCapability.navigationLabel,
          icon: academicScheduleCapability.icon,
          selectedIcon: academicScheduleCapability.icon,
          builder: (_) => academicScheduleCapability.createPage(),
        );
      case NavigationLayoutService.hostProfileKey:
        return _NavTab(
          key: key,
          role: AdaptiveNavigationRole.profile,
          label: '我的',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          builder: (_) => ProfilePage(onSignedOut: widget.onSignedOut),
        );
    }
    final plugin = AppRegistry.publishedById(key);
    if (plugin != null &&
        plugin.metadata.showInNavigation &&
        !plugin.metadata.core &&
        plugin.pageBuilder != null &&
        AppService.isVisibleInCurrentMode(plugin)) {
      return _NavTab(
        key: key,
        role: AdaptiveNavigationRole.custom,
        label: plugin.metadata.navigationLabel ?? plugin.metadata.name,
        icon: plugin.metadata.icon,
        selectedIcon: plugin.metadata.icon,
        builder:
            (context) =>
                plugin.requiresCampusAccount
                    ? CampusAuthBoundary(
                      title: plugin.metadata.name,
                      retainGuestShell: plugin.retainsGuestShell,
                      builder: plugin.pageBuilder!,
                    )
                    : plugin.pageBuilder!(context),
      );
    }
    return null;
  }

  List<_NavTab> _defaultTabs() {
    return [
      for (final key in [
        NavigationLayoutService.hostHomeKey,
        NavigationLayoutService.hostAppsKey,
        NavigationLayoutService.academicScheduleKey,
        NavigationLayoutService.hostMapKey,
        NavigationLayoutService.hostProfileKey,
      ])
        if (_tabFor(key) case final tab?) tab,
    ];
  }

  void _selectTab(int index) {
    final tab = _tabs[index];
    setState(() {
      _pages[tab.key] ??= tab.builder(context);
      _currentKey = tab.key;
    });
  }

  int get _selectedIndex {
    if (_tabs.isEmpty) return 0;
    final index = _tabs.indexWhere((tab) => tab.key == _currentKey);
    return index < 0 ? 0 : index;
  }

  Widget _buildIndexedPages() {
    final selectedIndex = _selectedIndex;
    return IndexedStack(
      index: selectedIndex,
      children: [
        for (var index = 0; index < _tabs.length; index++)
          // Only the visible root destination may contribute navigation-bar
          // heroes. Inactive IndexedStack pages remain alive, but cannot be
          // mistaken for the source/destination when tabs change.
          HeroMode(
            enabled: index == selectedIndex,
            child: RootDestinationActiveScope(
              active: index == selectedIndex,
              child: KeyedSubtree(
                // Evict private root-page state immediately on owner changes.
                key: ValueKey(
                  _tabs[index].key == NavigationLayoutService.hostHomeKey ||
                          _tabs[index].key ==
                              NavigationLayoutService.hostProfileKey
                      ? '${_tabs[index].key}:${_accountKey ?? 'guest'}'
                      : _tabs[index].key,
                ),
                child: _pages[_tabs[index].key] ?? const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_startupReady && _currentKey == NavigationLayoutService.hostHomeKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_maybeStartOnboardingFlow());
      });
    }
    return AdaptiveRootNavigation(
      items: [
        for (final tab in _tabs)
          AdaptiveNavigationItem(
            role: tab.role,
            label: tab.label,
            icon: tab.icon,
            selectedIcon: tab.selectedIcon,
          ),
      ],
      selectedIndex: _selectedIndex,
      onSelected: _selectTab,
      deviceFamilyOverride: widget.deviceFamilyOverride,
      windowClassOverride: widget.windowClassOverride,
      child: _buildIndexedPages(),
    );
  }

  bool get _canShowCampusPrompt =>
      mounted &&
      _startupReady &&
      _accountKey != null &&
      _currentKey == NavigationLayoutService.hostHomeKey &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _maybeStartOnboardingFlow() async {
    if (_onboardingFlowAttempted ||
        _onboardingFlowRunning ||
        !_canShowCampusPrompt) {
      return;
    }
    _onboardingFlowAttempted = true;
    _onboardingFlowRunning = true;
    try {
      await _maybeShowCampusPrompt();
      if (!mounted || !_canShowCampusPrompt) return;
      final shouldShow = await _guidePreferences.shouldShowOnboardingFlow();
      if (!mounted || !shouldShow || !_canShowCampusPrompt) return;
      await OnboardingFlowService.start(
        includeSchedule: _tabs.any(
          (tab) => tab.key == NavigationLayoutService.academicScheduleKey,
        ),
      );
    } finally {
      _onboardingFlowRunning = false;
    }
  }

  Future<void> _maybeShowCampusPrompt() async {
    if (_campusPromptAttempted ||
        _campusPromptRunning ||
        !_canShowCampusPrompt) {
      return;
    }
    _campusPromptAttempted = true;
    _campusPromptRunning = true;
    try {
      final shouldShow = await _guidePreferences.shouldShowCampusPrompt();
      if (!mounted || !shouldShow || !_canShowCampusPrompt) return;
      final accountKey = _accountKey;
      if (accountKey == null) return;
      try {
        final storedCampus = await campusSettingsService.readStored();
        if (!mounted || !_canShowCampusPrompt) return;
        if (storedCampus == null) {
          await _showCampusSelection(accountKey);
        }
      } catch (_) {
        // An unavailable campus store should not block the home screen.
      }
      await _guidePreferences.markCampusPromptSeen();
    } finally {
      _campusPromptRunning = false;
    }
  }

  Future<void> _showCampusSelection(String accountKey) async {
    Widget buildPanel(BuildContext dialogContext) {
      return CampusSelectionPanel(
        title: '选择常用校区',
        message: '首页信息、课表上课时间和地图默认校区会根据校区设置变化。',
        note: '之后也可以在“我的 → 校区设置”中修改。',
        saveLabel: '保存并继续',
        skipLabel: '暂不设置',
        onSaved: (_) => Navigator.of(dialogContext).pop(),
        onSkipped: () => Navigator.of(dialogContext).pop(),
        onClosed: () => Navigator.of(dialogContext).maybePop(),
      );
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 280,
                maxWidth: 560,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
              ),
              child: buildPanel(dialogContext),
            ),
          ),
    );
  }
}

class _NavTab {
  final String key;
  final AdaptiveNavigationRole role;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;

  const _NavTab({
    required this.key,
    required this.role,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });
}
