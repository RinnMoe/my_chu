import 'auth_service.dart';
import 'campus_session_store.dart';
import 'campus_service_session_service.dart';
import 'federated_session.dart';
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

    final fence = store.captureFence(
      serviceId: definition.id,
      scopeKey: definition
          .scopeFor(definition.startUri)
          .keyFor(definition.startUri),
      sessionRevision: AuthService.sessionRevision,
      additionalScopeKeys: definition.sessionScopeKeys,
    );

    if (definition.sessionMaterializer case CustomPostSsoBootstrap(
      :final bootstrapId,
    )) {
      await CampusSessionService.get(bootstrapId, forceRefresh: true);
      final refreshedStore = await CampusSessionStore.open(
        accountKey: account.accountKey,
      );
      return _isReady(refreshedStore, definition);
    }

    final result = await FederatedSession.exchangeForStore(
      store: store,
      definition: definition,
      fence: fence,
      label: '会话预热 ${definition.id.value}',
    );
    if (result.endedAtIdentityLogin || !result.committed) return false;
    if (!await store.isCurrentIdentityEpoch()) return false;
    return _isReady(store, definition, finalUri: result.finalUri);
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
