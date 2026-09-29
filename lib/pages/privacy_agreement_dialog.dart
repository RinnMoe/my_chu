import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'privacy_policy_page.dart';

enum PrivacyAgreementDecision { accepted, declined }

Future<PrivacyAgreementDecision?> presentPrivacyAgreement(
  BuildContext context,
) {
  return showDialog<PrivacyAgreementDecision>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PrivacyAgreementDialog(),
  );
}

class PrivacyAgreementDialog extends StatefulWidget {
  const PrivacyAgreementDialog({super.key});

  @override
  State<PrivacyAgreementDialog> createState() => _PrivacyAgreementDialogState();
}

class _PrivacyAgreementDialogState extends State<PrivacyAgreementDialog> {
  late final TapGestureRecognizer _policyRecognizer;

  @override
  void initState() {
    super.initState();
    _policyRecognizer = TapGestureRecognizer()..onTap = _openPolicy;
  }

  @override
  void dispose() {
    _policyRecognizer.dispose();
    super.dispose();
  }

  void _openPolicy() => _pushPage(const PrivacyPolicyPage());

  void _pushPage(Widget page) {
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(builder: (_) => page);
    unawaited(navigator.push<void>(route));
  }

  TextSpan _content(BuildContext context) {
    final linkColor = Theme.of(context).colorScheme.primary;
    return TextSpan(
      children: [
        const TextSpan(text: '请阅读并理解《'),
        TextSpan(
          text: 'MyCHU 用户协议',
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
          ),
          recognizer: _policyRecognizer,
        ),
        const TextSpan(text: '》。同意本协议并继续使用 MyCHU，即表示您接受其中约定。'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('用户协议'),
      content: Text.rich(_content(context)),
      actions: [
        TextButton(
          onPressed:
              () =>
                  Navigator.of(context).pop(PrivacyAgreementDecision.declined),
          child: const Text('不同意'),
        ),
        FilledButton(
          onPressed:
              () =>
                  Navigator.of(context).pop(PrivacyAgreementDecision.accepted),
          child: const Text('同意'),
        ),
      ],
    );
  }
}
