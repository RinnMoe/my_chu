import 'package:flutter/material.dart';
import '../widgets/diagnostics_entries.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('日志与崩溃报告')),
    body: const SingleChildScrollView(child: DiagnosticsEntries()),
  );
}
