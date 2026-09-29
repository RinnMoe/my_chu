import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';
import '../theme/app_palette.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    AppLogger.addListener(_onLogUpdated);
  }

  @override
  void dispose() {
    AppLogger.removeListener(_onLogUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogUpdated() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Color _levelColor(BuildContext context, String level) {
    final semantic = AppSemanticColors.of(context);
    return switch (level) {
      'ERROR' => semantic.danger,
      'WARN' => semantic.warning,
      _ => semantic.success,
    };
  }

  Future<void> _copyAll() async {
    final text = AppLogger.entries.map((e) => e.toSafeLine()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    final entries = AppLogger.entries;

    final body = _buildBody(context, entries);

    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(
          title: const Text('日志'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制全部',
              onPressed: _copyAll,
            ),
            PopupMenuButton<String>(
              onSelected: (action) {
                switch (action) {
                  case 'clear':
                    AppLogger.clear();
                  case 'toggle_scroll':
                    setState(() => _autoScroll = !_autoScroll);
                }
              },
              itemBuilder:
                  (context) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20),
                          SizedBox(width: 8),
                          Text('清空日志'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle_scroll',
                      child: Row(
                        children: [
                          Icon(
                            _autoScroll ? Icons.lock : Icons.lock_open,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(_autoScroll ? '暂停滚动' : '自动滚动'),
                        ],
                      ),
                    ),
                  ],
            ),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, List<LogEntry> entries) {
    return entries.isEmpty
        ? const Center(child: Text('暂无日志'))
        : ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.toSafeLine(),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: _levelColor(context, entry.level),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }
}
