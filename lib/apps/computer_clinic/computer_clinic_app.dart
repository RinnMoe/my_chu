import 'package:flutter/material.dart';

import '../../capabilities/manual_login_web_view_page.dart';
import '../app.dart';

const _title = '电脑义诊预约';

final computerClinicApp = AppDefinition(
  metadata: AppMetadata(
    id: 'feature.computer.clinic',
    name: _title,
    description: '',
    iconCodePoint: Icons.computer_outlined.codePoint,
    category: AppCategory.campus,
    developmentFlag: DevelopmentFlag.none,
  ),
  requiresCampusAccount: false,
  builder:
      (_) => const ManualLoginWebViewPage(
        title: _title,
        url: 'http://chdinfodazhituan.mikecrm.com/eIh24Dc',
      ),
);
