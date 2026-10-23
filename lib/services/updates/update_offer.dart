import '../../capabilities/app_update/app_update_package.dart';
import '../fenfa/fenfa_models.dart';
import '../fenfa/fenfa_service.dart';

enum UpdateProvider { fenfa, upgradeLink }

class UpdateOffer {
  const UpdateOffer({
    required this.provider,
    required this.package,
    required this.notes,
    required this.force,
    this.sizeBytes,
    this.fenfaRelease,
    this.nativeMd5,
  });

  final UpdateProvider provider;
  final AppUpdatePackage package;
  final String notes;
  final bool force;
  final int? sizeBytes;
  final FenfaRelease? fenfaRelease;
  final String? nativeMd5;

  factory UpdateOffer.fromFenfa(FenfaRelease release) => UpdateOffer(
    provider: UpdateProvider.fenfa,
    package: AppUpdatePackage(
      version: release.version,
      versionCode: 2000 + normalizeFenfaBuild(release.build),
      downloadUrl: release.downloadUrl,
      deltaManifestUrl: release.deltaManifestUrl,
    ),
    notes: release.changelog,
    force: release.forceUpdate,
    fenfaRelease: release,
  );

  /// The existing mandatory-update dialog is presentation only. Downloads are
  /// dispatched by this offer's provider, never through this legacy DTO.
  FenfaRelease get dialogRelease =>
      fenfaRelease ??
      FenfaRelease(
        id: 'upgradelink-${package.versionCode}',
        version: package.version,
        build: package.versionCode,
        changelog: notes,
        forceUpdate: force,
        downloadUrl: package.downloadUrl,
      );
}
