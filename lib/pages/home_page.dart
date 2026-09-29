import 'dart:async';

import 'package:flutter/material.dart';

import '../models/account.dart';
import '../apps/academic_calendar/academic_calendar_models.dart';
import '../apps/academic_calendar/academic_calendar_service.dart';
import '../apps/app.dart';
import '../apps/app_service.dart';
import '../apps/information_portal/information_portal_service.dart';
import '../apps/portal_notices/mobile_campus_notice_service.dart';
import '../services/portal_identity_service.dart';
import '../services/app_remote_services_service.dart';
import '../services/auth_service.dart';
import '../services/credential_sync_service.dart';
import '../services/home_layout_service.dart';
import '../services/home_focus_service.dart';
import '../services/in_app_notification_service.dart';
import '../services/logger_service.dart';
import '../services/weather_service.dart';
import '../services/campus_settings_service.dart';
import '../services/demo_data_service.dart';
import '../services/temporal_change_service.dart';
import '../services/platform_environment.dart';
import '../capabilities/east8_time.dart';
import '../capabilities/alert_center.dart';
import '../capabilities/dev_visibility.dart';
import '../capabilities/academic_schedule/academic_schedule_capability.dart';
import '../capabilities/academic_schedule/academic_schedule_store.dart';
import '../capabilities/desktop_widgets/desktop_widget_bridge.dart';
import '../capabilities/public_holidays/public_holidays.dart';
import '../capabilities/skeleton_block.dart';
import 'home_focus_section.dart';
import 'app_sheet.dart';
import 'notifications_page.dart';
import 'quick_apps_editor_sheet.dart';
import '../widgets/feature_icon_tile.dart';

const _quickAppsColumns = 4;
const _quickAppsSpacing = 12.0;
const _quickAppsRunSpacing = 16.0;

String _academicTeachingWeekLabel(String term, int week) => '$term · 第$week周';

double _quickAppItemWidth(double maxWidth) {
  return (maxWidth - _quickAppsSpacing * (_quickAppsColumns - 1)) /
      _quickAppsColumns;
}

class HomePage extends StatefulWidget {
  final DeviceFamily? deviceFamilyOverride;
  final WindowClass? windowClassOverride;
  final PublicHolidayProvider? publicHolidayProvider;

