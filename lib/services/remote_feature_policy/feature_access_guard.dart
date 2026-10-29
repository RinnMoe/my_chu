import '../../apps/app.dart';
import '../../apps/app_service.dart';
import '../development_mode_service.dart';
import 'remote_feature_policy_models.dart';
import 'remote_feature_policy_service.dart';

/// Effective access state for one feature.
enum FeatureAccessStatus {
  /// Usable and listed by ordinary entry points.
  available,

  /// Usable, but the policy asked ordinary entry points to hide it.
  hidden,
  disabled,
  maintenance,

  /// Fail-closed: the local safety level requires a confirmation the client
  /// does not currently have.
  unavailable,
  developmentOnly,
  notInstalled,
  unknownFeature,
}

/// A single, explainable access decision.
class FeatureAccessDecision {
  const FeatureAccessDecision({
    required this.featureId,
    required this.status,
    this.message,
    this.visible = true,
    this.origin = RemoteFeaturePolicyOrigin.localDefault,
  });

  final String featureId;
  final FeatureAccessStatus status;

  /// Policy-provided explanation, or a host default for the status.
  final String? message;
  final bool visible;
  final RemoteFeaturePolicyOrigin origin;

  /// Whether the feature may be opened or executed.
  bool get canLaunch =>
      status == FeatureAccessStatus.available ||
      status == FeatureAccessStatus.hidden;

  /// Whether ordinary entry points (catalog, quick apps, navigation) list it.
  ///
  /// Only the policy's `visible` flag hides an entry. A blocked feature stays
  /// listed so the user can see the maintenance/disabled explanation; operators
  /// who want it gone set `visible = false` as well.
  bool get isEntryVisible {
    switch (status) {
      case FeatureAccessStatus.available:
      case FeatureAccessStatus.disabled:
      case FeatureAccessStatus.maintenance:
      case FeatureAccessStatus.unavailable:
        return visible;
      case FeatureAccessStatus.hidden:
      case FeatureAccessStatus.developmentOnly:
      case FeatureAccessStatus.notInstalled:
      case FeatureAccessStatus.unknownFeature:
        return false;
    }
  }

  bool get isBlocked => !canLaunch;
}

/// Single place that combines local gates with the remote policy layer.
///
/// Remote configuration can only restrict an existing feature: development
/// flags, installation state and the local safety registry are evaluated first
/// and are never overridden by a remote row.
class FeatureAccessGuard {
  FeatureAccessGuard({
    RemoteFeaturePolicyService? service,
    bool Function()? debugBuild,
  }) : _serviceOverride = service,
       _debugBuildOverride = debugBuild;

  /// Process-wide guard. Tests may replace it before mounting widgets.
  static FeatureAccessGuard instance = FeatureAccessGuard();

  static const String disabledMessage = '该功能已停用。';
  static const String maintenanceMessage = '该功能正在维护，请稍后再试。';
  static const String unavailableMessage = '暂时无法确认该功能状态，请稍后重试。';
  static const String developmentOnlyMessage = '当前版本不提供该功能。';
  static const String notInstalledMessage = '该功能尚未添加到本机。';
  static const String unknownFeatureMessage = '该功能不存在或已下线。';

  final RemoteFeaturePolicyService? _serviceOverride;
  final bool Function()? _debugBuildOverride;

  RemoteFeaturePolicyService get _service =>
      _serviceOverride ?? RemoteFeaturePolicyService.instance;

  bool get _debugBuild =>
      _debugBuildOverride?.call() ?? DevelopmentModeService.isDev;

  /// Decision for a registered definition, using known local state.
  FeatureAccessDecision decideForDefinition(
    AppDefinition app, {
    bool? installed,
    bool? debugBuild,
  }) {
    return decide(
      featureId: app.metadata.id,
      requiresDev: app.metadata.requiresDev,
      installed: installed,
      debugBuild: debugBuild,
    );
  }

  /// Decision for an entry point that can await the local installation state.
  Future<FeatureAccessDecision> decideForEntry(AppDefinition app) async {
    await _service.initialize();
    bool? installed;
    try {
      installed = (await AppService.getState(app.metadata.id)).installed;
    } on Object {
      // A damaged local state must not block a feature that is otherwise
      // available; the catalog already treats it as installed by default.
      installed = null;
    }
    return decideForDefinition(app, installed: installed);
  }

  FeatureAccessDecision decide({
    required String featureId,
    bool exists = true,
    bool requiresDev = false,
    bool? installed,
    bool? debugBuild,
  }) {
    if (!exists) {
      return FeatureAccessDecision(
        featureId: featureId,
        status: FeatureAccessStatus.unknownFeature,
        message: unknownFeatureMessage,
      );
    }
    if (requiresDev && !(debugBuild ?? _debugBuild)) {
      return FeatureAccessDecision(
        featureId: featureId,
        status: FeatureAccessStatus.developmentOnly,
        message: developmentOnlyMessage,
      );
    }
    if (installed == false) {
      return FeatureAccessDecision(
        featureId: featureId,
        status: FeatureAccessStatus.notInstalled,
        message: notInstalledMessage,
      );
    }

    final evaluation = _service.evaluate(featureId);
    switch (evaluation.availability) {
      case RemoteFeatureAvailability.disabled:
        return FeatureAccessDecision(
          featureId: featureId,
          status: FeatureAccessStatus.disabled,
          message: evaluation.message ?? disabledMessage,
          origin: evaluation.origin,
          visible: evaluation.visible,
        );
      case RemoteFeatureAvailability.maintenance:
        return FeatureAccessDecision(
          featureId: featureId,
          status: FeatureAccessStatus.maintenance,
          message: evaluation.message ?? maintenanceMessage,
          origin: evaluation.origin,
          visible: evaluation.visible,
        );
      case RemoteFeatureAvailability.unavailable:
        return FeatureAccessDecision(
          featureId: featureId,
          status: FeatureAccessStatus.unavailable,
          message: evaluation.message ?? unavailableMessage,
          origin: evaluation.origin,
          visible: evaluation.visible,
        );
      case RemoteFeatureAvailability.enabled:
        return FeatureAccessDecision(
          featureId: featureId,
          status:
              evaluation.allowsEntry
                  ? FeatureAccessStatus.available
                  : FeatureAccessStatus.hidden,
          message: evaluation.message,
          origin: evaluation.origin,
          visible: evaluation.visible,
        );
    }
  }
}

/// Entry-point projection shared by the catalog, quick apps and navigation.
///
/// Keeping this in one helper avoids per-page policy judgement while leaving
/// the persisted user preferences untouched.
class FeatureEntryVisibility {
  FeatureEntryVisibility._();

  static bool isVisible(AppDefinition app) =>
      FeatureAccessGuard.instance.decideForDefinition(app).isEntryVisible;

  static List<AppDefinition> filter(Iterable<AppDefinition> apps) => [
    for (final app in apps)
      if (isVisible(app)) app,
  ];
}
