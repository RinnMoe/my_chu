import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A credential selected by the user for silent sign-in.
///
/// The value is intentionally kept out of account models, logs, and feature
/// state. A capability instance owns only the secure-storage namespace; the
/// caller supplies credentials at the explicit login boundary.
class SavedLoginCredential {
  final String username;
  final String password;
  final DateTime savedAt;

  const SavedLoginCredential({
    required this.username,
    required this.password,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    'savedAt': savedAt.toIso8601String(),
  };

  static SavedLoginCredential? fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ?? '').toString().trim();
    final password = json['password']?.toString() ?? '';
    if (username.isEmpty || password.isEmpty) return null;
    final savedAt =
        DateTime.tryParse(json['savedAt']?.toString() ?? '') ?? DateTime.now();
    return SavedLoginCredential(
      username: username,
      password: password,
      savedAt: savedAt,
    );
  }
}

/// Host-owned secure storage for optional saved login credentials.
///
/// This is deliberately a capability rather than an app-local service so the
/// host's unified-identity silent-login service can keep its credential
/// handling out of account models and feature state.
class SavedLoginCredentialCapability {
  static const unifiedIdentityScope = 'unified_identity';

  final String scope;
  final FlutterSecureStorage _storage;
  final Future<String?> Function(String key)? _secureRead;
  final Future<void> Function(String key, String value)? _secureWrite;
  final Future<void> Function(String key)? _secureDelete;

  SavedLoginCredentialCapability({
    required this.scope,
    FlutterSecureStorage? storage,
    Future<String?> Function(String key)? secureRead,
    Future<void> Function(String key, String value)? secureWrite,
    Future<void> Function(String key)? secureDelete,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _secureRead = secureRead,
       _secureWrite = secureWrite,
       _secureDelete = secureDelete {
    if (!_validScope.hasMatch(scope)) {
      throw ArgumentError.value(scope, 'scope', 'must be a safe storage scope');
    }
  }

  /// The legacy unified-identity namespace. Its key is kept unchanged for
  /// backward compatibility with existing saved credentials.
  factory SavedLoginCredentialCapability.unifiedIdentity({
    FlutterSecureStorage? storage,
    Future<String?> Function(String key)? secureRead,
    Future<void> Function(String key, String value)? secureWrite,
    Future<void> Function(String key)? secureDelete,
  }) => SavedLoginCredentialCapability(
    scope: unifiedIdentityScope,
    storage: storage,
    secureRead: secureRead,
    secureWrite: secureWrite,
    secureDelete: secureDelete,
  );

  static final _validScope = RegExp(r'^[A-Za-z0-9._-]+$');

  String get _credentialKey =>
      scope == unifiedIdentityScope
          ? 'saved_login_credential.v1'
          : 'saved_login_credential.$scope.v1';

  /// Reads a saved credential without exposing malformed storage contents.
  Future<SavedLoginCredential?> read() async {
    final raw = await _readSecure(_credentialKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SavedLoginCredential.fromJson(Map<String, dynamic>.from(decoded));
    } on Object {
      return null;
    }
  }

  Future<bool> hasCredential() async => (await read()) != null;

  /// Saves only explicit non-empty credentials to Android Keystore-backed
  /// secure storage. Passwords never enter logs or account serialization.
  Future<void> save(String username, String password) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty || password.isEmpty) return;
    final credential = SavedLoginCredential(
      username: trimmed,
      password: password,
      savedAt: DateTime.now(),
    );
    await _writeSecure(_credentialKey, jsonEncode(credential.toJson()));
  }

  Future<void> clear() => _deleteSecure(_credentialKey);

  Future<String?> _readSecure(String key) {
    final hook = _secureRead;
    if (hook != null) return hook(key);
    return _storage.read(key: key);
  }

  Future<void> _writeSecure(String key, String value) {
    final hook = _secureWrite;
    if (hook != null) return hook(key, value);
    return _storage.write(key: key, value: value);
  }

  Future<void> _deleteSecure(String key) {
    final hook = _secureDelete;
    if (hook != null) return hook(key);
    return _storage.delete(key: key);
  }
}
