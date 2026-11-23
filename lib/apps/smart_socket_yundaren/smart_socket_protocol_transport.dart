import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../services/logging/logger.dart';

class BleTransportException implements Exception {
  final String message;
  final String? userMessage;

  const BleTransportException(this.message, {this.userMessage});

  @override
  String toString() => message;
}

abstract interface class BleProtocolTransport {
  Stream<List<int>> get notifications;

  Stream<void> get unexpectedDisconnects;

  /// Prepares the target address, scanning only when the transport needs it.
  Future<void> scanForTarget(String mac);

  Future<void> connect();

  Future<void> discoverAndSubscribe();

  Future<void> writeAscii(String frame);

  Future<void> disconnect();

  Future<void> dispose();
}

typedef BleSupportReader = Future<bool> Function();
typedef BleAdapterStateReader = Future<BluetoothAdapterState> Function();

List<List<int>> splitBleWriteChunks(List<int> bytes) {
  return [
    for (var offset = 0; offset < bytes.length; offset += 20)
      bytes.sublist(offset, min(offset + 20, bytes.length)),
  ];
}

class FlutterBlueProtocolTransport implements BleProtocolTransport {
  final BleSupportReader _readSupport;
  final BleAdapterStateReader _readAdapterState;
  final StreamController<List<int>> _notificationController =
      StreamController<List<int>>.broadcast(sync: true);
  final StreamController<void> _disconnectController =
      StreamController<void>.broadcast(sync: true);

  BluetoothDevice? _device;
  Completer<BluetoothDevice?>? _scanTarget;
  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<List<int>>? _notificationSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  bool _connected = false;
  bool _intentionalDisconnect = false;
  bool _disposed = false;

  FlutterBlueProtocolTransport({
    BleSupportReader? supportReader,
    BleAdapterStateReader? adapterStateReader,
  }) : _readSupport = supportReader ?? (() => FlutterBluePlus.isSupported),
       _readAdapterState =
           adapterStateReader ?? (() => FlutterBluePlus.adapterState.first);

  @override
  Stream<List<int>> get notifications => _notificationController.stream;

  @override
  Stream<void> get unexpectedDisconnects => _disconnectController.stream;

  @override
  Future<void> scanForTarget(String mac) async {
    _ensureActive();
    if (!await _readSupport()) {
      throw const BleTransportException(
        '当前设备不支持 BLE',
        userMessage: '此手机无法连接该插座',
      );
    }
    final adapterState = await _readLiveAdapterState();
    if (adapterState != BluetoothAdapterState.on) {
      throw const BleTransportException('蓝牙未开启', userMessage: '蓝牙未开启，请开启后重试');
    }
    _ensureActive();
    _device = BluetoothDevice.fromId(_formatMac(_normalizeMac(mac)));
  }

