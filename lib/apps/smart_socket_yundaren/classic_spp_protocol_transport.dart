import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../services/logging/logger.dart';
import 'smart_socket_protocol.dart';
import 'smart_socket_protocol_transport.dart';

class ClassicSppProtocolTransport implements BleProtocolTransport {
  static const _channel = MethodChannel('mychu/classic_bluetooth');
  static int _nextSession = 0;

  final _notifications = StreamController<List<int>>.broadcast();
  final _disconnects = StreamController<void>.broadcast();
  String? _address;
  int? _session;
  bool _disposed = false;

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Stream<void> get unexpectedDisconnects => _disconnects.stream;

  @override
  Future<void> scanForTarget(String mac) async {
    if (_disposed) throw const BleTransportException('蓝牙连接已关闭');
    _address = formatMac(hexToBytes(mac));
  }

  @override
  Future<void> connect() async {
    final address = _address;
    if (_disposed || address == null) {
      throw const BleTransportException('蓝牙连接已关闭');
    }
    final session = ++_nextSession;
    _session = session;
    try {
      await _invoke<void>('connect', session, {
        'address': address,
      }).timeout(const Duration(seconds: 75));
      if (_session != session) {
        throw const BleTransportException('蓝牙连接已关闭');
      }
    } on TimeoutException {
      await disconnect();
      throw const BleTransportException('经典蓝牙连接超时', userMessage: '连接插座超时');
    } catch (_) {
      if (_session == session) _session = null;
      rethrow;
    }
  }

  @override
  Future<void> discoverAndSubscribe() async {
    unawaited(_read(_requireSession()));
  }

  Future<void> _read(int session) async {
    try {
      while (_session == session) {
        final bytes = await _invoke<Uint8List>('read', session);
        if (_session != session) return;
        if (bytes == null || bytes.isEmpty) {
          throw const BleTransportException('经典蓝牙连接已断开', userMessage: '连接中断');
        }
        _notifications.add(bytes);
      }
    } on BleTransportException catch (error, stack) {
      if (_session != session) return;
      _notifications.addError(error, stack);
      _disconnects.add(null);
      await disconnect();
    }
  }

  @override
  Future<void> writeAscii(String frame) async {
    try {
      await _invoke<void>('write', _requireSession(), {
        'bytes': Uint8List.fromList(ascii.encode(frame)),
      }).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      await disconnect();
      throw const BleTransportException('经典蓝牙写入超时', userMessage: '与插座通信超时');
    }
  }

  int _requireSession() =>
      _session ?? (throw const BleTransportException('蓝牙连接已关闭'));

  Future<T?> _invoke<T>(
    String method,
    int session, [
    Map<String, Object>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, {
        'session': session,
        ...?arguments,
      });
    } on MissingPluginException catch (error) {
      throw BleTransportException(
        '经典蓝牙 $method 通道不可用：$error',
        userMessage: '此手机无法连接该插座',
      );
    } on PlatformException catch (error) {
      throw BleTransportException(
        '经典蓝牙 $method 失败：$error',
        userMessage: switch (error.code) {
          'unsupported' => '此手机无法连接该插座',
          'disabled' => '蓝牙未开启',
          'permission' => '需要蓝牙权限',
          'busy' => '已有连接正在进行',
          'invalid_address' => '无法识别此插座',
          'pair_failed' => '配对失败',
          'bond_timeout' => '配对超时',
          'closed' || 'disconnected' => '连接中断',
          'write_failed' => '无法与插座通信',
          _ => '无法连接插座',
        },
      );
    }
  }

  @override
  Future<void> disconnect() async {
    final session = _session;
    _session = null;
    _address = null;
    if (session == null) return;
    try {
      await _invoke<void>('close', session);
    } on BleTransportException catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
      // The native engine closes its socket when the channel detaches.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _notifications.close();
    await _disconnects.close();
  }
}
