import 'package:url_launcher/url_launcher.dart';

/// 通过 QQ 群卡片深链调起手机 QQ 的加群界面。
///
/// 只携带公开群号，不涉及账号、Cookie 或任何本机标识。QQ 未安装、系统无应用
/// 可处理该 scheme 或调起被拒绝时返回 false，由入口提示群号让用户自行搜索。
class QqGroupJoinCapability {
  final Future<bool> Function(Uri uri)? _launcher;

  const QqGroupJoinCapability({Future<bool> Function(Uri uri)? launcher})
    : _launcher = launcher;

  /// 官方交流群，与页面展示的群号保持同一来源，避免文案与深链漂移。
  static const groupNumber = '1049712941';

  /// 手机 QQ 的群卡片页；`card_type=group` 直接落在加群入口，
  /// 已加群时显示群资料，未加群时显示“申请加群”。
  static final Uri groupUri = Uri.parse(
    'mqqapi://card/show_pslcard'
    '?src_type=internal&version=1&uin=$groupNumber'
    '&card_type=group&source=qrcode',
  );

  Future<bool> joinGroup() async {
    final launcher = _launcher ?? _launchExternally;
    try {
      return await launcher(groupUri);
    } on Object {
      return false;
    }
  }

  static Future<bool> _launchExternally(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
