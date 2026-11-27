/// 校园邮箱账号配置（不含密码）。
///
/// 密码由 `MailCredentialStore` 单独写入安全存储，配置对象可以安全地出现在
/// 设置页状态与 SharedPreferences 中。
library;

enum MailSecurity { ssl, starttls }

class MailAccountConfig {
  static const chdDomain = 'chd.edu.cn';
  static const defaultImapHost = 'imaphz.qiye.163.com';
  static const defaultImapPort = 993;

  /// 网易企业邮箱杭州节点的发件服务器，与收件主机遵循同一命名规则。
  static const defaultSmtpHost = 'smtphz.qiye.163.com';
  static const defaultSmtpPort = 465;

  static const _emailPattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';
  static final _emailRegExp = RegExp(_emailPattern);

  final String email;
  final String imapHost;
  final int imapPort;
  final MailSecurity imapSecurity;
  final String smtpHost;
  final int smtpPort;
  final MailSecurity smtpSecurity;

  const MailAccountConfig({
    required this.email,
    required this.imapHost,
    required this.imapPort,
    this.imapSecurity = MailSecurity.ssl,
    required this.smtpHost,
    required this.smtpPort,
    this.smtpSecurity = MailSecurity.ssl,
  });

  factory MailAccountConfig.chd(String email) {
    return MailAccountConfig(
      email: email.trim(),
      imapHost: defaultImapHost,
      imapPort: defaultImapPort,
      imapSecurity: MailSecurity.ssl,
      smtpHost: defaultSmtpHost,
      smtpPort: defaultSmtpPort,
      smtpSecurity: MailSecurity.ssl,
    );
  }

  static int defaultPortFor(MailSecurity security) =>
      security == MailSecurity.ssl ? 993 : 143;

  static int defaultSmtpPortFor(MailSecurity security) =>
      security == MailSecurity.ssl ? 465 : 587;

  /// 发件主机默认沿用收件主机的命名规则：`imaphz` → `smtphz`、`imap.` → `smtp.`。
  ///
  /// 自建服务器通常收发同主机，此时原样返回。
  static String deriveSmtpHost(String imapHost) {
    final host = imapHost.trim().toLowerCase();
    if (host.startsWith('imap')) return 'smtp${host.substring(4)}';
    return host;
  }

  /// 校园邮箱地址固定使用校园域名，界面只需收集前缀。
  static String emailFromPrefix(String raw) {
    final prefix = prefixOf(raw);
    return prefix.isEmpty ? '' : '$prefix@$chdDomain';
  }

  /// 取出 `@` 之前的前缀，完整地址与纯前缀都接受。
  static String prefixOf(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    final at = value.indexOf('@');
    final prefix = at < 0 ? value : value.substring(0, at);
    return prefix.replaceAll(RegExp(r'\s+'), '');
  }

  String? get validationError {
    final normalizedEmail = email.trim();
    if (!_emailRegExp.hasMatch(normalizedEmail)) {
      return '请输入完整的邮箱地址';
    }
    final imapError = _hostError(imapHost, '请填写收件服务器地址');
    if (imapError != null) return imapError;
    if (imapPort < 1 || imapPort > 65535) {
      return '端口需在 1 到 65535 之间';
    }
    final smtpError = _hostError(smtpHost, '请填写发件服务器地址');
    if (smtpError != null) return smtpError;
    if (smtpPort < 1 || smtpPort > 65535) {
      return '端口需在 1 到 65535 之间';
    }
    return null;
  }

  bool get isValid => validationError == null;

  static String? _hostError(String value, String emptyMessage) {
    final host = value.trim();
    if (host.isEmpty) return emptyMessage;
    if (host.contains('/') || host.contains(':')) {
      return '服务器地址不要包含协议或端口';
    }
    return null;
  }

  MailAccountConfig copyWith({
    String? email,
    String? imapHost,
    int? imapPort,
    MailSecurity? imapSecurity,
    String? smtpHost,
    int? smtpPort,
    MailSecurity? smtpSecurity,
  }) {
    return MailAccountConfig(
      email: email ?? this.email,
      imapHost: imapHost ?? this.imapHost,
      imapPort: imapPort ?? this.imapPort,
      imapSecurity: imapSecurity ?? this.imapSecurity,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpSecurity: smtpSecurity ?? this.smtpSecurity,
    );
  }

  /// 载荷 schema 2 增加发件服务器字段；键名与凭证作用域保持不变。
  Map<String, dynamic> toJson() => {
    'schema': 2,
    'email': email,
    'imapHost': imapHost,
    'imapPort': imapPort,
    'imapSecurity': imapSecurity.name,
    'smtpHost': smtpHost,
    'smtpPort': smtpPort,
    'smtpSecurity': smtpSecurity.name,
  };

  /// 兼容 schema 1：缺少或非法的发件字段按收件主机推导。
  static MailAccountConfig? fromJson(Map<String, dynamic> json) {
    final email = (json['email'] ?? '').toString().trim();
    final imapHost = (json['imapHost'] ?? '').toString().trim();
    final imapPort = _intFrom(json['imapPort']);
    if (email.isEmpty || imapHost.isEmpty || imapPort == null) return null;

    final imapSecurity = _securityFrom(json['imapSecurity']);
    final rawSmtpHost = (json['smtpHost'] ?? '').toString().trim();
    var smtpHost =
        rawSmtpHost.isEmpty ? deriveSmtpHost(imapHost) : rawSmtpHost;
    if (_hostError(smtpHost, '') != null) {
      smtpHost = deriveSmtpHost(imapHost);
    }
    final smtpSecurity = _securityFrom(json['smtpSecurity']);
    final rawSmtpPort = _intFrom(json['smtpPort']);
    final smtpPort =
        rawSmtpPort == null || rawSmtpPort < 1 || rawSmtpPort > 65535
            ? defaultSmtpPortFor(smtpSecurity)
            : rawSmtpPort;

    final config = MailAccountConfig(
      email: email,
      imapHost: imapHost,
      imapPort: imapPort,
      imapSecurity: imapSecurity,
      smtpHost: smtpHost,
      smtpPort: smtpPort,
      smtpSecurity: smtpSecurity,
    );
    return config.isValid ? config : null;
  }

  static MailSecurity _securityFrom(Object? value) =>
      MailSecurity.values.firstWhere(
        (item) => item.name == value,
        orElse: () => MailSecurity.ssl,
      );

  static int? _intFrom(Object? value) => switch (value) {
    final int number => number,
    final String text => int.tryParse(text),
    _ => null,
  };

  @override
  bool operator ==(Object other) {
    return other is MailAccountConfig &&
        other.email == email &&
        other.imapHost == imapHost &&
        other.imapPort == imapPort &&
        other.imapSecurity == imapSecurity &&
        other.smtpHost == smtpHost &&
        other.smtpPort == smtpPort &&
        other.smtpSecurity == smtpSecurity;
  }

  @override
  int get hashCode => Object.hash(
    email,
    imapHost,
    imapPort,
    imapSecurity,
    smtpHost,
    smtpPort,
    smtpSecurity,
  );
}
