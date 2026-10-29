import 'dart:convert';

import 'package:http/http.dart' as http;

import '../public_http_client.dart';
import 'remote_feature_policy_config.dart';
import 'remote_feature_policy_models.dart';

/// Transport boundary for the published policy set.
///
/// Implementations return decoded rows so parsing and validation stay in one
/// place. Tests replace this interface instead of issuing HTTP requests.
abstract class RemoteFeaturePolicySource {
  Future<List<Object?>> fetchRows();

  void close();
}

/// Read-only PostgREST adapter for `public.feature_policies`.
///
/// The client only ever performs a filtered `SELECT`; row level security denies
/// every write for the publishable key.
class SupabaseFeaturePolicySource implements RemoteFeaturePolicySource {
  SupabaseFeaturePolicySource({required this.config, PublicHttpClient? client})
    : _client =
          client ?? PublicHttpClient(defaultTimeout: config.requestTimeout),
      _ownsClient = client == null;

  static const String _select =
      'feature_id,state,visible,message,platform,'
      'min_version,max_version,priority,updated_at';

  final RemoteFeaturePolicyConfig config;
  final PublicHttpClient _client;
  final bool _ownsClient;

  @override
  Future<List<Object?>> fetchRows() async {
    final endpoint = config.endpoint;
    if (endpoint == null || config.publishableKey.isEmpty) {
      throw const RemoteFeaturePolicyFetchException('not configured');
    }
    final uri = endpoint.replace(
      queryParameters: const {
        'select': _select,
        'published': 'eq.true',
        'order': 'feature_id.asc',
      },
    );

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {...config.authHeaders, 'Accept': 'application/json'},
        timeout: config.requestTimeout,
      );
    } on PublicHttpException catch (error) {
      throw RemoteFeaturePolicyFetchException(
        error.failureReason.name,
        statusCode: error.statusCode,
      );
    }

    if (response.statusCode != 200) {
      throw RemoteFeaturePolicyFetchException(
        'unexpected status',
        statusCode: response.statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const RemoteFeaturePolicyFetchException('response is not JSON');
    }
    if (decoded is! List) {
      throw const RemoteFeaturePolicyFetchException('response is not a list');
    }
    return decoded;
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
