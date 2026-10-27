import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../services/privacy_agreement_service.dart';
import '../services/public_http_client.dart';
import 'charging_pile_models.dart';

class ChargingPileCreditText {
  const ChargingPileCreditText(this.text, {this.bold = false, this.link});
  final String text;
  final bool bold;
  final Uri? link;
}

class ChargingPileCreditParagraph {
  ChargingPileCreditParagraph(
    List<ChargingPileCreditText> text, {
    this.bullet = false,
  }) : text = List.unmodifiable(text);
  final List<ChargingPileCreditText> text;
  final bool bullet;
}

/// Read-only source content. No scripts, embedded media or page controls are
/// rendered, and the source cannot provide instructions to the host.
class ChargingPileCreditsService {
  ChargingPileCreditsService({
    PublicHttpClient? httpClient,
    Future<bool> Function()? consent,
  }) : _http = httpClient ?? PublicHttpClient(),
       _consent = consent ?? PrivacyAgreementService.isAccepted;
  static final _source = Uri.parse('https://chd-charge.pages.dev/');
  final PublicHttpClient _http;
  final Future<bool> Function() _consent;
  final _cancellation = ChargingPileCancellation();

  Future<List<ChargingPileCreditParagraph>> load() async {
    _cancellation.check();
    if (!await _consent())
      throw const ChargingPileException(ChargingPileFailure.consentRequired);
    _cancellation.check();
    final response = await _http.get(
      _source,
      timeout: const Duration(seconds: 6),
      abortTrigger: _cancellation.whenCancelled,
    );
    _cancellation.check();
    if (!await _consent())
      throw const ChargingPileException(ChargingPileFailure.consentRequired);
    if (response.statusCode != 200 || response.bodyBytes.length > 2000000)
      throw const FormatException();
    final body = html
        .parse(utf8.decode(response.bodyBytes))
        .querySelector('#thanks-dialog > .dlg-body');
    if (body == null) throw const FormatException();
    final paragraphs = <ChargingPileCreditParagraph>[];
    var textLength = 0;
    for (final paragraph in body.querySelectorAll('p, li')) {
      final spans = <ChargingPileCreditText>[];
      void visit(dom.Node node, {bool bold = false, Uri? link}) {
        if (node is dom.Text) {
          final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
          textLength += text.length;
          if (textLength > 64000) throw const FormatException();
          spans.add(ChargingPileCreditText(text, bold: bold, link: link));
        } else if (node is dom.Element) {
          if ([
                'script',
                'style',
                'button',
                'iframe',
                'img',
              ].contains(node.localName) ||
              node.attributes.containsKey('hidden'))
            return;
          if (node.localName == 'br') {
            spans.add(const ChargingPileCreditText('\n'));
            return;
          }
          var target = link;
          if (node.localName == 'a') {
            final raw = node.attributes['href'];
            final parsed = raw == null ? null : Uri.tryParse(raw);
            final resolved = parsed == null ? null : _source.resolveUri(parsed);
            target =
                resolved != null &&
                        resolved.scheme == 'https' &&
                        resolved.host.isNotEmpty
                    ? resolved
                    : null;
          }
          for (final child in node.nodes) {
            visit(
              child,
              bold: bold || node.localName == 'b' || node.localName == 'strong',
              link: target,
            );
          }
        }
      }

      for (final node in paragraph.nodes) {
        visit(node);
      }
      if (spans.any((span) => span.text.trim().isNotEmpty)) {
        paragraphs.add(
          ChargingPileCreditParagraph(
            spans,
            bullet: paragraph.localName == 'li',
          ),
        );
      }
    }
    if (paragraphs.isEmpty) throw const FormatException();
    return List.unmodifiable(paragraphs);
  }

  void close() {
    _cancellation.cancel();
    _http.close();
  }
}
