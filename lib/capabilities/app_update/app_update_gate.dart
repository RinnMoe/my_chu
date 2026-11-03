import '../../services/app_remote_services_service.dart';
import '../../services/build_info.dart';
import '../../services/platform_compatibility_service.dart';
import '../../services/privacy_agreement_service.dart';

/// The three gates every update path consults before it downloads anything.
///
/// Eligibility is a build fact, consent and the remote-service switch are
/// asynchronous policy, and the revision pairs both policy signals so a caller
/// can detect that the answer changed while it was awaiting something else.
/// They live here so the native UpgradeLink planner and the shared service
/// cannot drift into two subtly different definitions.
abstract final class AppUpdateGate {
  /// Only an official Android release may merge a patch against the installed
  /// base APK, and only those builds may offer the native route at all.
  static bool deltaEligible() =>
      PlatformCompatibilityService.isAndroid &&
      BuildInfo.current.isOfficialRelease;

  /// The user accepted the privacy agreement and remote services stay enabled.
  static Future<bool> allowed() async =>
      await PrivacyAgreementService.isAccepted() &&
      await AppRemoteServicesService.isEnabled();

  /// Changes whenever either policy signal changes.
  static int revision() =>
      AppRemoteServicesService.revision.value +
      PrivacyAgreementService.revision.value;
}
