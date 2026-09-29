import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleTransportException implements Exception {
  final String message;

  const BleTransportException(this.message);

  @override
  String toString() => message;
}

abstract interface class BleProtocolTransport {
  Stream<List<int>> get notifications;

  Stream<void> get unexpectedDisconnects;

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
      throw const BleTransportException('当前设备不支持 BLE');
    }
    final adapterState = await _readLiveAdapterState();
    if (adapterState != BluetoothAdapterState.on) {
      throw const BleTransportException('蓝牙未开启，请开启后重试');
    }

    await FlutterBluePlus.stopScan();
    final target = _normalizeMac(mac);
    final found = Completer<BluetoothDevice>();
    late final StreamSubscription<List<ScanResult>> subscription;
    subscription = FlutterBluePlus.scanResults.listen(
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
      _device = await found.future.timeout(
        const Duration(seconds: 12),
        onTimeout:
            () =>
                throw BleTransportException(
                  '12 秒内未找到二维码设备 ${_formatMac(target)}',
                ),
      );
    } on BleTransportException {
      rethrow;
    } catch (error) {
      throw BleTransportException('扫描目标设备失败（${error.runtimeType}）');
    } finally {
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  @override
  Future<void> connect() async {
    _ensureActive();
    final device = _device;
    if (device == null) {
      throw const BleTransportException('尚未找到目标设备');
    }
    _intentionalDisconnect = false;
    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      final wasConnected = _connected;
      _connected = state == BluetoothConnectionState.connected;
      if (wasConnected && !_connected && !_intentionalDisconnect) {
        _disconnectController.add(null);
      }
    });
    try {
      await device.connect(
        timeout: const Duration(seconds: 15),
        mtu: null,
        autoConnect: false,
      );
      _connected = true;
    } catch (error) {
      throw BleTransportException('连接设备失败（${error.runtimeType}）');
    }
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
      _writeCharacteristic = write;
      await _notificationSubscription?.cancel();
      _notificationSubscription = notify.onValueReceived.listen(
        _notificationController.add,
        onError: _notificationController.addError,
      );
      await notify.setNotifyValue(true);
    } on BleTransportException {
      rethrow;
    } catch (error) {
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
    } catch (error) {
      throw BleTransportException('写入 FF02 失败（${error.runtimeType}）');
    }
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    await FlutterBluePlus.stopScan();
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    final device = _device;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {
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
    } catch (error) {
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