  Future<BluetoothDevice> _scanForTarget(String target) async {
    await FlutterBluePlus.stopScan();
    _ensureActive();
    final found = _scanTarget = Completer<BluetoothDevice?>();
    found.future.ignore(); // Native scan errors may arrive during startScan.
    late final StreamSubscription<List<ScanResult>> subscription;
    subscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final result in results) {
          if (_normalizeMac(result.device.remoteId.str) == target &&
              !found.isCompleted) {
            found.complete(result.device);
            break;
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(error, stackTrace: stackTrace);
        if (!found.isCompleted) found.completeError(error, stackTrace);
      },
    );

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        continuousUpdates: true,
        continuousDivisor: 2,
        removeIfGone: const Duration(seconds: 5),
        androidUsesFineLocation: true,
      );
      final device = await found.future.timeout(
        const Duration(seconds: 12),
        onTimeout:
            () =>
                throw const BleTransportException(
                  'BLE 直连失败，扫描时也未找到插座',
                  userMessage: '未找到插座',
                ),
      );
      return device ?? (throw const BleTransportException('蓝牙连接已关闭'));
    } on BleTransportException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      rethrow;
    } catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      throw BleTransportException(
        '扫描目标设备失败（${error.runtimeType}）',
        userMessage: '查找插座失败',
      );
    } finally {
      _scanTarget = null;
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  @override
  Future<void> connect() async {
    _ensureActive();
    var device = _device;
    if (device == null) {
      throw const BleTransportException('尚未找到目标设备');
    }
    _intentionalDisconnect = false;
    try {
      await device.connect(timeout: const Duration(seconds: 8), mtu: null);
    } catch (error, stack) {
      AppLogger.error(error, stackTrace: stack);
      _ensureActive();
      // FlutterBluePlus cancels timed-out GATT attempts itself.
      device = await _scanForTarget(_normalizeMac(device.remoteId.str));
      _ensureActive();
      _device = device;
      try {
        await device.connect(timeout: const Duration(seconds: 15), mtu: null);
      } catch (error, stack) {
        AppLogger.error(error, stackTrace: stack);
        throw const BleTransportException(
          '已找到插座，但 BLE 连接失败',
          userMessage: '无法连接插座',
        );
      }
    }
    _ensureActive();
    if (!device.isConnected) {
      throw const BleTransportException('插座的 BLE 连接已断开', userMessage: '连接中断');
    }
    _connected = true;
    _connectionSubscription = device.connectionState.listen((state) {
      final wasConnected = _connected;
      _connected = state == BluetoothConnectionState.connected;
      if (wasConnected && !_connected && !_intentionalDisconnect) {
        _disconnectController.add(null);
      }
    });
  }

  @override
  Future<void> discoverAndSubscribe() async {
    _ensureActive();
    final device = _device;
    if (device == null || !_connected) {
      throw const BleTransportException('BLE 设备未连接');
    }
    try {
      final services = await device.discoverServices();
      final service =
          services.where((item) => item.uuid == Guid('FF00')).firstOrNull;
      if (service == null) {
        throw const BleTransportException('设备缺少 FF00 服务');
      }
      final notify =
          service.characteristics
              .where((item) => item.uuid == Guid('FF01'))
              .firstOrNull;
      final write =
          service.characteristics
              .where((item) => item.uuid == Guid('FF02'))
              .firstOrNull;
      if (notify == null || !notify.properties.notify) {
        throw const BleTransportException('设备缺少可通知的 FF01 特征');
      }
      if (write == null || !write.properties.writeWithoutResponse) {
        throw const BleTransportException('设备缺少可无响应写入的 FF02 特征');
      }
      _ensureActive();
      _writeCharacteristic = write;
      _notificationSubscription = notify.onValueReceived.listen(
        _notificationController.add,
        onError: _notificationController.addError,
      );
      await notify.setNotifyValue(true);
    } on BleTransportException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      rethrow;
    } catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      throw BleTransportException('发现 GATT 服务失败（${error.runtimeType}）');
    }
  }

  @override
  Future<void> writeAscii(String frame) async {
    _ensureActive();
    final characteristic = _writeCharacteristic;
    if (characteristic == null || !_connected) {
      throw const BleTransportException('FF02 尚未准备完成');
    }
    final bytes = ascii.encode(frame);
    try {
      for (final chunk in splitBleWriteChunks(bytes)) {
        await characteristic.write(chunk, withoutResponse: true);
      }
    } catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      throw BleTransportException('写入 FF02 失败（${error.runtimeType}）');
    }
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    final scan = _scanTarget;
    if (scan != null && !scan.isCompleted) scan.complete(null);
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    final device = _device;
    if (device != null) {
      try {
        await device.disconnect(queue: false);
      } catch (diagnosticError, diagnosticStack) {
        AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
        // Local teardown remains best-effort when the adapter is already off.
      }
    }
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connected = false;
    _writeCharacteristic = null;
    _device = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _notificationController.close();
    await _disconnectController.close();
  }

  void _ensureActive() {
    if (_disposed) throw const BleTransportException('BLE 连接已关闭');
  }

  Future<BluetoothAdapterState> _readLiveAdapterState() async {
    try {
      // adapterStateNow is only a cache and is unknown until the plugin has
      // emitted its first platform state. Reading the stream's first value
      // initializes that state from the Android adapter before scanning.
      return await _readAdapterState();
    } catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      throw BleTransportException('读取蓝牙状态失败（${error.runtimeType}）');
    }
  }

  static String _normalizeMac(String value) =>
      value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();

  static String _formatMac(String value) => [
    for (var index = 0; index < value.length; index += 2)
      value.substring(index, min(index + 2, value.length)),
  ].join(':');
}
