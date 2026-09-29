import 'package:flutter/material.dart';

import '../app.dart';
import '../../capabilities/external_app_launcher.dart';

final parcelIdentityCodeApp = AppDefinition.action(
  metadata: AppMetadata(
    id: 'feature.parcel.identity.code',
    name: '淘宝身份码',
    description: '快速打开淘宝取件身份码',
    iconCodePoint: Icons.qr_code_2_outlined.codePoint,
    category: AppCategory.life,
    developmentFlag: DevelopmentFlag.none,
    defaultPinned: false,
  ),
  action: _openTaobaoIdentityCode,
);

final _launcher = ExternalAppLauncher();
final _identityCodeTarget = ExternalAppTarget(
  uri: Uri.parse(
    'https://pages-fast.m.taobao.com/wow/z/uniapp/1011717/last-mile-fe/end-collect-platform/identity-code',
  ),
  androidPackage: 'com.taobao.taobao',
);

Future<bool> _openTaobaoIdentityCode(BuildContext context) async {
  final launched = await _launcher.launch(_identityCodeTarget);
  if (launched || !context.mounted) return launched;

  const message = '无法打开淘宝，请确认已安装淘宝。';
  {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text(message)));
  }
  return false;
}
