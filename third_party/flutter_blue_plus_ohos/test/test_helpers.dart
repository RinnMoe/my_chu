import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The platform channel name used by flutter_blue_plus.
const String kChannelName = 'flutter_blue_plus/methods';

void _ensureBinding() {
  TestWidgetsFlutterBinding.ensureInitialized();
}

/// A lightweight test double that stands in for the native BLE platform.
///
/// The real platform is a Flutter `MethodChannel`, which is a static object
/// we cannot subclass. Instead this class encapsulates the *behavior* of the
/// platform: it routes each Dart->native `MethodCall` to a handler function
/// (a plain callback), and exposes [emitEvent] to simulate native->Dart pushes.
///
/// This is a hand-rolled test double (no Mockito dependency) that keeps the
/// zero-codegen `setMockMethodCallHandler` mechanism flutter_blue_plus requires,
/// while remaining a named, documented object the test harness can recognize.
/// It previously extended Mockito's `Fake`, but only its own `install`/`uninstall`
/// methods were ever used, so the dependency was removed to stay compatible with
/// Dart 2.19 (Flutter 3.7) through Dart 3.x without a version-solving conflict.
class FakeBluetoothPlatform {
  FakeBluetoothPlatform(this.handler);

  /// The per-method-call handler currently installed on the channel.
  Future<dynamic> Function(MethodCall) handler;

  /// Install this fake as the mock method-call handler on the channel.
  void install() {
    const channel = MethodChannel(kChannelName);
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  /// Remove this fake (or any handler) from the channel.
  void uninstall() {
    const channel = MethodChannel(kChannelName);
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

/// Install a mock handler on the flutter_blue_plus method channel and return
/// the channel. The handler receives every Dart->native `invokeMethod`.
MethodChannel mockChannel(Future<dynamic> Function(MethodCall) handler) {
  _ensureBinding();
  // Register via the named test double so the platform double is explicit.
  FakeBluetoothPlatform(handler).install();
  return const MethodChannel(kChannelName);
}

/// A default mock handler that keeps `_initFlutterBluePlus` from hanging:
/// `flutterRestart` and `connectedCount` must return 0 (otherwise the init
/// loop `while (connectedCount != 0)` spins forever). Everything else -> null.
Future<dynamic> defaultMockHandler(MethodCall call) async {
  switch (call.method) {
    case 'flutterRestart':
    case 'connectedCount':
      return 0;
    case 'isSupported':
      return true;
    default:
      return null;
  }
}

/// Tear down helper for tests that drive the FlutterBluePlus singleton.
/// Removes the mock method-call handler (via the test double) so no lingering
/// native->Dart call can reach a handler from a previous test.
///
/// FlutterBluePlus holds static caches (adapter state, connection states,
/// scan results, etc.) that are not publicly resettable; tests are written
/// to push their own precondition events rather than rely on cross-test
/// isolation. This helper guarantees the channel layer is clean between tests.
void tearDownFlutterBluePlus() {
  FakeBluetoothPlatform((_) async => null).uninstall();
}

/// Build a handler that returns 0 for the init methods and otherwise delegates
/// to [perMethod]. Use this when a test needs specific return values.
Future<dynamic> Function(MethodCall) withDefaults(
    Future<dynamic> Function(MethodCall)? perMethod) {
  return (MethodCall call) async {
    switch (call.method) {
      case 'flutterRestart':
      case 'connectedCount':
        return 0;
      default:
        return perMethod == null ? null : await perMethod(call);
    }
  };
}

/// Simulate the native platform pushing a MethodCall (an event) onto the
/// channel, e.g. "OnMtuChanged". The flutter_blue_plus `_methodCallHandler`
/// must already be installed (call any `_invokeMethod`-based API once first,
/// e.g. `FlutterBluePlus.isSupported`).
Future<void> emitEvent(String method, Map<dynamic, dynamic> args) async {
  _ensureBinding();
  final ByteData data = const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
  await TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
      .handlePlatformMessage(kChannelName, data, (ByteData? _) {});
}
