import 'auth_service.dart';
import 'campus_session_store.dart';
import 'campus_service_session_service.dart';
import 'service_endpoints.dart';

/// Host-owned readiness coordinator for service warm-up.
///
/// Readiness is deliberately a boolean capability result. Callers do not
/// inspect a credential object to decide whether a service is available.
class SessionReadinessService {
  const SessionReadinessService._();

  static Future<bool> ensure(CampusServiceId serviceId) async {
    final account = await AuthService.getCurrentAccount();
    if (account == null) return false;
    final definition = CampusServiceEndpoints.definitionForId(serviceId);
    if (definition == null) return false;
    final store = await CampusSessionStore.open(accountKey: account.accountKey);
    if (await _isReady(store, definition)) return true;

    final target = switch (definition.sessionMaterializer) {
      CustomPostSsoBootstrap(:final bootstrapId) => bootstrapId,
      _ => serviceId,
    };
    final session = await CampusSessionService.get(target);
    if (session == null) return false;
    if ((await AuthService.getCurrentAccount())?.accountKey !=
        account.accountKey) {
      return false;
    }
    // Root recovery may have replaced the epoch while the broker was running.
    final refreshedStore = await CampusSessionStore.open(
      accountKey: account.accountKey,
    );
    if (!await refreshedStore.isCurrentIdentityEpoch()) return false;
    return _isReady(refreshedStore, definition, finalUri: session.sessionUri);
  }

  static Future<bool> _isReady(
    CampusSessionStore store,
    CampusServiceDefinition definition, {
    Uri? finalUri,
  }) async {
    if (definition.sessionMaterializer case CustomPostSsoBootstrap(
      :final bootstrapId,
    )) {
      return await store.artifacts.read(bootstrapId) != null;
    }
    if (definition.sessionMaterializer.containsWebViewSessionMaterializer) {
      return finalUri != null &&
          finalUri.toString().contains('caslogin') &&
          finalUri.toString().contains('userToken');
    }
    if (definition.sessionMaterializer.tokenFromRedirect != null) {
      final artifact = await store.artifacts.read(definition.id);
      if (artifact == null) return false;
    }
    final jar = store.cookieJar(
      definition.id,
      scope: definition.scopeFor(definition.seedUri),
    );
    return (await jar.headerFor(definition.seedUri)).isNotEmpty ||
        definition.sessionMaterializer.tokenFromRedirect != null;
  }
}
