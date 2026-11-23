import 'dart:async';
import 'dart:math';

import '../../capabilities/east8_time.dart';
import '../../services/host_platform.dart';
import 'smart_socket_protocol.dart';
import 'smart_socket_protocol_transport.dart';
import 'ble_protocol_transport_ohos.dart';
import 'classic_spp_protocol_transport.dart';

import '../../services/logging/logger.dart';

BleProtocolTransport createDefaultBleProtocolTransport({
  HostPlatform? hostPlatform,
}) {
  if ((hostPlatform ?? HostPlatform.current) == HostPlatform.harmony) {
    return HarmonyBleProtocolTransport();
  }
  return FlutterBlueProtocolTransport();
}

BleProtocolTransport createSmartSocketTransport(
  BleQrInfo qr, {
  HostPlatform? hostPlatform,
}) {
  final platform = hostPlatform ?? HostPlatform.current;
  if (qr.usesBle) {
    return createDefaultBleProtocolTransport(hostPlatform: platform);
  }
  if (platform == HostPlatform.android) return ClassicSppProtocolTransport();
  throw const SmartSocketFailure('当前平台不支持经典蓝牙插座', userMessage: '此手机无法连接该插座');
}

enum SmartSocketPhase {
  scanning,
  connecting,
  discovering,
  querying,
  readingOrder,
  clearingOrder,
  verifyingIdle,
  preparingStart,
  sendingStart,
  running,
  disconnected,
}

class SmartSocketUpdate {
  final SmartSocketPhase phase;
  final String message;
  final String? frame;
  final BleDeviceInfo? device;
  final BleStoredOrder? order;

  const SmartSocketUpdate({
    required this.phase,
    required this.message,
    this.frame,
    this.device,
    this.order,
  });
}

class SmartSocketResult {
  final BleDeviceInfo device;
  final BleStoredOrder? clearedOrder;
  final BleStartPayload start;
  final int appRandom;

  const SmartSocketResult({
    required this.device,
    required this.clearedOrder,
    required this.start,
    required this.appRandom,
  });
}

class SmartSocketFailure implements Exception {
  final String message;
  final bool uncertainDeviceState;
  final String? userMessage;

  const SmartSocketFailure(
    this.message, {
    this.uncertainDeviceState = false,
    this.userMessage,
  });

  @override
  String toString() => message;
}

typedef SmartSocketUpdateCallback = void Function(SmartSocketUpdate update);

class SmartSocketProtocolService {
  final BleProtocolTransport? _injectedTransport;
  final BleProtocolTransport Function(BleQrInfo) _createTransport;
  final DateTime Function() _clock;
  final Random _random;
  final Duration commandTimeout;

  StreamSubscription<List<int>>? _notificationSubscription;
  StreamSubscription<void>? _disconnectSubscription;
  StreamController<BleFrame>? _frameController;
  final _disconnects = StreamController<void>.broadcast();
  BleProtocolTransport? _activeTransport;
  Future<void>? _disconnecting;
  bool _running = false;
  bool _disposed = false;

  SmartSocketProtocolService({
    BleProtocolTransport? transport,
    BleProtocolTransport Function(BleQrInfo)? transportFactory,
    DateTime Function()? clock,
    Random? random,
    this.commandTimeout = const Duration(seconds: 5),
  }) : _injectedTransport = transport,
       _createTransport = transportFactory ?? createSmartSocketTransport,
       _clock = clock ?? east8Now,
       _random = random ?? Random();

  Stream<void> get unexpectedDisconnects => _disconnects.stream;