  const HomePage({
    super.key,

    this.deviceFamilyOverride,
    this.windowClassOverride,
    this.publicHolidayProvider,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Account? _account;
  List<AppDefinition> _quickAppCandidates = [];
  List<String> _recentIds = [];
  QuickAppsConfig _quickAppsConfig = const QuickAppsConfig();
  HomeFocusSnapshot? _homeFocus;
  bool _homeFocusLoading = true;
  int _bootstrapGeneration = 0;
  int _homeFocusGeneration = 0;
  int _weatherGeneration = 0;
  int _teachingWeekGeneration = 0;
  int _unreadGeneration = 0;
  int _quickAppsGeneration = 0;
  bool _loading = true;
  bool _teachingWeekLoading = true;
  bool _weatherLoading = true;
  AcademicCalendarState? _academicCalendarState;
  CurrentTeachingWeek? get _teachingWeek =>
      _academicCalendarState?.teachingWeek;
  String? get _teachingWeekTerm {
    final state = _academicCalendarState;
    return state == null ? null : state.teachingWeek?.term ?? state.term;
  }

  int? get _teachingCalendarWeek =>
      _academicCalendarState?.teachingWeek?.week ??
      _academicCalendarState?.calendarWeek;
  bool get _isAcademicHoliday => _academicCalendarState?.isHoliday ?? false;
  int _unreadCount = 0;
  WeatherInfo? _weather;
  Timer? _focusRefreshTimer;
  late final PublicHolidayProvider _publicHolidayProvider;
  PublicHolidayRevisionSource? _publicHolidayRevisionSource;

  @override
  void initState() {
    super.initState();
    _publicHolidayProvider =
        widget.publicHolidayProvider ?? PublicHolidayCapability();
    final revisionSource = _publicHolidayProvider;
    if (revisionSource is PublicHolidayRevisionSource) {
      final source = revisionSource as PublicHolidayRevisionSource;
      _publicHolidayRevisionSource = source;
      source.revision.addListener(_onPublicHolidayRevision);
    }
    appCatalogNotifier.addListener(_onQuickAppsSourceChanged);
    HomeLayoutService.revision.addListener(_onQuickAppsSourceChanged);
    CredentialSyncService.statusNotifier.addListener(_onCredentialSyncChanged);
    InAppNotificationService.revision.addListener(_loadUnread);
    InAppNotificationService.revision.addListener(
      _onHomeFocusNotificationRevision,
    );
    AlertSubscriptionStore.revision.addListener(_onAlertSubscriptionChanged);
    MobileCampusNoticeService.noticesRevision.addListener(_onHomeFocusRevision);
    AppRemoteServicesService.revision.addListener(_onHomeFocusRevision);
    CampusSettingsService.revision.addListener(_onCampusSettingsChanged);
    TemporalChangeService.revision.addListener(_onTemporalChange);
    DemoDataService.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _bootstrapGeneration++;
    _homeFocusGeneration++;
    _weatherGeneration++;
    _teachingWeekGeneration++;
    _unreadGeneration++;
    _quickAppsGeneration++;
    _publicHolidayRevisionSource?.revision.removeListener(
      _onPublicHolidayRevision,
    );
    appCatalogNotifier.removeListener(_onQuickAppsSourceChanged);
    HomeLayoutService.revision.removeListener(_onQuickAppsSourceChanged);
    CredentialSyncService.statusNotifier.removeListener(
      _onCredentialSyncChanged,
    );
    InAppNotificationService.revision.removeListener(_loadUnread);
    InAppNotificationService.revision.removeListener(
      _onHomeFocusNotificationRevision,
    );
    AlertSubscriptionStore.revision.removeListener(_onAlertSubscriptionChanged);
    MobileCampusNoticeService.noticesRevision.removeListener(
      _onHomeFocusRevision,
    );
    AppRemoteServicesService.revision.removeListener(_onHomeFocusRevision);
    CampusSettingsService.revision.removeListener(_onCampusSettingsChanged);
    TemporalChangeService.revision.removeListener(_onTemporalChange);
    DemoDataService.revision.removeListener(_load);
    _focusRefreshTimer?.cancel();
    if (widget.publicHolidayProvider == null) {
      final provider = _publicHolidayProvider;
      if (provider is PublicHolidayCapability) provider.close();
    }
    super.dispose();
  }

  void _onPublicHolidayRevision() {
    if (!mounted) return;
    unawaited(_loadHomeFocus(evaluateAlerts: false));
  }

  void _onHomeFocusRevision() {
    unawaited(_loadHomeFocus(evaluateAlerts: false));
  }

  void _onHomeFocusNotificationRevision() {
    // Notification revisions are real source events. Bypass the HomeFocus
    // source cache so a published, read, or resolved item is reflected now.
    unawaited(_loadHomeFocus(force: true, evaluateAlerts: false));
  }

  void _onAlertSubscriptionChanged() {
    unawaited(_loadHomeFocus(force: true, evaluateAlerts: false));
  }

  void _onCampusSettingsChanged() {
    unawaited(_loadWeather());
  }

  void _onTemporalChange() {
    // The home page stays alive in the root IndexedStack, so a date change
    // must explicitly invalidate both the teaching-week header and Focus.
    unawaited(_refreshHomeForTemporalChange());
  }

  Future<void> _refreshHomeForTemporalChange() async {
    // Refresh the shared calendar first so the header and schedule module
    // render the same day and teaching week.
    await _refreshTeachingWeek(force: true);
    if (!mounted) return;
    await _loadHomeFocus(force: true, evaluateAlerts: false);
  }

  Future<void> _loadUnread() async {
    final generation = ++_unreadGeneration;
    String? accountKey;
    try {
      final account = await AuthService.getCurrentAccount();
      if (!_isCurrentRequest(generation, _unreadGeneration)) {
        return;
      }
      accountKey = account?.accountKey ?? 'anonymous';
      if (accountKey != (_account?.accountKey ?? 'anonymous')) return;
      final unread =
          account == null
              ? 0
              : await InAppNotificationService.unreadCount(account.accountKey);
      if (!_isCurrentRequest(generation, _unreadGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      setState(() => _unreadCount = unread);
    } catch (error) {
      if (!_isCurrentRequest(generation, _unreadGeneration) ||
          (accountKey != null &&
              accountKey != (_account?.accountKey ?? 'anonymous'))) {
        return;
      }
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.notifications.unread.failed',
        message: '首页未读通知数量加载失败',
        error: error,
        domain: 'home',
        fields: const {'stage': 'unread'},
      );
    }
  }

  void _onCredentialSyncChanged() {
    if (!CredentialSyncService.statusNotifier.value.isSyncing) {
      _load();
    }
  }

  CredentialSyncState? _visibleCredentialSyncState(CredentialSyncState state) {
    if (_account == null ||
        state.accountKey != _account!.accountKey ||
        state.sessionRevision != AuthService.sessionRevision ||
        (!state.isSyncing && !state.hasError)) {
      return null;
    }
    return state;
  }

  bool _isCurrentRequest(int generation, int currentGeneration) {
    return mounted && generation == currentGeneration;
  }

  Future<void> _load() async {
    final generation = ++_bootstrapGeneration;
    late final int quickAppsGeneration;
    var accountChanged = false;
    try {
      final account = await AuthService.getCurrentAccount();
      if (!_isCurrentRequest(generation, _bootstrapGeneration)) {
        return;
      }
      final accountKey = account?.accountKey ?? 'anonymous';
      accountChanged = _account?.accountKey != account?.accountKey;
      if (accountChanged) {
        _focusRefreshTimer?.cancel();
        _focusRefreshTimer = null;
        _homeFocusGeneration++;
        _weatherGeneration++;
        _teachingWeekGeneration++;
        _unreadGeneration++;
        setState(() {
          _account = account;
          _quickAppCandidates = [];
          _recentIds = [];
          _quickAppsConfig = const QuickAppsConfig();
          _homeFocus = null;
          _homeFocusLoading = true;
          _weather = null;
          _weatherLoading = true;
          _academicCalendarState = null;
          _teachingWeekLoading = true;
          _unreadCount = 0;
          _loading = true;
        });
      }
      quickAppsGeneration = ++_quickAppsGeneration;
      final projection = await AppService.loadQuickAppsProjection(accountKey);
      if (!_isCurrentRequest(generation, _bootstrapGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      setState(() {
        _account = account;
        if (quickAppsGeneration == _quickAppsGeneration) {
          _quickAppCandidates = projection.candidates;
          _quickAppsConfig = projection.config;
          _recentIds = projection.recentIds;
        }
        _loading = false;
      });
      if (accountChanged) unawaited(_loadUnread());
      // This bootstrap warm-up also evaluates account-scoped Portal Personal
      // alerts. Demo mode must not read a real account's personal data.
      if (!DemoDataService.instance.enabled) {
        unawaited(_preloadPortalPersonalData());
      }
      await _refreshTeachingWeek();
      if (!_isCurrentRequest(generation, _bootstrapGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      if (account != null &&
          !PortalIdentityService.hasDisplayName(account.name)) {
        unawaited(_refreshAccountName(account, generation));
      }
      unawaited(_loadHomeFocus());
      unawaited(_loadWeather());
    } catch (error) {
      if (!_isCurrentRequest(generation, _bootstrapGeneration)) {
        return;
      }
      AppLogger.recordSafeFailure(
        code: 'home.bootstrap.failed',
        message: '首页基础数据加载失败',
        error: error,
        domain: 'home',
        fields: const {'stage': 'bootstrap'},
      );
      setState(() {
        _loading = false;
        if (accountChanged) {
          _homeFocusLoading = false;
          _weatherLoading = false;
          _teachingWeekLoading = false;
        }
      });
    }
  }

  Future<void> _preloadPortalPersonalData() async {
    try {
      await PortalApiService().fetchPersonalData();
    } catch (error) {
      // 后台预热失败不阻塞首页；打开“个人数据”页时会自行重试。
      if (!mounted) return;
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.personal.preload.failed',
        message: '首页个人数据预热失败',
        error: error,
        domain: 'home',
        fields: const {'stage': 'preload'},
      );
    }
  }

  Future<void> _loadHomeFocus({
    bool force = false,
    bool evaluateAlerts = true,
  }) async {
    final generation = ++_homeFocusGeneration;
    String? accountKey;
    if (mounted) setState(() => _homeFocusLoading = true);
    try {
      final account = await AuthService.getCurrentAccount();
      if (!_isCurrentRequest(generation, _homeFocusGeneration)) {
        return;
      }
      accountKey = account?.accountKey;
      if (accountKey == null) {
        setState(() {
          _homeFocus = HomeFocusSnapshot(items: [], fetchedAt: east8Now());
          _homeFocusLoading = false;
        });
        _focusRefreshTimer?.cancel();
        _focusRefreshTimer = null;
        return;
      }
      if (accountKey != (_account?.accountKey ?? 'anonymous')) return;
      final snapshot = await HomeFocusService(
        publicHolidayProvider: _publicHolidayProvider,
      ).load(accountKey, force: force, evaluateAlerts: evaluateAlerts);
      if (!_isCurrentRequest(generation, _homeFocusGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      setState(() {
        _homeFocus = snapshot;
        _homeFocusLoading = false;
      });
      _scheduleFocusRefresh(snapshot.nextRefreshAt);
    } catch (error) {
      if (!_isCurrentRequest(generation, _homeFocusGeneration) ||
          (accountKey != null &&
              accountKey != (_account?.accountKey ?? 'anonymous'))) {
        return;
      }
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.focus.unexpected_failed',
        message: '首页焦点加载失败',
        error: error,
        domain: 'home',
        fields: const {'stage': 'page'},
      );
      final previous = _homeFocus;
      setState(() {
        _homeFocus = HomeFocusSnapshot(
          items: previous?.items ?? const [],
          fetchedAt: previous?.fetchedAt ?? east8Now(),
          hasError: true,
          nextRefreshAt: previous?.nextRefreshAt,
        );
        _homeFocusLoading = false;
      });
    }
  }

  void _scheduleFocusRefresh(DateTime? nextRefreshAt) {
    _focusRefreshTimer?.cancel();
    _focusRefreshTimer = null;
    if (nextRefreshAt == null) return;
    final delay = nextRefreshAt.difference(east8Now());
    if (delay <= Duration.zero) {
      Timer.run(() {
        if (!mounted) return;
        unawaited(_loadHomeFocus(force: true, evaluateAlerts: false));
      });
      return;
    }
    _focusRefreshTimer = Timer(delay, () {
      _focusRefreshTimer = null;
      if (!mounted) return;
      unawaited(_loadHomeFocus(force: true, evaluateAlerts: false));
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([
      _loadHomeFocus(force: true),
      _loadUnread(),
      _refreshTeachingWeek(),
      _loadWeather(),
      _reloadQuickAppsProjection(),
    ]);
  }

  void _onQuickAppsSourceChanged() {
    unawaited(_reloadQuickAppsProjection());
  }

  Future<void> _reloadQuickAppsProjection() async {
    final generation = ++_quickAppsGeneration;
    String? accountKey;
    try {
      final account = await AuthService.getCurrentAccount();
      if (!_isCurrentRequest(generation, _quickAppsGeneration)) {
        return;
      }
      accountKey = account?.accountKey ?? 'anonymous';
      if (accountKey != (_account?.accountKey ?? 'anonymous')) return;
      final projection = await AppService.loadQuickAppsProjection(accountKey);
      if (!_isCurrentRequest(generation, _quickAppsGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      setState(() {
        _quickAppCandidates = projection.candidates;
        _quickAppsConfig = projection.config;
        _recentIds = projection.recentIds;
      });
    } catch (error) {
      if (!_isCurrentRequest(generation, _quickAppsGeneration) ||
          (accountKey != null &&
              accountKey != (_account?.accountKey ?? 'anonymous'))) {
        return;
      }
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.quick_apps.failed',
        message: '首页常用应用加载失败',
        error: error,
        domain: 'home',
        fields: const {'stage': 'quick_apps_projection'},
      );
    }
  }

  Future<void> _loadWeather() async {
    final generation = ++_weatherGeneration;
    String? accountKey;
    try {
      final account = await AuthService.getCurrentAccount();
      if (!_isCurrentRequest(generation, _weatherGeneration)) {
        return;
      }
      accountKey = account?.accountKey ?? 'anonymous';
      if (accountKey != (_account?.accountKey ?? 'anonymous')) return;
      if (mounted) setState(() => _weatherLoading = true);
      final campus = await campusSettingsService.selectedCampus(accountKey);
      if (!_isCurrentRequest(generation, _weatherGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      final center = campus?.initialCenter;
      if (campus == null || center == null) {
        setState(() {
          _weather = null;
          _weatherLoading = false;
        });
        return;
      }
      final weather = await WeatherService().fetchWeather(
        campusId: campus.campusId,
        city: campus.displayName,
        latitude: center.latitude,
        longitude: center.longitude,
      );
      if (!_isCurrentRequest(generation, _weatherGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      setState(() {
        _weatherLoading = false;
        _weather = weather;
      });
    } catch (error) {
      if (!_isCurrentRequest(generation, _weatherGeneration) ||
          (accountKey != null &&
              accountKey != (_account?.accountKey ?? 'anonymous'))) {
        return;
      }
      setState(() => _weatherLoading = false);
      // 天气为非关键信息：获取失败时静默隐藏，下拉刷新会重试。
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.weather.failed',
        message: '首页天气加载失败',
        error: error,
        domain: 'home',
        fields: const {'source': 'weather'},
      );
    }
  }

  Future<void> _refreshTeachingWeek({bool force = false}) async {
    final generation = ++_teachingWeekGeneration;
    if (mounted) {
      setState(() {
        _teachingWeekLoading = true;
        _academicCalendarState = null;
      });
    }
    String? accountKey;
    try {
      final account = await AuthService.getCurrentAccount();
      if (!_isCurrentRequest(generation, _teachingWeekGeneration)) return;
      accountKey = account?.accountKey ?? 'anonymous';
      if (accountKey != (_account?.accountKey ?? 'anonymous')) {
        if (mounted && _isCurrentRequest(generation, _teachingWeekGeneration)) {
          setState(() => _teachingWeekLoading = false);
        }
        return;
      }
      final calendarService = AcademicCalendarService();
      final snapshot = await calendarService.fetchCurrentCalendarState(
        force: force,
      );
      if (!_isCurrentRequest(generation, _teachingWeekGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      final schedule = await AcademicScheduleStore().readCachedCurrentSchedule(
        accountKey,
      );
      if (schedule != null && schedule.semesterLabel.trim().isNotEmpty) {
        try {
          await calendarService.ensureTermStartDateForSemester(
            schedule.semesterLabel,
          );
        } catch (error) {
          AppLogger.recordSafeFailure(
            level: 'WARN',
            code: 'home.widget_calendar.resolve.failed',
            message: '桌面小组件学期日期解析失败',
            error: error,
            domain: 'home',
            fields: const {'stage': 'widget_term_start'},
          );
        }
      }
      if (!_isCurrentRequest(generation, _teachingWeekGeneration) ||
          accountKey != (_account?.accountKey ?? 'anonymous')) {
        return;
      }
      setState(() {
        _teachingWeekLoading = false;
        _academicCalendarState = snapshot;
      });
      // The initial widget sync may run before the calendar and term directory
      // have finished loading. Publish again now that the schedule's date map
      // is available in the account-scoped cache.
      unawaited(DesktopWidgetSyncService.refresh());
    } catch (error) {
      if (!_isCurrentRequest(generation, _teachingWeekGeneration) ||
          (accountKey != null &&
              accountKey != (_account?.accountKey ?? 'anonymous'))) {
        return;
      }
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.teaching_week.failed',
        message: '首页教学周加载失败',
        error: error,
        domain: 'home',
        fields: const {'source': 'academic.calendar'},
      );
      setState(() => _teachingWeekLoading = false);
    }
  }

  Future<void> _refreshAccountName(
    Account account,
    int bootstrapGeneration,
  ) async {
    try {
      final updated = await PortalIdentityService.refreshAccountName();
      if (!_isCurrentRequest(bootstrapGeneration, _bootstrapGeneration) ||
          updated == null ||
          _account?.accountKey != account.accountKey) {
        return;
      }
      if (updated.name != _account?.name) {
        setState(() => _account = updated);
      }
    } catch (error) {
      if (!_isCurrentRequest(bootstrapGeneration, _bootstrapGeneration) ||
          _account?.accountKey != account.accountKey) {
        return;
      }
      AppLogger.recordSafeFailure(
        level: 'WARN',
        code: 'home.account_name.failed',
        message: '首页账号名称刷新失败',
        error: error,
        domain: 'home',
        fields: const {'stage': 'account_name'},
      );
    }
  }

  String _greeting() {
    final hour = east8Now().hour;
    if (hour >= 6 && hour < 12) return '早上好';
    if (hour >= 12 && hour < 14) return '中午好';
    if (hour >= 14 && hour < 18) return '下午好';
    return '晚上好';
  }

  String _dateLine() {
    final now = _academicCalendarState?.fetchedAt ?? east8Now();
    return '${now.month}月${now.day}日';
  }

  String _weekdayLine() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final now = _academicCalendarState?.fetchedAt ?? east8Now();
    return '星期${weekdays[now.weekday - 1]}';
  }

  List<AppDefinition> _orderedQuickApps() {
    return AppService.orderQuickApps(
      _quickAppCandidates,
      _recentIds,
      _quickAppsConfig,
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
    );
  }

  void _openApp(AppDefinition plugin) {
    openAppDefinition(context, plugin);
  }

  Future<void> _showQuickAppMenu(AppDefinition plugin) async {
    final metadata = plugin.metadata;
    if (!mounted) return;

    final action = await showModalBottomSheet<_QuickAppAction>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(metadata.icon),
                  title: Row(
                    children: [
                      Expanded(child: Text(metadata.name)),
                      if (metadata.requiresDev) ...[
                        const SizedBox(width: 8),
                        const DevBadge(),
                      ],
                    ],
                  ),
                  subtitle: Text(metadata.description),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.space_dashboard_outlined),
                  title: const Text('从首页移除'),
                  onTap:
                      () => Navigator.pop(
                        context,
                        _QuickAppAction.removeFromHome,
                      ),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('查看功能详情'),
                  onTap: () => Navigator.pop(context, _QuickAppAction.details),
                ),
              ],
            ),
          ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _QuickAppAction.removeFromHome:
        await HomeLayoutService.removeQuickApp(
          _account?.accountKey ?? 'anonymous',
          metadata.id,
        );
      case _QuickAppAction.details:
        await showAppDetailSheet(context, plugin);
    }
  }

  Future<void> _showQuickAppsEditor() async {
    await showQuickAppsEditorSheet(
      context,
      accountKey: _account?.accountKey ?? 'anonymous',
    );
  }

  /// 首页固定设计间距：Header → Focus 24~36、Focus → Quick Apps 32~48、
  /// Focus 为空时 Header → Quick Apps 36~56。页面不再把弹性间距塞进模块
  /// 之间，剩余空白自然留在内容之后。
  static const _headerToFocusGap = 28.0;
  static const _focusToAppsGap = 40.0;
  static const _emptyFocusToAppsGap = 44.0;

  Widget _buildHomeFocus() {
    return ValueListenableBuilder<CredentialSyncState>(
      valueListenable: CredentialSyncService.statusNotifier,
      builder: (_, syncState, __) {
        return KeyedSubtree(
          key: const ValueKey('home-focus'),
          child: HomeFocusSection(
            snapshot: _homeFocus,
            loading: _homeFocusLoading,
            credentialSyncState: _visibleCredentialSyncState(syncState),
            onRetry: () => unawaited(_loadHomeFocus(force: true)),
          ),
        );
      },
    );
  }

  Widget _buildHomeBlocks({required List<AppDefinition> quickApps}) {
    if (_loading) return const _HomeActionsSkeleton();
    return KeyedSubtree(
      key: const ValueKey('home-blocks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          academicScheduleCapability.createHomeModule(
            publicHolidayProvider: _publicHolidayProvider,
            calendarState: _academicCalendarState,
            calendarStateLoading: _teachingWeekLoading,
            onRetryCalendarState: () => _refreshTeachingWeek(force: true),
          ),
          if (_quickAppsConfig.enabled) ...[
            const SizedBox(height: 24),
            _QuickAppsSection(
              plugins: quickApps,
              onEdit: _showQuickAppsEditor,
              onTap: _openApp,
              onLongPress: _showQuickAppMenu,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedTabletHome({
    required List<AppDefinition> quickApps,

    required Widget header,
    required bool focusVisible,
  }) {
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              SizedBox(
                height: focusVisible ? _headerToFocusGap : _emptyFocusToAppsGap,
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final focusWidth = (constraints.maxWidth * 0.38).clamp(
                    320.0,
                    460.0,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: focusWidth, child: _buildHomeFocus()),
                      const SizedBox(width: 24),
                      Expanded(child: _buildHomeBlocks(quickApps: quickApps)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    final scrollView = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [SliverToBoxAdapter(child: content)],
    );
    final safeContent = SafeArea(bottom: false, child: scrollView);

    return Scaffold(
      body: RefreshIndicator(onRefresh: _refreshAll, child: safeContent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickApps = _orderedQuickApps();
    final credentialSyncVisible =
        _visibleCredentialSyncState(
          CredentialSyncService.statusNotifier.value,
        ) !=
        null;
    final focusVisible =
        _homeFocusLoading ||
        (_homeFocus?.items.isNotEmpty ?? false) ||
        credentialSyncVisible;

    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
        sliver: SliverList.list(
          children: [
            _GreetingHeader(
              title:
                  _account != null
                      ? '${_greeting()}，${_account!.name}'
                      : _greeting(),
              subtitle: _dateLine(),
              weekday: _weekdayLine(),
              teachingWeek: _teachingWeek,
              teachingWeekTerm: _teachingWeekTerm,
              teachingCalendarWeek: _teachingCalendarWeek,
              isAcademicHoliday: _isAcademicHoliday,
              weather: _weather,
              teachingWeekLoading: _teachingWeekLoading,
              weatherLoading: _weatherLoading,
              unreadCount: _unreadCount,
              onOpenNotifications: _openNotifications,
            ),
            SizedBox(
              height: focusVisible ? _headerToFocusGap : _emptyFocusToAppsGap,
            ),
            _buildHomeFocus(),
            if (focusVisible) const SizedBox(height: _focusToAppsGap),
            _buildHomeBlocks(quickApps: quickApps),
          ],
        ),
      ),
    ];
    final scrollView = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [...slivers],
    );
    final content = SafeArea(
      bottom: false,
      child: RefreshIndicator(onRefresh: _refreshAll, child: scrollView),
    );
    final environment = PlatformEnvironment.fromContext(
      context,

      deviceFamilyOverride: widget.deviceFamilyOverride,
      windowClassOverride: widget.windowClassOverride,
    );
    if (environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass.isExpanded) {
      return _buildExpandedTabletHome(
        quickApps: quickApps,

        header: _GreetingHeader(
          title:
              _account != null
                  ? '${_greeting()}，${_account!.name}'
                  : _greeting(),
          subtitle: _dateLine(),
          weekday: _weekdayLine(),
          teachingWeek: _teachingWeek,
          teachingWeekTerm: _teachingWeekTerm,
          teachingCalendarWeek: _teachingCalendarWeek,
          isAcademicHoliday: _isAcademicHoliday,
          weather: _weather,
          teachingWeekLoading: _teachingWeekLoading,
          weatherLoading: _weatherLoading,
          unreadCount: _unreadCount,
          onOpenNotifications: _openNotifications,
        ),
        focusVisible: focusVisible,
      );
    }

    if (environment.deviceFamily == DeviceFamily.tablet &&
        environment.windowClass == WindowClass.medium) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: content,
          ),
        ),
      );
    }
    return Scaffold(body: content);
  }
}

enum _QuickAppAction { removeFromHome, details }

class _GreetingHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String weekday;
  final CurrentTeachingWeek? teachingWeek;
  final String? teachingWeekTerm;
  final int? teachingCalendarWeek;
  final bool isAcademicHoliday;
  final WeatherInfo? weather;
  final bool teachingWeekLoading;
  final bool weatherLoading;
  final int unreadCount;
  final VoidCallback onOpenNotifications;

  const _GreetingHeader({
    required this.title,
    required this.subtitle,
    required this.weekday,
    this.teachingWeek,
    this.teachingWeekTerm,
    this.teachingCalendarWeek,
    this.isAcademicHoliday = false,
    this.weather,
    this.teachingWeekLoading = false,
    this.weatherLoading = false,
    required this.unreadCount,
    required this.onOpenNotifications,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentWeek = teachingWeek;
    // 板块一不渲染卡片容器：问候区与页面背景一体，只靠字号与间距表达层级。
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              if (currentWeek == null && teachingWeekLoading)
                _TeachingWeekLoadingLines(
                  dateLine: subtitle,
                  weekday: weekday,
                  weather: weather,
                  weatherLoading: weatherLoading,
                )
              else if (currentWeek == null && isAcademicHoliday)
                _AcademicHolidayLines(
                  dateLine: subtitle,
                  weekday: weekday,
                  term: teachingWeekTerm,
                  week: teachingCalendarWeek,
                  weather: weather,
                  weatherLoading: weatherLoading,
                )
              else if (currentWeek == null)
                _SubtitleRow(
                  text: subtitle,
                  weekday: weekday,
                  weather: weather,
                  weatherLoading: weatherLoading,
                )
              else
                CurrentTeachingWeekLines(
                  dateLine: subtitle,
                  weekday: weekday,
                  teachingWeek: currentWeek,
                  weather: weather,
                  weatherLoading: weatherLoading,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '通知',
          onPressed: onOpenNotifications,
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: const Icon(Icons.notifications_outlined),
          ),
        ),
      ],
    );

    return Padding(padding: const EdgeInsets.fromLTRB(4, 6, 4, 0), child: row);
  }
}

/// Renders the date and the current teaching week on separate lines.
class CurrentTeachingWeekLines extends StatelessWidget {
  final String dateLine;
  final String weekday;
  final CurrentTeachingWeek teachingWeek;
  final WeatherInfo? weather;
  final bool weatherLoading;

  const CurrentTeachingWeekLines({
    super.key,
    required this.dateLine,
    required this.weekday,
    required this.teachingWeek,
    this.weather,
    this.weatherLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodyMedium?.copyWith(color: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$dateLine $weekday', style: style),
            if (weather != null) _WeatherText(weather: weather!),
            if (weather == null && weatherLoading)
              const SkeletonBlock(width: 72, height: 14),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _academicTeachingWeekLabel(teachingWeek.term, teachingWeek.week),
          style: style,
        ),
      ],
    );
  }
}

class _AcademicHolidayLines extends StatelessWidget {
  final String dateLine;
  final String weekday;
  final String? term;
  final int? week;
  final WeatherInfo? weather;
  final bool weatherLoading;

  const _AcademicHolidayLines({
    required this.dateLine,
    required this.weekday,
    this.term,
    this.week,
    this.weather,
    this.weatherLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodyMedium?.copyWith(color: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$dateLine $weekday', style: style),
            if (weather != null) _WeatherText(weather: weather!),
            if (weather == null && weatherLoading)
              const SkeletonBlock(width: 72, height: 14),
          ],
        ),
        if (term != null && week != null) ...[
          const SizedBox(height: 2),
          Text(_academicTeachingWeekLabel(term!, week!), style: style),
        ],
      ],
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  final String text;
  final String weekday;
  final WeatherInfo? weather;
  final bool weatherLoading;

  const _SubtitleRow({
    required this.text,
    required this.weekday,
    this.weather,
    this.weatherLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$text $weekday',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        if (weather != null) _WeatherText(weather: weather!),
        if (weather == null && weatherLoading)
          const SkeletonBlock(width: 72, height: 14),
      ],
    );
  }
}

class _TeachingWeekLoadingLines extends StatelessWidget {
  final String dateLine;
  final String weekday;
  final WeatherInfo? weather;
  final bool weatherLoading;

  const _TeachingWeekLoadingLines({
    required this.dateLine,
    required this.weekday,
    this.weather,
    this.weatherLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodyMedium?.copyWith(color: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$dateLine $weekday', style: style),
            if (weather != null) _WeatherText(weather: weather!),
            if (weather == null && weatherLoading)
              const SkeletonBlock(width: 72, height: 14),
          ],
        ),
        const SizedBox(height: 2),
        const SkeletonBlock(width: 140, height: 14),
      ],
    );
  }
}

class _WeatherText extends StatelessWidget {
  final WeatherInfo weather;

