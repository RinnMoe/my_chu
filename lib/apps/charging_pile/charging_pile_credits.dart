import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../charging_piles/charging_pile_credits_service.dart';

Future<void> showChargingPileCredits(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => const _ChargingPileCreditsDialog(),
  );
}

Future<void> _openCreditsLink(BuildContext context, Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    /* Never display raw platform failures. */
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
  }
}

class _ChargingPileCreditsDialog extends StatefulWidget {
  const _ChargingPileCreditsDialog();
  @override
  State<_ChargingPileCreditsDialog> createState() =>
      _ChargingPileCreditsDialogState();
}

class _ChargingPileCreditsDialogState
    extends State<_ChargingPileCreditsDialog> {
  final _service = ChargingPileCreditsService();
  late Future<List<ChargingPileCreditParagraph>> _content;

  @override
  void initState() {
    super.initState();
    _content = _service.load();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).vertical -
        MediaQuery.paddingOf(context).vertical;
    return AlertDialog(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: (availableHeight * 0.8).clamp(0.0, 640.0).toDouble(),
      ),
      title: const Text('致谢&贡献名单'),
      content: SingleChildScrollView(
        child: SelectionArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本功能由@长歌开发，@Rinn和@znm2500完成MyCHU移植。'),
              const SizedBox(height: 16),
              const Text('以下为原项目致谢&贡献名单'),
              const SizedBox(height: 16),
              FutureBuilder<List<ChargingPileCreditParagraph>>(
                future: _content,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('原项目名单暂时无法加载。'),
                        TextButton.icon(
                          onPressed:
                              () => setState(() => _content = _service.load()),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        snapshot.data!
                            .map(
                              (paragraph) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _CreditParagraph(paragraph: paragraph),
                              ),
                            )
                            .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed:
              () => _openCreditsLink(
                context,
                Uri.parse('https://github.com/Qishihe/longsong-chd-charger'),
              ),
          child: const Text('查看本功能Github'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _CreditParagraph extends StatelessWidget {
  const _CreditParagraph({required this.paragraph});
  final ChargingPileCreditParagraph paragraph;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (paragraph.bullet) const TextSpan(text: '• '),
          ...paragraph.text.map((part) {
            final textStyle = style.copyWith(
              fontWeight: part.bold ? FontWeight.w600 : style.fontWeight,
            );
            final uri = part.link;
            if (uri == null) return TextSpan(text: part.text, style: textStyle);
            return WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Semantics(
                link: true,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 48),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () => _openCreditsLink(context, uri),
                  child: Text(
                    part.text,
                    style: textStyle.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
