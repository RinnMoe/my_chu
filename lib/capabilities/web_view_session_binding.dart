import '../services/campus_service_id.dart';
import '../services/session_materialization.dart';
import '../services/session_runtime_fence.dart';

/// Non-secret identity and materialization binding held by a WebView host.
/// Cookie/token values and Account objects deliberately do not belong here.
class WebViewSessionBinding {
  const WebViewSessionBinding({
    required this.accountKey,
    required this.serviceId,
    required this.sessionRevision,
    required this.identityEpoch,
    required this.runtimeFence,
    required this.materializationFence,
  });

  final String accountKey;
  final CampusServiceId serviceId;
  final int sessionRevision;
  final String identityEpoch;
  final SessionRuntimeFence runtimeFence;
  final WebViewMaterializationFence materializationFence;
}
