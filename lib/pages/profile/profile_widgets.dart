import 'dart:math' as math;

import '../../widgets/app_bottom_sheet.dart';
import 'package:flutter/material.dart';

import '../../services/ip_status_service.dart';
import '../../widgets/adaptive_settings.dart';

class ProfileSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingValue;
  final VoidCallback onTap;

  const ProfileSettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveSettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailingValue: trailingValue,
      onTap: onTap,
    );
  }
}

/// 账号分组首行：身份信息与当前网络环境。
///
/// 身份卡并入“账号”分组后不再单独占一张卡片，分栏与相邻设置项对齐；姓名与
/// 学号两行保持紧凑并整体居中，网络状态作为尾随控件与两行居中对齐。当前字号
/// 和可用宽度放不下时，网络状态改排在身份下方，避免挤压姓名与学号。
class ProfileIdentityRow extends StatelessWidget {
  final bool loading;
  final bool loadFailed;
  final String? name;
  final String? uid;
  final String? identity;
  final CampusNetworkStatus? networkStatus;
  final bool networkLoading;
  final VoidCallback? onRetryAccount;
  final VoidCallback? onOpenNetworkDetails;

  const ProfileIdentityRow({
    super.key,
    required this.loading,
    required this.loadFailed,
    required this.name,
    required this.uid,
    this.identity,
    required this.networkStatus,
    required this.networkLoading,
    required this.onRetryAccount,
    required this.onOpenNetworkDetails,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final titleStyle = materialTheme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final detailStyle = materialTheme.textTheme.bodySmall?.copyWith(
      color: materialTheme.colorScheme.onSurfaceVariant,
    );
    final retryWidget =
        onRetryAccount == null
            ? null
            : TextButton(onPressed: onRetryAccount, child: const Text('重试'));
    final chip = _NetworkStatusChip(
      status: networkStatus,
      loading: networkLoading,
      onPressed: onOpenNetworkDetails,
    );
    final chipWidth =
        networkLoading
            ? 76.0
            : _networkChipWidth(context, _networkStatusLabel(networkStatus));
    if (loading) {
      return _IdentityTile(
        title: const _Skeleton(width: 160, height: 18),
        titleWidth: 160,
        detail: const _Skeleton(width: 112, height: 14),
        detailWidth: 112,
        chip: chip,
        chipWidth: chipWidth,
      );
    }
    if (loadFailed) {
      return ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: const Text('账号信息暂不可用'),
        trailing: retryWidget,
      );
    }
    final accountLine = [
      if (uid?.trim().isNotEmpty ?? false) uid!.trim(),
      if (identity?.trim().isNotEmpty ?? false) identity!.trim(),
    ].join(' ');
    return _IdentityTile(
      title: Text(
        name ?? '未登录',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      ),
      titleWidth: _textWidth(context, name ?? '未登录', titleStyle),
      detail:
          accountLine.isEmpty ? null : Text(accountLine, style: detailStyle),
      detailWidth:
          accountLine.isEmpty
              ? 0
              : _textWidth(context, accountLine, detailStyle),
      chip: chip,
      chipWidth: chipWidth,
    );
  }
}

String _networkStatusLabel(CampusNetworkStatus? status) {
  if (status?.inWhiteList == true) {
    return '校园网';
  }
  return status == null ? '未知网络' : '校外网';
}

double _textWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// 网络状态按钮在当前主题下的固有宽度：文本、内边距与描边。
double _networkChipWidth(BuildContext context, String label) {
  final theme = Theme.of(context);
  final style = OutlinedButtonTheme.of(context).style;
  final textWidth = _textWidth(context, label, theme.textTheme.labelLarge);
  final paddingProperty = style?.padding;
  final padding =
      paddingProperty?.resolve(const <WidgetState>{}) ??
      const EdgeInsets.symmetric(horizontal: 24);
  final borderWidth = style?.side?.resolve(const <WidgetState>{})?.width ?? 1.0;
  return textWidth + padding.horizontal + 2 * borderWidth;
}

/// 账号身份行：姓名与学号作为紧凑的两行整体居中，网络状态作为尾随控件与
/// 两行居中对齐；当前字号和可用宽度放不下时，网络状态移到身份信息下方。
class _IdentityTile extends StatelessWidget {
  const _IdentityTile({
    required this.title,
    required this.titleWidth,
    this.detail,
    this.detailWidth = 0,
    required this.chip,
    required this.chipWidth,
  });

  final Widget title;
  final double titleWidth;
  final Widget? detail;
  final double detailWidth;
  final Widget chip;
  final double chipWidth;

  @override
  Widget build(BuildContext context) {
    final tileTheme = ListTileTheme.of(context);
    final contentPadding = (tileTheme.contentPadding ??
            const EdgeInsetsDirectional.only(start: 16, end: 24))
        .resolve(Directionality.of(context));
    final titleGap = tileTheme.horizontalTitleGap ?? 16;
    final leadingWidth = math.max(tileTheme.minLeadingWidth ?? 24, 24.0);
    final chromeWidth =
        contentPadding.left + contentPadding.right + leadingWidth + titleGap;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 与 `_RenderListTile._computeSizes` 一致：文字区宽度等于列表宽度减去
        // 内容留白、前导图标与标题间距，以及尾随控件及其间距。
        final textWidth =
            constraints.maxWidth -
            chromeWidth -
            math.max(chipWidth + titleGap, 32.0);
        final fitsInline =
            textWidth > 0 && textWidth >= math.max(titleWidth, detailWidth);
        return ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: title,
          subtitle:
              fitsInline
                  ? detail
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (detail != null) ...[
                        detail!,
                        const SizedBox(height: 8),
                      ],
                      chip,
                    ],
                  ),
          trailing: fitsInline ? chip : null,
          isThreeLine: !fitsInline,
          titleAlignment:
              fitsInline
                  ? ListTileTitleAlignment.center
                  : ListTileTitleAlignment.threeLine,
        );
      },
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double width;
  final double height;

  const _Skeleton({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _NetworkStatusChip extends StatelessWidget {
  final CampusNetworkStatus? status;
  final bool loading;
  final VoidCallback? onPressed;

  const _NetworkStatusChip({
    required this.status,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 76,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final label = _networkStatusLabel(status);

    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center, softWrap: true),
    );
  }
}

Future<void> showNetworkStatusSheet(
  BuildContext context, {
  required CampusNetworkStatus? status,
  required Future<CampusNetworkStatus?> Function() refresh,
}) {
  return showAppBottomSheet<void>(
    context: context,
    scrollBody: true,
    builder: (_) => _NetworkStatusSheet(status: status, refresh: refresh),
  );
}

class _NetworkStatusSheet extends StatefulWidget {
  final CampusNetworkStatus? status;
  final Future<CampusNetworkStatus?> Function() refresh;

  const _NetworkStatusSheet({required this.status, required this.refresh});

  @override
  State<_NetworkStatusSheet> createState() => _NetworkStatusSheetState();
}

class _NetworkStatusSheetState extends State<_NetworkStatusSheet> {
  CampusNetworkStatus? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final next = await widget.refresh();
    if (!mounted) return;
    setState(() {
      _status = next;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '网络环境',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    title: const Text('当前网络'),
                    trailing: Text(
                      _status?.inWhiteList == true
                          ? '校园网'
                          : _status == null
                          ? '不可用'
                          : '校外网',
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    dense: true,
                    title: const Text('本机 IP'),
                    trailing: Text(_status?.ip ?? '不可用'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _refresh,
                icon:
                    _loading
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.refresh),
                label: Text(_loading ? '检测中' : '重新检测'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
