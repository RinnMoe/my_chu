import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../capabilities/external_app_launcher.dart';
import '../../capabilities/host_login.dart';
import '../../capabilities/qr_scanner_capability.dart';
import '../../services/host_platform.dart';
import '../../services/tronclass_rollcall_store.dart';
import '../../services/user_error_message.dart';
import '../../services/logger_service.dart';
import 'tronclass_rollcall_models.dart';
import 'tronclass_rollcall_qr.dart';
import 'rollcall_code_input.dart';

class TronclassRollcallPage extends StatefulWidget {
  const TronclassRollcallPage({super.key, this.store, this.scanner});
  final TronclassRollcallStore? store;
  final QrScannerCapability? scanner;

  @override
  State<TronclassRollcallPage> createState() => _TronclassRollcallPageState();
}

class _TronclassRollcallPageState extends State<TronclassRollcallPage> {
  late final TronclassRollcallStore _store;
  final _code = TextEditingController();
  late int _identity;
  String? _selectedId;
  String? _message;
  bool _success = false;
  bool _ended = false;
  bool _working = false;
  bool _needsLogin = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? TronclassRollcallStore.instance;
    _identity = _store.identity;
    _store.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_identity != _store.identity) {
      _identity = _store.identity;
      _selectedId = null;
      _code.clear();
      _message = null;
      _success = false;
      _ended = false;
      _needsLogin = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit(
    TronclassRollcall item, {
    TronclassRollcallQr? qr,
  }) async {
    if (_working || _success || _ended) return;
    final identity = _identity;
    setState(() {
      _working = true;
      _message = null;
      _needsLogin = false;
    });
    try {
      final success =
          qr == null
              ? await _store.answerNumber(
                item,
                _code.text,
                expectedIdentity: identity,
              )
              : await _store.answerQr(item, qr, expectedIdentity: identity);
      if (!mounted || identity != _identity) return;
      if (success) {
        _code.clear();
        setState(() {
          _success = true;
          _message = '应答成功';
        });
      }
    } on RollcallException catch (error) {
      if (!mounted || identity != _identity) return;
      setState(() {
        _message = error.message;
        _ended = error.failure == RollcallFailure.ended;
        _needsLogin = error.failure == RollcallFailure.authentication;
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _scan(TronclassRollcall item) async {
    if (_working || _store.isSubmitting(item.id)) return;
    final identity = _identity;
    setState(() => _working = true);
    try {
      final result = await (widget.scanner ?? qrScannerCapability).scan(
        context,
        QrScanRequest<TronclassRollcallQr>(
          title: '扫码点名',
          prompt: '扫描当前点名二维码，识别成功后立即应答',
          decoder: (symbol) => decodeRollcallQr(symbol, item),
        ),
      );
      if (!mounted || identity != _identity) return;
      _working = false;
      if (result != null) await _submit(item, qr: result);
    } catch (error) {
      if (!mounted || identity != _identity) return;
      logUserFacingError(
        UserErrorContext.network,
        error,
        operationId: UserOperationId.tronclassRollcallAnswer,
      );
      setState(() => _message = '扫码暂时无法使用，请重试。');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openTronclass() async {
    final supported = !kIsWeb && HostPlatform.current == HostPlatform.android;
    final opened =
        supported &&
        await ExternalAppLauncher().launchPackage('com.wisdomgarden.trpc');
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(supported ? '无法打开畅课，请确认已安装后手动打开。' : '请手动打开畅课 App 完成点名。'),
      ),
    );
  }

  void _choose(TronclassRollcall item) {
    setState(() {
      _selectedId = item.id;
      _code.clear();
      _message = null;
      _success = false;
      _ended = false;
      _needsLogin = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _store.items;
    final selected =
        items.where((item) => item.id == _selectedId).firstOrNull ??
        (_selectedId == null && items.length == 1 ? items.single : null);
    final busy =
        _working || (selected != null && _store.isSubmitting(selected.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('畅课签到'),
        actions: [
          IconButton(
            tooltip: '刷新签到',
            onPressed: busy || _store.loading ? null : () => _store.refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_store.loading) const LinearProgressIndicator(),
                if (_store.error != null) ...[
                  Text(_store.error!.message),
                  if (_store.error!.failure == RollcallFailure.authentication)
                    TextButton(
                      onPressed: () => HostLogin.open(context),
                      child: const Text('重新登录'),
                    ),
                  const SizedBox(height: 16),
                ],
                if (_success || _ended) ...[
                  Icon(
                    _success
                        ? Icons.check_circle_outline
                        : Icons.event_busy_outlined,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (items.isNotEmpty)
                    TextButton(
                      onPressed:
                          () => setState(() {
                            _selectedId = null;
                            _success = false;
                            _ended = false;
                            _message = null;
                          }),
                      child: const Text('查看其他点名'),
                    ),
                ] else if (selected != null) ...[
                  Text(
                    selected.courseTitle.isEmpty
                        ? '课程点名'
                        : selected.courseTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(selected.typeLabel),
                  const SizedBox(height: 24),
                  if (selected.type == TronclassRollcallType.number) ...[
                    RollcallCodeInput(
                      controller: _code,
                      enabled: !busy,
                      onChanged: () => setState(() {}),
                      onSubmitted: () {
                        if (!busy &&
                            RegExp(r'^[0-9]{4}$').hasMatch(_code.text)) {
                          _submit(selected);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed:
                          busy || !RegExp(r'^[0-9]{4}$').hasMatch(_code.text)
                              ? null
                              : () => _submit(selected),
                      child: const Text('应答点名'),
                    ),
                  ] else if (selected.type == TronclassRollcallType.qr)
                    FilledButton.icon(
                      onPressed: busy ? null : () => _scan(selected),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫一扫'),
                    )
                  else
                    FilledButton(
                      onPressed: _openTronclass,
                      child: const Text('打开畅课 App'),
                    ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_message!),
                    ),
                  if (_needsLogin)
                    TextButton(
                      onPressed: () => HostLogin.open(context),
                      child: const Text('重新登录'),
                    ),
                  if (items.length > 1)
                    TextButton(
                      onPressed:
                          busy
                              ? null
                              : () => setState(() {
                                _selectedId = null;
                                _code.clear();
                                _message = null;
                              }),
                      child: const Text('选择其他点名'),
                    ),
                ] else if (items.isNotEmpty)
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.courseTitle.isEmpty ? '课程点名' : item.courseTitle,
                      ),
                      subtitle: Text(item.typeLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _choose(item),
                    )
                else if (!_store.loading)
                  const Text('暂无待应答点名，可下拉首页或点击刷新查看。'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