  Future<SmartSocketResult> run(
    BleQrInfo qr, {
    SmartSocketUpdateCallback? onUpdate,
  }) async {
    if (_disposed) throw const SmartSocketFailure('插座连接页面已关闭');
    if (_running) throw const SmartSocketFailure('插座连接正在进行中');
    if (_activeTransport != null) {
      throw const SmartSocketFailure('请先断开上一次插座连接');
    }
    _running = true;
    try {
      if (_disconnecting case final pending?) await pending;
      if (_disposed) throw const SmartSocketFailure('插座连接页面已关闭');
      final transport = _injectedTransport ?? _createTransport(qr);
      _activeTransport = transport;
      _disconnectSubscription = transport.unexpectedDisconnects.listen((_) {
        if (!identical(_activeTransport, transport)) return;
        _frameController?.addError(
          const BleTransportException('蓝牙连接已断开', userMessage: '连接中断'),
        );
        _disconnects.add(null);
      });
      _emit(onUpdate, SmartSocketPhase.scanning, '正在准备蓝牙连接');
      await transport.scanForTarget(qr.effectiveAddress);
      _ensureCurrent(transport);
      _emit(onUpdate, SmartSocketPhase.connecting, '正在连接设备');
      await transport.connect();
      _ensureCurrent(transport);
      _listenForFrames(transport);
      _emit(onUpdate, SmartSocketPhase.discovering, '正在准备设备通信');
      await transport.discoverAndSubscribe();
      _ensureCurrent(transport);

      _emit(onUpdate, SmartSocketPhase.querying, '发送 0x23 查询设备状态');
      var device = BleDeviceInfo.fromFrame(
        await _exchange(0x23, const [0], onUpdate: onUpdate),
      );
      _verifyMac(qr, device);
      _emit(
        onUpdate,
        SmartSocketPhase.querying,
        device.isIdle ? '设备当前空闲' : '检测到设备旧记录',
        device: device,
      );

      BleStoredOrder? clearedOrder;
      if (!device.isIdle) {
        _emit(onUpdate, SmartSocketPhase.readingOrder, '发送 0x85 读取旧记录');
        clearedOrder = BleStoredOrder.fromFrame(
          await _exchange(0x85, const [0], onUpdate: onUpdate),
        );
        if (!qr.matchesMac(clearedOrder.mac)) {
          throw const SmartSocketFailure('旧记录 MAC 与二维码 MAC 不一致');
        }
        if (clearedOrder.productId != device.productId ||
            clearedOrder.deviceId != device.deviceId ||
            clearedOrder.accountId != device.accountId) {
          throw const SmartSocketFailure('旧记录身份字段与当前设备状态不一致');
        }
        _emit(
          onUpdate,
          SmartSocketPhase.readingOrder,
          '已读取旧记录 ${clearedOrder.timeIdText}',
          order: clearedOrder,
        );
        _emit(onUpdate, SmartSocketPhase.clearingOrder, '发送 0x86 自动确认旧记录');
        _expectAck(
          await _exchange(
            0x86,
            clearedOrder.buildClearPayload(),
            onUpdate: onUpdate,
            uncertainOnFailure: true,
          ),
          0x86,
        );

        _emit(onUpdate, SmartSocketPhase.verifyingIdle, '再次发送 0x23 验证空闲状态');
        final verified = BleDeviceInfo.fromFrame(
          await _exchange(0x23, const [0], onUpdate: onUpdate),
        );
        _verifyMac(qr, verified);
        // Both responses already matched the QR address, including its C0/00 alias.
        _verifyStableIdentity(device, verified);
        if (!verified.isIdle) {
          throw const SmartSocketFailure('0x86 后设备仍不是空闲状态');
        }
        device = verified;
        _emit(
          onUpdate,
          SmartSocketPhase.verifyingIdle,
          '旧记录已整理，设备状态为空闲',
          device: device,
        );
      }

      final appRandom = _random.nextInt(9001) + 1000;
      _emit(onUpdate, SmartSocketPhase.preparingStart, '正在生成 START 明文与 DES 密文');
      final start = BleStartProtocol.build(
        qr: qr,
        device: device,
        time: _clock(),
        appRandom: appRandom,
      );
      _emit(
        onUpdate,
        SmartSocketPhase.sendingStart,
        '发送 0x31 START',
        frame: start.frame.trim(),
      );
      _expectAck(
        await _exchange(
          0x31,
          start.ciphertext,
          onUpdate: onUpdate,
          uncertainOnFailure: true,
        ),
        0x31,
      );
      _emit(onUpdate, SmartSocketPhase.running, 'START 成功，保持蓝牙连接');
      return SmartSocketResult(
        device: device,
        clearedOrder: clearedOrder,
        start: start,
        appRandom: appRandom,
      );
    } on SmartSocketFailure catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      await disconnect();
      rethrow;
    } on BleProtocolException catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      await disconnect();
      throw SmartSocketFailure(error.message);
    } on BleTransportException catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      await disconnect();
      throw SmartSocketFailure(error.message, userMessage: error.userMessage);
    } catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      await disconnect();
      throw SmartSocketFailure('蓝牙连接失败（${error.runtimeType}）');
    } finally {
      _running = false;
    }
  }

  Future<BleFrame> _exchange(
    int command,
    List<int> payload, {
    SmartSocketUpdateCallback? onUpdate,
    bool uncertainOnFailure = false,
  }) async {
    final frames = _frameController;
    final transport = _activeTransport;
    if (frames == null || transport == null) {
      throw const SmartSocketFailure('蓝牙连接已关闭');
    }
    final response = Completer<BleFrame>();
    late final StreamSubscription<BleFrame> responseSubscription;
    responseSubscription = frames.stream.listen(
      (frame) {
        if (!response.isCompleted &&
            frame.type == 0x81 &&
            frame.command == command) {
          response.complete(frame);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(error, stackTrace: stackTrace);
        if (!response.isCompleted) {
          response.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!response.isCompleted) {
          response.completeError(
            const BleTransportException('蓝牙连接已断开', userMessage: '连接中断'),
          );
        }
      },
    );
    final request = BleFrameCodec.request(command, payload);
    _emit(
      onUpdate,
      _phaseForCommand(command),
      '写入 0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      frame: request.trim(),
    );
    // A response (or disconnect) can arrive before the write callback.
    response.future.ignore();
    try {
      await transport.writeAscii(request);
      final received = await response.future.timeout(commandTimeout);
      _ensureCurrent(transport);
      _emit(
        onUpdate,
        _phaseForCommand(command),
        '收到 0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()} 响应',
        frame: received.ascii.trim(),
      );
      return received;
    } on TimeoutException catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      throw SmartSocketFailure(
        '等待 0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()} 响应超时',
        uncertainDeviceState: uncertainOnFailure,
        userMessage: '等待插座响应超时',
      );
    } on SmartSocketFailure catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      rethrow;
    } catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      throw SmartSocketFailure(
        '0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()} 传输失败（${error.runtimeType}）',
        uncertainDeviceState: uncertainOnFailure,
        userMessage: error is BleTransportException ? error.userMessage : null,
      );
    } finally {
      await responseSubscription.cancel();
    }
  }

  void _listenForFrames(BleProtocolTransport transport) {
    final frames = StreamController<BleFrame>.broadcast(sync: true);
    _frameController = frames;
    final decoder = BleNotificationDecoder();
    _notificationSubscription = transport.notifications.listen((bytes) {
      try {
        for (final frame in decoder.add(bytes)) {
          frames.add(frame);
        }
      } catch (error, stackTrace) {
        AppLogger.error(error, stackTrace: stackTrace);
        frames.addError(error, stackTrace);
      }
    }, onError: frames.addError);
  }

  Future<void> disconnect() {
    final transport = _activeTransport;
    if (transport == null) return _disconnecting ?? Future.value();
    _activeTransport = null;
    final notifications = _notificationSubscription;
    _notificationSubscription = null;
    final disconnects = _disconnectSubscription;
    _disconnectSubscription = null;
    final frames = _frameController;
    _frameController = null;
    return _disconnecting = Future.wait<void>([
      if (notifications != null) notifications.cancel(),
      if (disconnects != null) disconnects.cancel(),
      if (frames != null) frames.close().then<void>((_) {}),
      if (identical(transport, _injectedTransport))
        transport.disconnect()
      else
        transport.dispose(),
    ]).then<void>((_) {}).whenComplete(() => _disconnecting = null);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _injectedTransport?.dispose();
    await _disconnects.close();
  }

  void _ensureCurrent(BleProtocolTransport transport) {
    if (!identical(_activeTransport, transport)) {
      throw const BleTransportException('蓝牙连接已断开', userMessage: '连接中断');
    }
  }

  void _verifyMac(BleQrInfo qr, BleDeviceInfo device) {
    if (!qr.matchesMac(device.mac)) {
      throw const SmartSocketFailure(
        '二维码 MAC 与设备响应 MAC 不一致',
        userMessage: '插座与二维码不匹配',
      );
    }
  }

  void _verifyStableIdentity(BleDeviceInfo before, BleDeviceInfo after) {
    final stable =
        before.productId == after.productId &&
        before.deviceId == after.deviceId &&
        bytesEqual(before.tacTime, after.tacTime) &&
        before.macType == after.macType &&
        before.lType == after.lType;
    if (!stable) {
      throw const SmartSocketFailure('旧记录整理后设备身份字段发生变化');
    }
  }

  SmartSocketPhase _phaseForCommand(int command) => switch (command) {
    0x23 => SmartSocketPhase.querying,
    0x85 => SmartSocketPhase.readingOrder,
    0x86 => SmartSocketPhase.clearingOrder,
    0x31 => SmartSocketPhase.sendingStart,
    _ => SmartSocketPhase.querying,
  };

  void _expectAck(BleFrame frame, int command) {
    try {
      expectAck(frame, command);
    } on BleProtocolException catch (error, diagnosticStack) {
      AppLogger.error(error, stackTrace: diagnosticStack);
      if (command == 0x86 || command == 0x31) {
        throw SmartSocketFailure(error.message, uncertainDeviceState: true);
      }
      rethrow;
    }
  }

  void _emit(
    SmartSocketUpdateCallback? callback,
    SmartSocketPhase phase,
    String message, {
    String? frame,
    BleDeviceInfo? device,
    BleStoredOrder? order,
  }) {
    callback?.call(
      SmartSocketUpdate(
        phase: phase,
        message: message,
        frame: frame,
        device: device,
        order: order,
      ),
    );
  }
}
