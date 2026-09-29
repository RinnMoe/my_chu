import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/account.dart';

/// Owns the single active account profile. Session cookies, tokens and
/// path-scoped sessions are owned by [CampusSessionStore].
class CurrentAccountStore {
  CurrentAccountStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const accountsKey = 'accounts.v2';

  Future<Account?> read() async {
    final raw = await _storage.read(key: accountsKey);
    if (raw == null) return null;
    if (raw.isEmpty) {
      throw const FormatException('v2 account storage is empty');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('v2 accounts must be a JSON list');
    }
    if (decoded.isEmpty) return null;
    if (decoded.length != 1) {
      throw const FormatException(
        'v2 account storage must contain one account',
      );
    }
    final item = decoded.single;
    if (item is! Map) {
      throw const FormatException('v2 account profile must be an object');
    }
    return Account.fromProfileJson(Map<String, dynamic>.from(item));
  }

  Future<void> write(Account account) {
    if (account.accountKey.trim().isEmpty) {
      throw const FormatException('invalid current account');
    }
    return _storage.write(
      key: accountsKey,
      value: jsonEncode([account.toProfileJson()]),
    );
  }

  Future<void> clear() => _storage.delete(key: accountsKey);

  Future<bool> matches(Account expected) async {
    final actual = await read();
    return actual != null &&
        jsonEncode(actual.toProfileJson()) ==
            jsonEncode(expected.toProfileJson());
  }
}
