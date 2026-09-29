import 'auth_service.dart';
import 'portal_identity_service.dart';
import 'portal_route_service.dart';

enum AcademicAffairsBackend { undergraduate, graduate }

class AcademicAffairsIdentityException implements Exception {
  final String message;

  const AcademicAffairsIdentityException([
    this.message = '暂时无法识别学生身份，请重新登录后重试。',
  ]);

  @override
  String toString() => message;
}

class AcademicAffairsBackendResolver {
  AcademicAffairsBackendResolver._();

  static Future<AcademicAffairsBackend> Function()? debugResolver;

  static AcademicAffairsBackend? fromIdentity(String? identity) {
    final route = PortalRoute.fromIdentity(identity);
    if (route == null) return null;
    return route.studentType == PortalStudentType.graduate
        ? AcademicAffairsBackend.graduate
        : AcademicAffairsBackend.undergraduate;
  }

  static PortalRoute routeFor(AcademicAffairsBackend backend) =>
      PortalRoute.forStudentType(
        backend == AcademicAffairsBackend.graduate
            ? PortalStudentType.graduate
            : PortalStudentType.undergraduate,
      );

  static Future<AcademicAffairsBackend> resolveCurrent() async {
    final override = debugResolver;
    if (override != null) return override();
    final account = await AuthService.getCurrentAccount();
    if (account == null) {
      throw const AcademicAffairsIdentityException('请先登录后访问教务系统。');
    }
    final existing = fromIdentity(account.identity);
    if (existing != null) return existing;

    final refreshed = await PortalIdentityService.refreshAccountName();
    if (refreshed == null || refreshed.accountKey != account.accountKey) {
      throw const AcademicAffairsIdentityException();
    }
    final resolved = fromIdentity(refreshed.identity);
    if (resolved == null) throw const AcademicAffairsIdentityException();
    return resolved;
  }

}
