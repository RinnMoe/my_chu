import {
  FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler,
  MethodChannel, MethodResult,
} from '@ohos/flutter_ohos';
import { BusinessError } from '@kit.BasicServicesKit';

interface HostErrorEntry {
  timestamp: number;
  content: string;
}

/** Process-local errors are transferred to the shared Flutter error list. */
export default class MychuHarmonyDiagnosticsPlugin implements FlutterPlugin, MethodCallHandler {
  private static pending: HostErrorEntry[] = [];
  private static current: MychuHarmonyDiagnosticsPlugin | null = null;
  private channel: MethodChannel | null = null;

  static record(error: Error, operation: string): void {
    const code = (error as BusinessError).code;
    MychuHarmonyDiagnosticsPlugin.pending.push({
      timestamp: Date.now(),
      content: `${operation}\n[HarmonyOS] ${error.name}: ${error.message}` +
        (typeof code === 'number' ? ` (${code})` : '') + `\n${error.stack ?? ''}`,
    });
    if (MychuHarmonyDiagnosticsPlugin.pending.length > 300) {
      MychuHarmonyDiagnosticsPlugin.pending.shift();
    }
    MychuHarmonyDiagnosticsPlugin.current?.channel?.invokeMethod('errorsAvailable', null);
  }

  getUniqueClassName(): string { return 'MychuHarmonyDiagnosticsPlugin'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'mychu/diagnostics');
    this.channel.setMethodCallHandler(this);
    MychuHarmonyDiagnosticsPlugin.current = this;
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    if (MychuHarmonyDiagnosticsPlugin.current === this) {
      MychuHarmonyDiagnosticsPlugin.current = null;
    }
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'takeErrors':
        result.success(MychuHarmonyDiagnosticsPlugin.pending.splice(0));
        return;
      case 'clearErrors':
        MychuHarmonyDiagnosticsPlugin.pending.splice(0);
        result.success(null);
        return;
      default:
        result.notImplemented();
    }
  }
}
