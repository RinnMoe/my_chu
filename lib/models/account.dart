import 'dart:math';

/// User profile and non-secret account state.
///
/// Authentication state is deliberately not part of this model. Root
/// identity cookies, service cookies, tokens and path-scoped sessions live in
/// [CampusSessionStore], keyed by [accountKey].
class Account {
  /// Immutable local key for secure storage, session ownership and caches.
  /// This is deliberately separate from [uid], which is profile data returned
  /// by a campus service after login.
  final String id;
  final String? uid;
  final String? identity;
  String name;
  final String? mobileCampusUuId;
  final String? mobileCampusUserId;
  final DateTime loginTime;

  Account({
    required this.id,
    this.uid,
    this.identity,
    this.name = 'CHUer',
    this.mobileCampusUuId,
    this.mobileCampusUserId,
    required this.loginTime,
  });

  String get accountKey => id;

  static String createAccountKey() {
    final random = Random.secure();
    final entropy = random.nextInt(0x7fffffff).toRadixString(36);
    return 'local_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$entropy';
  }

  Map<String, dynamic> toProfileJson() => {
    'accountKey': id,
    if (uid != null) 'uid': uid,
    if (identity != null && identity!.isNotEmpty) 'identity': identity,
    'name': name,
    if (mobileCampusUuId != null) 'mobileCampusUuId': mobileCampusUuId,
    if (mobileCampusUserId != null) 'mobileCampusUserId': mobileCampusUserId,
    'loginTime': loginTime.toIso8601String(),
  };

  factory Account.fromProfileJson(Map<String, dynamic> json) {
    final accountKey = json['accountKey'] as String?;
    final loginTime = DateTime.tryParse(json['loginTime'] as String? ?? '');
    if (accountKey == null || accountKey.trim().isEmpty || loginTime == null) {
      throw const FormatException('invalid Account profile');
    }
    return Account(
      id: accountKey,
      uid: json['uid'] as String?,
      identity: json['identity'] as String?,
      name: json['name'] as String? ?? 'CHUer',
      mobileCampusUuId: json['mobileCampusUuId'] as String?,
      mobileCampusUserId: json['mobileCampusUserId'] as String?,
      loginTime: loginTime,
    );
  }

  Account copyWith({
    String? uid,
    String? identity,
    String? name,
    String? mobileCampusUuId,
    String? mobileCampusUserId,
    DateTime? loginTime,
  }) => Account(
    id: id,
    uid: uid ?? this.uid,
    identity: identity ?? this.identity,
    name: name ?? this.name,
    mobileCampusUuId: mobileCampusUuId ?? this.mobileCampusUuId,
    mobileCampusUserId: mobileCampusUserId ?? this.mobileCampusUserId,
    loginTime: loginTime ?? this.loginTime,
  );
}