  const _WeatherText({required this.weather});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_weatherCampusLabel(weather.city)} · '
          '${weather.temperatureLabel} · ${weather.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 5),
        Icon(
          _weatherIcon(weather.weatherCode),
          size: 16,
          color: colors.onSurfaceVariant,
        ),
      ],
    );
  }
}

String _weatherCampusLabel(String displayName) {
  switch (displayName) {
    case '渭水校区':
      return '渭水';
    case '校本部':
      return '本部';
    case '雁塔校区':
      return '雁塔';
    case '小寨校区':
      return '小寨';
    default:
      return displayName;
  }
}

IconData _weatherIcon(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny_outlined;
  if (code == 2 || code == 3) return Icons.wb_cloudy_outlined;
  if (code == 45 || code == 48) return Icons.cloud_outlined;
  if (code >= 95) return Icons.thunderstorm_outlined;
  if ((code >= 51 && code <= 57) ||
      (code >= 61 && code <= 67) ||
      (code >= 80 && code <= 82)) {
    return Icons.umbrella_outlined;
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return Icons.ac_unit;
  }
  return Icons.thermostat;
}

class _QuickAppsSection extends StatelessWidget {
  final List<AppDefinition> plugins;
  final VoidCallback onEdit;
  final ValueChanged<AppDefinition> onTap;
  final ValueChanged<AppDefinition> onLongPress;

