import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../services/deepseek_balance_service.dart';
import '../../services/deepseek_speech_service.dart';
import '../../services/file_save_service.dart';

import '../../services/logging/logger.dart';
import 'chat_demo_page.dart';

/// Android 原生 WebMessageListener 的最小宿主桥。
///
/// 只向同源主 Frame 暴露已注册的宿主方法。
/// OHOS 当前插件的 WebMessageListener 是 JS 模拟，不提供真实 Frame 来源，
/// 因此不会创建此桥。
class ChatDemoBridge {
  ChatDemoBridge({
    required this.controller,
    required this.origin,
    required this.onClose,
    required this.onOpenSettings,
  });

  final InAppWebViewController controller;
  final String origin;
  final Future<bool> Function() onClose;
  final bool Function() onOpenSettings;

  WebMessageListener? _listener;

  Future<bool> attach() async {
    if (!Platform.isAndroid) return false;
    try {
      final listener = WebMessageListener(
        jsObjectName: 'MyCHUBridge',
        allowedOriginRules: {origin},
        onPostMessage: _onPostMessage,
      );
      await controller.addWebMessageListener(listener);
      _listener = listener;
      return true;
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    }
  }

  void _onPostMessage(
    WebMessage? message,
    WebUri? sourceOrigin,
    bool isMainFrame,
    dynamic replyProxy,
  ) {
    final source = sourceOrigin?.toString().replaceFirst(RegExp(r'/$'), '');
    if (!isMainFrame || source != origin) {
      _reply(replyProxy, null, error: 'untrusted_source');
      return;
    }
    final data = message?.data;
    if (data is! String) {
      _reply(replyProxy, null, error: 'invalid_message');
      return;
    }
    Map<String, dynamic> request;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        _reply(replyProxy, null, error: 'invalid_message');
        return;
      }
      request = decoded;
    } on Object {
      _reply(replyProxy, null, error: 'invalid_message');
      return;
    }

    final id = request['id'];
    final method = request['method'];
    if (id is! String || method is! String) {
      _reply(replyProxy, null, error: 'invalid_message');
      return;
    }

    unawaited(_dispatch(id, method, request['params'], replyProxy));
  }

  Future<void> _dispatch(
    String id,
    String method,
    Object? params,
    dynamic replyProxy,
  ) async {
    try {
      switch (method) {
        case 'host.close':
          final closed = await onClose();
          _reply(replyProxy, closed, id: id);
          return;
        case 'host.openDeepSeekSettings':
          _reply(replyProxy, onOpenSettings(), id: id);
          return;
        case 'host.hello':
          _reply(replyProxy, {
            'bridgeProtocol': chatDemoBridgeProtocol,
            'mode': 'full',
          }, id: id);
          return;
        case 'files.save':
          await _saveFile(id, params, replyProxy);
          return;
        case 'balance.get':
          final balance = await const DeepSeekBalanceService().fetch();
          _reply(replyProxy, {
            'currency': balance.currency,
            'totalBalance': balance.totalBalance,
          }, id: id);
          return;
        case 'speech.transcribe':
          await _transcribe(id, params, replyProxy);
          return;
        default:
          _reply(replyProxy, null, id: id, error: 'unsupported_method');
      }
    } on Object catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      _reply(replyProxy, null, id: id, error: 'host_error');
    }
  }

  Future<void> _transcribe(
    String id,
    Object? params,
    dynamic replyProxy,
  ) async {
    if (params is! Map) {
      _reply(replyProxy, null, id: id, error: 'invalid_params');
      return;
    }
    final encoded = params['base64'];
    final name = params['name'];
    if (encoded is! String) {
      _reply(replyProxy, null, id: id, error: 'invalid_params');
      return;
    }
    List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } on Object {
      _reply(replyProxy, null, id: id, error: 'invalid_params');
      return;
    }
    if (bytes.length > 8 * 1024 * 1024) {
      _reply(replyProxy, null, id: id, error: 'file_too_large');
      return;
    }
    final text = await const DeepSeekSpeechService().transcribe(
      bytes,
      filename: name is String && name.isNotEmpty ? name : 'recording.wav',
    );
    _reply(replyProxy, {'text': text}, id: id);
  }

  Future<void> _saveFile(String id, Object? params, dynamic replyProxy) async {
    if (params is! Map) {
      _reply(replyProxy, null, id: id, error: 'invalid_params');
      return;
    }
    final name = params['name'];
    final encoded = params['base64'];
    if (name is! String || name.trim().isEmpty || encoded is! String) {
      _reply(replyProxy, null, id: id, error: 'invalid_params');
      return;
    }
    List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } on Object {
      _reply(replyProxy, null, id: id, error: 'invalid_params');
      return;
    }
    if (bytes.length > 32 * 1024 * 1024) {
      _reply(replyProxy, null, id: id, error: 'file_too_large');
      return;
    }
    final safeName = name.split(RegExp(r'[/\\]')).last;
    final path = await FileSaveService.saveToDownloads(
      fileName: safeName,
      bytes: bytes,
    );
    if (path == null || path.isEmpty) {
      _reply(replyProxy, null, id: id, error: 'save_failed');
      return;
    }
    _reply(replyProxy, true, id: id);
  }

  void _reply(dynamic replyProxy, Object? result, {String? id, String? error}) {
    final payload = <String, Object?>{
      if (id != null) 'id': id,
      'ok': error == null,
      if (error == null) 'result': result,
      if (error != null)
        'error': {
          'code': error,
          'message':
              error == 'unsupported_method'
                  ? 'Unsupported method'
                  : 'Host operation failed',
        },
    };
    unawaited(replyProxy.postMessage(WebMessage(data: jsonEncode(payload))));
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
