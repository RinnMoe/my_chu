import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'capabilities/alert_registry.dart';
import 'capabilities/authenticated_web_view_capability.dart';
import 'pages/apps_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/profile_page.dart';
import 'pages/campus_settings_page.dart';
import 'capabilities/campus_map/campus_map_capability.dart';
import 'capabilities/academic_schedule/academic_schedule_capability.dart';
import 'capabilities/academic_schedule/academic_schedule_store.dart';
import 'capabilities/desktop_widgets/desktop_widget_bridge.dart';
import 'capabilities/desktop_widgets/desktop_widget_models.dart';
import 'apps/app_registry.dart';
import 'apps/app_service.dart';
import 'models/account.dart';
import 'services/auth_service.dart';
import 'services/auth_lifecycle_service.dart';
import 'services/login_required_notifier.dart';
import 'services/logger_service.dart';
import 'services/navigation_layout_service.dart';
import 'services/privacy_agreement_service.dart';
import 'services/usage_analytics_service.dart';
import 'services/live_update_service.dart';
import 'services/host_permission_service.dart';
import 'services/theme_service.dart';
import 'services/app_launch_service.dart';
import 'services/temporal_change_service.dart';
import 'services/root_navigation_service.dart';
import 'services/legacy_session_migration_executor.dart';
import 'services/platform_environment.dart';
import 'services/error_feedback_service.dart';
import 'services/campus_settings_service.dart';
import 'services/guide_preferences.dart';
import 'services/onboarding_flow_service.dart';
import 'theme/app_palette.dart';
import 'pages/fenfa_dialogs.dart';
import 'pages/privacy_agreement_dialog.dart';
import 'pages/app_sheet.dart';
import 'pages/auth_recovery_page.dart';
import 'pages/host_permission_purpose_overlay.dart';
import 'widgets/adaptive_confirmation_dialog.dart';
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
  ensureBuiltInAlertProvidersRegistered();
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

enum _Page { startup, login, recovery, main }

class _AppShellState extends State<AppShell> {
  _Page _page = _Page.startup;
  bool _reloginPromptShowing = false;
  AuthLifecycleResult? _authRecovery;
  int _restoreGeneration = 0;

  ErrorFeedbackCoordinator get _feedbackCoordinator =>
      ErrorFeedbackCoordinator.shared;

