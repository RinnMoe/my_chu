import 'package:flutter/material.dart';

class AppreciationPage extends StatelessWidget {
  const AppreciationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(height: 1.6);
    return Scaffold(
      appBar: AppBar(title: const Text('赞赏')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('赞赏完全自愿，MyCHU是免费项目。', style: textStyle),
                  const SizedBox(height: 16),
                  Text(
                    '若您希望对本项目开发工作进行赞助，请在备注中注明【MyCHU开发赞助】以及您的称呼或联系邮箱，您的赞助金将完全用于MyCHU相关开发并会在赞助者栏中展示。',
                    style: textStyle,
                  ),
                  const SizedBox(height: 24),
                  Image.asset(
                    'assets/images/appreciation_wechat.png',
                    fit: BoxFit.contain,
                    semanticLabel: 'Rinn 的微信赞赏码',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
