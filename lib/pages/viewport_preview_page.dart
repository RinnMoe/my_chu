import 'package:flutter/material.dart';

import '../capabilities/dev_visibility.dart';
import '../services/viewport_preview_service.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class ViewportPreviewPage extends StatelessWidget {
  const ViewportPreviewPage({super.key});

  Future<void> _editCustomSize(BuildContext context) async {
    final current = ViewportPreviewService.config.value;

    final widthController = TextEditingController(
      text: (current?.portraitWidth ?? 390).toStringAsFixed(0),
    );
    final heightController = TextEditingController(
      text: (current?.portraitHeight ?? 844).toStringAsFixed(0),
    );
    void apply(BuildContext dialogContext) {
      final width = double.tryParse(widthController.text);
      final height = double.tryParse(heightController.text);
      if (width == null || height == null) return;
      Navigator.of(dialogContext).pop((width, height));
    }

    Widget buildDialog(BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('自定义 iPhone 尺寸'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widthController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '宽度（320–500dp）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: heightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '高度（568–1000dp）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => apply(dialogContext),
            child: const Text('应用'),
          ),
        ],
      );
    }

    final result = await showDialog<(double, double)>(
      context: context,
      builder: buildDialog,
    );
    widthController.dispose();
    heightController.dispose();
    if (!context.mounted || result == null) return;
    try {
      ViewportPreviewService.setCustom(width: result.$1, height: result.$2);
    } on RangeError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尺寸超出范围，请输入 320–500 × 568–1000dp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('iPhone 视图模拟')),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    return ValueListenableBuilder<ViewportPreviewConfig?>(
      valueListenable: ViewportPreviewService.config,
      builder: (context, config, _) {
        final isEnabled = config != null;
        final selectedPreset =
            ViewportPreviewService.presets
                .where(
                  (preset) =>
                      config?.portraitWidth == preset.width &&
                      config?.portraitHeight == preset.height,
                )
                .map((preset) => preset.id)
                .firstOrNull;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Expanded(
                          child: Text(
                            '只在 DEV 中生效',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        DevBadge(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '在 iPad 上约束完整应用为 iPhone 逻辑尺寸，用于检查 compact 布局。重启应用后自动恢复真实 iPad 视图。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('启用 iPhone 视图'),
                    subtitle: Text(
                      isEnabled
                          ? '当前 ${config.width.toInt()} × ${config.height.toInt()}dp'
                          : '当前使用真实设备窗口',
                    ),
                    value: isEnabled,
                    onChanged: (value) {
                      if (value) {
                        ViewportPreviewService.enable();
                      } else {
                        ViewportPreviewService.disable();
                      }
                    },
                  ),
                  if (isEnabled) ...[
                    const Divider(height: 1, indent: 16),
                    ListTile(
                      title: const Text('尺寸预设'),
                      trailing: SizedBox(
                        width: 210,
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedPreset,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('自定义尺寸'),
                          items: [
                            for (final preset in ViewportPreviewService.presets)
                              DropdownMenuItem(
                                value: preset.id,
                                child: Text(preset.label),
                              ),
                          ],
                          onChanged: (id) {
                            if (id != null) {
                              ViewportPreviewService.enablePreset(id);
                            }
                          },
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('自定义尺寸'),
                      subtitle: const Text('宽 320–500dp，高 568–1000dp'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _editCustomSize(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      title: const Text('横向'),
                      subtitle: const Text('交换宽高并使用横向安全区'),
                      value:
                          config.orientation == ViewportOrientation.landscape,
                      onChanged: (value) {
                        ViewportPreviewService.setOrientation(
                          value
                              ? ViewportOrientation.landscape
                              : ViewportOrientation.portrait,
                        );
                      },
                    ),
                    ListTile(
                      title: const Text('Safe Area 模板'),
                      trailing: DropdownButton<ViewportSafeAreaTemplate>(
                        value: config.safeAreaTemplate,
                        items: [
                          for (final template
                              in ViewportSafeAreaTemplate.values)
                            DropdownMenuItem(
                              value: template,
                              child: Text(template.label),
                            ),
                        ],
                        onChanged: (template) {
                          if (template != null) {
                            ViewportPreviewService.setSafeAreaTemplate(
                              template,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isEnabled) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: ViewportPreviewService.disable,
                icon: const Icon(Icons.phone_iphone),
                label: const Text('恢复真实 iPad 视图'),
              ),
            ],
          ],
        );
      },
    );
  }
}
