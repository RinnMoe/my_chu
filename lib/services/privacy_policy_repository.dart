import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_policy_document.dart';
import 'supabase/supabase_project_config.dart';

/// Public static resources only: no campus client, cookies, credentials or SDKs.
class PrivacyPolicyRepository {
  PrivacyPolicyRepository({
    String? baseUrl,
    String projectUrl = SupabaseEndpointConfig.environmentUrl,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 8),
  }) : baseUrl =
           baseUrl ??
           (const String.fromEnvironment('MYCHU_PRIVACY_BASE_URL').isNotEmpty
               ? const String.fromEnvironment('MYCHU_PRIVACY_BASE_URL')
               : SupabaseEndpointConfig.privacyResourceRoot(
                 projectUrl: projectUrl,
               )),
       _clientFactory = clientFactory ?? http.Client.new;

  static PrivacyPolicyRepository instance = PrivacyPolicyRepository();
  static const cacheKey = 'privacy.agreement.documents';
  final String baseUrl;
  final http.Client Function() _clientFactory;
  final Duration timeout;
  Future<PrivacyPolicyDocument>? _inFlight;

  static Uri resourceRoot(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.endsWith('/')) {
      throw const FormatException('Configure an HTTPS policy root ending in /');
    }
    return uri;
  }

  Future<List<PrivacyPolicyDocument>> cached() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <PrivacyPolicyDocument>[];
    try {
      final entries =
          jsonDecode(prefs.getString(cacheKey) ?? '{}') as Map<String, dynamic>;
      for (final entry in entries.entries) {
        try {
          final value = entry.value as Map<String, dynamic>;
          final document = PrivacyPolicyDocument.decode(
            value['body'] as String,
            expectedHash: value['sha256'] as String,
          );
          if (entry.key == '${document.version}') result.add(document);
        } catch (_) {
          /* Ignore only the corrupt entry. */
        }
      }
    } catch (_) {
      /* A corrupt cache is never consent. */
    }
    result.sort((a, b) => b.version.compareTo(a.version));
    return result;
  }

  Future<PrivacyPolicyDocument> refresh({
    int acceptedVersion = 0,
    String? acceptedHash,
  }) {
    return _inFlight ??= _refresh(
      acceptedVersion,
      acceptedHash,
    ).whenComplete(() => _inFlight = null);
  }

  Future<PrivacyPolicyDocument> _refresh(
    int acceptedVersion,
    String? acceptedHash,
  ) async {
    final root = resourceRoot(baseUrl);
    final client = _clientFactory();
    final deadline = DateTime.now().add(timeout);
    final timer = Timer(timeout, client.close);
    Future<String> read(Uri uri, {String? expectedHash}) async {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['Cache-Control'] = 'no-cache';
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw const FormatException('Policy request failed');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 512 * 1024) {
          throw const FormatException('Policy too large');
        }
      }
      if (expectedHash != null &&
          sha256.convert(bytes).toString() != expectedHash) {
        throw const FormatException('Policy bytes hash mismatch');
      }
      return utf8.decode(bytes);
    }

    try {
      return await (() async {
        final index =
            jsonDecode(await read(root.resolve('latest.json')))
                as Map<String, dynamic>;
        final version = index['version'];
        final hash = index['sha256'];
        if (index['schemaVersion'] != 1 ||
            version is! int ||
            version < 4 ||
            index['path'] != 'versions/$version.json' ||
            hash is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          throw const FormatException('Invalid policy index');
        }
        final previous = await cached();
        if (version < acceptedVersion ||
            (version == acceptedVersion &&
                acceptedHash != null &&
                hash != acceptedHash) ||
            previous.any((d) => d.version > version) ||
            previous.any((d) => d.version == version && d.hash != hash)) {
          throw const FormatException('Policy version rollback or mutation');
        }
        final body = await read(
          root.resolve('versions/$version.json'),
          expectedHash: hash,
        );
        final document = PrivacyPolicyDocument.decode(body, expectedHash: hash);
        if (document.version != version || DateTime.now().isAfter(deadline)) {
          throw const FormatException('Policy version mismatch or timeout');
        }
        final retained = <int, PrivacyPolicyDocument>{
          for (final old in previous)
            if (old.version == acceptedVersion) old.version: old,
          document.version: document,
        };
        final prefs = await SharedPreferences.getInstance();
        // One preference replacement: failed writes retain the previous cache.
        try {
          final saved = await prefs.setString(
            cacheKey,
            jsonEncode({
              for (final entry in retained.entries)
                '${entry.key}': {
                  'body': entry.value.encoded,
                  'sha256': entry.value.hash,
                },
            }),
          );
          if (!saved) throw StateError('Policy cache write failed');
        } catch (_) {
          await prefs.reload();
          rethrow;
        }
        return document;
      })().timeout(timeout);
    } finally {
      timer.cancel();
      client.close();
    }
  }
}