  const _QuickAppsSection({
    required this.plugins,
    required this.onEdit,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '常用功能',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  textStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('编辑'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _QuickAppsGrid(
          plugins: plugins,
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ],
    );
  }
}

class _QuickAppsGrid extends StatelessWidget {
  final List<AppDefinition> plugins;
  final ValueChanged<AppDefinition> onTap;
  final ValueChanged<AppDefinition> onLongPress;

  const _QuickAppsGrid({
    required this.plugins,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (plugins.isEmpty) return const _EmptyQuickApps();
    // 左对齐 + 4 列等分 item 宽度；常规手机宽度下每行 4 项，不足 4 项不拉满。
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = _quickAppItemWidth(constraints.maxWidth);
        return Wrap(
          spacing: _quickAppsSpacing,
          runSpacing: _quickAppsRunSpacing,
          children: [
            for (final plugin in plugins)
              SizedBox(
                width: itemWidth,
                child: _QuickAppTile(
                  plugin: plugin,
                  onTap: () => onTap(plugin),
                  onLongPress: () => onLongPress(plugin),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuickAppTile extends StatelessWidget {
  final AppDefinition plugin;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _QuickAppTile({
    required this.plugin,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return FeatureIconTile(
      metadata: plugin.metadata,

      onTap: onTap,
      onLongPress: onLongPress,
      maxLines: MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 3 : 2,
    );
  }
}

class _EmptyQuickApps extends StatelessWidget {
  const _EmptyQuickApps();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(Icons.apps_outlined, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '暂无常用功能',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionsSkeleton extends StatelessWidget {
  const _HomeActionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBlock(width: 120, height: 18),
        SizedBox(height: 10),
        SkeletonBlock(height: 216, radius: 12),
      ],
    );
  }
}