  @override
  void initState() {
    super.initState();
    LoginRequiredNotifier.addListener(_onLoginRequired);
    _refresh();
    // 原生启动图在启动页首帧渲染后移除，露出带加载动画的启动页。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FlutterNativeSplash.remove();
    });
  }

  @override
  void dispose() {
    LoginRequiredNotifier.removeListener(_onLoginRequired);
    super.dispose();
  }

  /// 运行期凭证失效也复用启动恢复状态机，避免单独弹出一套登录对话框。
  void _onLoginRequired(String reason) {
    if (!mounted) {
      LoginRequiredNotifier.markPromptDismissed();
      return;
    }
    // 已经在启动、登录或恢复页时，当前流程会处理状态，无需重复恢复。
    if (_page != _Page.main) {
      LoginRequiredNotifier.markPromptDismissed();
      return;
    }
    if (_reloginPromptShowing) {
      LoginRequiredNotifier.markPromptDismissed();
      return;
    }
    _reloginPromptShowing = true;
    LoginRequiredNotifier.markPromptDismissed();
    final generation = ++_restoreGeneration;
    unawaited(_restoreAfterRuntimeExpiry(generation));
  }

  Future<void> _restoreAfterRuntimeExpiry(int generation) async {
    late final AuthLifecycleResult lifecycle;
    try {
      lifecycle = await AuthLifecycleService.retryRestore();
    } catch (error) {
      AppLogger.warn('运行期恢复登录状态失败 (${error.runtimeType})');
      lifecycle = const AuthLifecycleResult(
        status: AuthLifecycleStatus.retryableFailure,
        message: '暂时无法恢复登录状态，请重试。',
      );
    }
    if (!mounted || generation != _restoreGeneration) return;
    _reloginPromptShowing = false;
    if (lifecycle.status == AuthLifecycleStatus.noAccount) {
      _feedbackCoordinator.reset();
      _authRecovery = null;
      if (!await _requirePrivacyAgreement(generation)) return;
      await _showInteractiveLogin(generation);
      return;
    }
    if (!lifecycle.isAuthenticated) {
      _feedbackCoordinator.reset();
      setState(() {
        _authRecovery = lifecycle;
        _page = _Page.recovery;
      });
    }
  }

  Future<void> _refresh() async {
    final generation = ++_restoreGeneration;
    final migration = await SessionMigrationBootstrap.ensure();
    if (!migration.isSuccessful) {
      if (!mounted || generation != _restoreGeneration) return;
      setState(() {
        _authRecovery = const AuthLifecycleResult(
          status: AuthLifecycleStatus.retryableFailure,
          message: '账号会话迁移未完成，请重试。',
        );
        _page = _Page.recovery;
      });
      return;
    }
    late final Account? account;
    try {
      // Read the persisted account locally. Network identity validation and
      // recovery happen on demand through CampusSession after the first frame.
      account = await AuthService.getCurrentAccount();
    } catch (error) {
      AppLogger.warn('启动读取本地登录状态失败 (${error.runtimeType})');
      const lifecycle = AuthLifecycleResult(
        status: AuthLifecycleStatus.retryableFailure,
        message: '暂时无法读取登录状态，请重试。',
      );
      if (!mounted || generation != _restoreGeneration) return;
      _feedbackCoordinator.reset();
      setState(() {
        _authRecovery = lifecycle;
        _page = _Page.recovery;
      });
      return;
    }
    if (!mounted || generation != _restoreGeneration) return;

    if (account == null) {
      _feedbackCoordinator.reset();
      _authRecovery = null;
      if (!await _requirePrivacyAgreement(generation)) return;
      await _showInteractiveLogin(generation);
      return;
    }

    _authRecovery = null;
    await _showMainForPersistedAccount(generation, account.accountKey);
  }

  Future<void> _showMainForPersistedAccount(
    int generation,
    String accountKey,
  ) async {
    if (!mounted || generation != _restoreGeneration) return;

    if (!await _requirePrivacyAgreement(generation)) return;
    if (!mounted || generation != _restoreGeneration) return;
    setState(() {
      _page = _Page.main;
    });
    // Allow the first main-screen frame to render before warming core service
    // sessions. CampusSession owns request-time validation and silent recovery.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _restoreGeneration || _page != _Page.main) {
        return;
      }
      AuthLifecycleService.warmUpPersistedAccount(accountKey);
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
          _page = _Page.startup;
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

  void _onLoginSuccess() {
    _feedbackCoordinator.reset();
    _restoreGeneration++;
    _reloginPromptShowing = false;
    _authRecovery = null;
    setState(() {
      _page = _Page.main;
    });
    LoginRequiredNotifier.resetAfterLogin();
  }

  void _onSignedOut() {
    _feedbackCoordinator.reset();
    unawaited(_refresh());
  }

  void _retryRecovery() {
    setState(() => _page = _Page.startup);
    unawaited(_refresh());
  }

  void _openManualLogin() {
    unawaited(_openManualLoginAfterPrivacyAgreement());
  }

  Future<void> _openManualLoginAfterPrivacyAgreement() async {
    _feedbackCoordinator.reset();
    _restoreGeneration++;
    _reloginPromptShowing = false;
    final generation = _restoreGeneration;
    if (!await _requirePrivacyAgreement(generation)) return;
    await _showInteractiveLogin(generation);
  }

  Future<void> _showInteractiveLogin(int generation) async {
    if (!mounted || generation != _restoreGeneration) return;
    await AuthLifecycleService.prepareInteractiveLogin();
    if (!mounted || generation != _restoreGeneration) return;
    setState(() {
      _page = _Page.login;
    });
  }

  Future<void> _clearLocalAccount() async {
    final confirmation = showAdaptiveConfirmationDialog(
      context,
      title: '清除本地账号',
      message: '这会清除本地登录状态、缓存和已保存的登录信息。',
      confirmLabel: '清除',
      destructive: true,
    );
    final confirmed = await confirmation;
    if (confirmed != true) return;
    _restoreGeneration++;
    _reloginPromptShowing = false;
    _feedbackCoordinator.reset();
    await AuthLifecycleService.signOut();
    if (!mounted) return;
    _authRecovery = null;
    await _openManualLoginAfterPrivacyAgreement();
  }

  @override
  Widget build(BuildContext context) {
    switch (_page) {
      case _Page.startup:
        return const AdaptiveStartupSplash();
      case _Page.login:
        return LoginPage(onLoginSuccess: _onLoginSuccess);
      case _Page.recovery:
        return AuthRecoveryPage(
          result:
              _authRecovery ??
              const AuthLifecycleResult(
                status: AuthLifecycleStatus.retryableFailure,
                message: '暂时无法确认登录状态，请重试。',
              ),
          onRetry: _retryRecovery,
          onManualLogin: _openManualLogin,
          onClearAccount: () => unawaited(_clearLocalAccount()),
        );
      case _Page.main:
        return MainScreen(onSignedOut: _onSignedOut);
    }
  }
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
    appCatalogNotifier.addListener(_reloadTabs);
    AppLaunchService.revision.addListener(_handleAppLaunch);
    RootNavigationService.revision.addListener(_handleRootNavigationRequest);
    TemporalChangeService.revision.addListener(_handleTemporalChange);
    AcademicScheduleStore.revision.addListener(_syncDesktopWidgetSnapshot);
    unawaited(AppLaunchService.initialize());
    _reloadTabs();
    _handleAppLaunch();
    _syncDesktopWidgetSnapshot();
    // 进入主界面后异步执行 Fenfa 更新检查；公告由首页 Focus 加载。
    // 不阻塞登录与首页渲染；Fenfa 不可用时静默降级。
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    if (mounted) {
      setState(() => _startupReady = true);
      // The first reconciliation is deliberately scheduled after the primary
      // UI and its startup permission flow are usable. It only reads the
      // host-owned, account-scoped data contract.
      unawaited(LiveUpdateService.refreshIfEnabled());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    academicScheduleCapability.handleAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      _syncDesktopWidgetSnapshot();
      _restoreCampusSessionAfterResume();
      // ActivityKit has no APNs-backed server in the first release. Reconcile
      // whenever the host gets an execution opportunity again.
      unawaited(LiveUpdateService.refreshIfEnabled(forceRefresh: true));
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
    try {
      final result = await AuthLifecycleService.restoreForResume();
      if (!mounted) return;
      if (result.status == AuthLifecycleStatus.manualLoginRequired ||
          result.status == AuthLifecycleStatus.noAccount) {
        LoginRequiredNotifier.requestRelogin(
          result.recoveryOutcome?.name ?? result.status.name,
        );
        return;
      }
      AuthenticatedWebViewCapability.notifyAppResumed();
    } catch (error) {
      AppLogger.warn('前台恢复校园会话失败 (${error.runtimeType})');
      if (mounted) AuthenticatedWebViewCapability.notifyAppResumed();
    }
  }

  Future<void> _runStartupChecks() async {
    await presentFenfaStartupCheck(context);
    if (!mounted) return;

    final shouldPrompt =
        await LiveUpdateService.shouldPromptPromotionOnStartup();
    if (!mounted || !shouldPrompt) return;

    // Mark before displaying so a dismissed dialog is still one-time.
    await LiveUpdateService.markPromotionStartupPromptShown();
    if (!mounted) return;

    final openSettings = await showAdaptiveConfirmationDialog(
      context,
      title: '开启状态栏实时动态',
      message: 'Android 16.1+ 可以在状态栏显示课程进行中的实时动态。是否前往系统设置，允许 MyCHU 发布推广通知？',
      confirmLabel: '去开启',
      cancelLabel: '暂不',
    );
    if (!mounted || openSettings != true) return;
    try {
      await LiveUpdateService.openPromotionSettings();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法打开系统设置，请稍后从“通知与提醒”进入')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NavigationLayoutService.revision.removeListener(_reloadTabs);
    appCatalogNotifier.removeListener(_reloadTabs);
    AppLaunchService.revision.removeListener(_handleAppLaunch);
    RootNavigationService.revision.removeListener(_handleRootNavigationRequest);
    TemporalChangeService.revision.removeListener(_handleTemporalChange);
    AcademicScheduleStore.revision.removeListener(_syncDesktopWidgetSnapshot);
    super.dispose();
  }

  void _handleTemporalChange() {
    if (mounted) setState(() {});
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

  Future<void> _openDesktopWidgetTarget(String request) async {
    final launch = DesktopWidgetLaunchRequestV1.tryDecode(request);
    if (!mounted || launch?.targetId != AcademicScheduleCapability.targetId) {
      return;
    }
    await openTargetId(context, launch!.targetId);
  }

  Future<void> _reloadTabs() async {
    final account = await AuthService.getCurrentAccount();
    final layout = await NavigationLayoutService.read(
      account?.accountKey ?? 'anonymous',
    );
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
      _accountKey = account?.accountKey;
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
        builder: plugin.pageBuilder!,
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
              child: _pages[_tabs[index].key] ?? const SizedBox.shrink(),
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
        final storedCampus = await campusSettingsService.readStored(accountKey);
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
        accountKey: accountKey,
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
