import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../capabilities/qr_scanner_capability.dart';

/// 从二维码内容里提取设备号，规则与源站 `scan.html` 一致：
///
/// 1. URL 形式的 `?id=` / `?deviceId=` / `?sn=` / `?code=` 取参数值；
/// 2. 整段就是 `[A-Za-z0-9_-]{2,64}` 的，直接当设备号；
/// 3. 其余一律返回 null（不是桩上的二维码，静默忽略）。
///
/// 结果统一转大写，与目录里的设备 id 对齐。
String? chargingPileDeviceIdFromScan(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final match = RegExp(
    r'[?&#](?:id|deviceid|device_id|sn|code)=([^&#\s]+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match != null) {
    final value = match.group(1);
    if (value == null) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(value);
    } on ArgumentError {
      decoded = value;
    }
    final trimmed = decoded.trim();
    return trimmed.isEmpty ? null : trimmed.toUpperCase();
  }
  if (RegExp(r'^[A-Za-z0-9_-]{2,64}$').hasMatch(text)) {
    return text.toUpperCase();
  }
  return null;
}

/// 扫到的设备号 + 是否已在目录里。
class ChargingPileScannedCode {
  const ChargingPileScannedCode({required this.deviceId, required this.known});

  final String deviceId;
  final bool known;
}

/// 扫码采设备号面板。
///
/// 行为对齐源站：连续扫码、按设备号去重、站里已有的标绿、没接入的标琥珀，
/// 最后「复制全部」把编号按行发给加桩的人。
class ChargingPileScanSheet extends StatefulWidget {
  const ChargingPileScanSheet({
    super.key,
    required this.knownDeviceIds,
    this.scanner,
    this.scannerTitle = '扫码采设备号',
    this.scannerPrompt = '对准桩身上的二维码，识别后继续扫下一台',
  });

  /// 目录里已有的设备号（大写），用于区分「已接入 / 未接入」。
  final Set<String> knownDeviceIds;

  /// 测试注入；默认用宿主的扫码能力。
  final QrScannerCapability? scanner;

  final String scannerTitle;
  final String scannerPrompt;

  @override
  State<ChargingPileScanSheet> createState() => _ChargingPileScanSheetState();
}

class _ChargingPileScanSheetState extends State<ChargingPileScanSheet> {
  final List<ChargingPileScannedCode> _codes = [];
  final Set<String> _seen = {};
  bool _scanning = false;

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final result = await (widget.scanner ?? qrScannerCapability).scan(
        context,
        QrScanRequest<String>(
          title: widget.scannerTitle,
          prompt: widget.scannerPrompt,
          decoder: (symbol) {
            final id = chargingPileDeviceIdFromScan(symbol.rawValue);
            return id == null
                ? const QrDecodeResult<String>.failure('这不是充电桩的二维码')
                : QrDecodeResult<String>.success(id);
          },
        ),
      );
      if (!mounted || result == null) return;
      if (!_seen.add(result)) {
        _toast('$result 已经扫过了');
        return;
      }
      final known = widget.knownDeviceIds.contains(result);
      setState(() {
        _codes.add(ChargingPileScannedCode(deviceId: result, known: known));
      });
      unawaited(HapticFeedback.selectionClick());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _copyAll() async {
    if (_codes.isEmpty) {
      _toast('还没有扫到编号');
      return;
    }
    final text = _codes.map((code) => code.deviceId).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast('已复制 ${_codes.length} 个编号');
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('扫码采设备号', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '对着桩身上的二维码扫，自动提取编号并去重。绿色是已接入的，琥珀色是还没接入的。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(_scanning ? '识别中…' : '扫码'),
              ),
            ),
            if (_codes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '已扫 ${_codes.length} 台',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final code in _codes)
                        Chip(
                          label: Text(
                            code.known
                                ? code.deviceId
                                : '${code.deviceId} · 未接入',
                          ),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: code.known
                                ? colors.primary.withValues(alpha: 0.4)
                                : colors.tertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _codes.clear();
                      _seen.clear();
                    }),
                    child: const Text('清空'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _copyAll,
                    child: const Text('复制全部'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 打开扫码面板。返回时携带本次扫到的编号（按扫码顺序）。
Future<List<ChargingPileScannedCode>> showChargingPileScan(
  BuildContext context, {
  required Set<String> knownDeviceIds,
  QrScannerCapability? scanner,
}) async {
  final result = await showModalBottomSheet<List<ChargingPileScannedCode>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (context) => ChargingPileScanSheet(
          knownDeviceIds: knownDeviceIds,
          scanner: scanner,
        ),
  );
  return result ?? const <ChargingPileScannedCode>[];
}
