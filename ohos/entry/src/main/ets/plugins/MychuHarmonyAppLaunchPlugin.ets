import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { Want } from '@kit.AbilityKit';

const CHANNEL_NAME = 'mychu/app_launch';
const WIDGET_TARGET_PARAMETER = 'desktopWidgetTargetId';

interface DesktopWidgetLaunchPayload {
  source: string;
  request: string;
}

/** Passes validated-by-Dart widget target IDs into the host launch service. */
export default class MychuHarmonyAppLaunchPlugin
  implements FlutterPlugin, MethodCallHandler {
  private static channel: MethodChannel | null = null;
  private static pendingLaunch: DesktopWidgetLaunchPayload | null = null;
  private static dartReady: boolean = false;

  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyAppLaunchPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_NAME,
    );
    MychuHarmonyAppLaunchPlugin.channel = this.channel;
    MychuHarmonyAppLaunchPlugin.dartReady = false;
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    MychuHarmonyAppLaunchPlugin.channel = null;
    MychuHarmonyAppLaunchPlugin.dartReady = false;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method === 'consume') {
      const pending = MychuHarmonyAppLaunchPlugin.pendingLaunch;
      MychuHarmonyAppLaunchPlugin.pendingLaunch = null;
      MychuHarmonyAppLaunchPlugin.dartReady = true;
      result.success(pending);
      return;
    }
    result.notImplemented();
  }

  static captureWant(want: Want): void {
    const rawTarget = want.parameters?.[WIDGET_TARGET_PARAMETER];
    const targetId = typeof rawTarget === 'string' ? rawTarget.trim() : '';
    if (targetId.length === 0) return;

    const payload: DesktopWidgetLaunchPayload = {
      source: 'desktopWidget',
      request: JSON.stringify({ schemaVersion: 1, targetId: targetId }),
    };
    const channel = MychuHarmonyAppLaunchPlugin.channel;
    if (channel === null || !MychuHarmonyAppLaunchPlugin.dartReady) {
      MychuHarmonyAppLaunchPlugin.pendingLaunch = payload;
      return;
    }
    channel.invokeMethod('launch', payload);
  }
}
