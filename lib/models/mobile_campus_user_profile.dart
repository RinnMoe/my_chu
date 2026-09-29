class MobileCampusUserProfile {
  final String userId;
  final String userName;
  final String displayName;
  final int role;

  /// 仅当移动校园 role 能确定本研身份时非空。
  final String? identity;

  const MobileCampusUserProfile({
    required this.userId,
    required this.userName,
    required this.displayName,
    required this.role,
    this.identity,
  });

  static String? identityForRole(int role) {
    return switch (role) {
      1 => '本科生',
      3 => '研究生',
      _ => null,
    };
  }
}
