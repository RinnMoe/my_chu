import '../../capabilities/app_update/app_update_package.dart';
import 'upgradelink_delta.dart';

/// One upgrade the update service announced, in transport-neutral terms.
class UpdateOffer {
  const UpdateOffer({
    required this.package,
    required this.notes,
    required this.force,
    this.sizeBytes,
    this.nativeMd5,
    this.packageName,
    this.nativeDelta,
  });

  final AppUpdatePackage package;
  final String notes;
  final bool force;
  final int? sizeBytes;
  final String? nativeMd5;

  /// Package the service announced, used to prove the installed base APK is the
  /// same application before a native patch may be applied.
  final String? packageName;

  /// Native HDiffPatch patch metadata, present only when the service returned a
  /// complete and usable patch description.
  final UpgradeLinkNativeDelta? nativeDelta;
}
