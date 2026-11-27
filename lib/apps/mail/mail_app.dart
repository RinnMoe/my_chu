import 'package:flutter/material.dart';

import '../app.dart';
import 'mail_account.dart';
import 'mail_page.dart';

const mailAppId = 'feature.mail';

final mailApp = AppDefinition(
  requiresCampusAccount: false,
  metadata: AppMetadata(
    id: mailAppId,
    name: '校园邮箱',
    description: '收发校园邮件',
    iconCodePoint: Icons.mail_outline.codePoint,
    category: AppCategory.campus,
    developmentFlag: DevelopmentFlag.beta,
  ),
  builder: (_) => const MailPage(),
  account: MailAccountProvider(),
);
