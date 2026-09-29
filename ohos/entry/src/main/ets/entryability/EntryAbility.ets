
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import MychuHarmonyNotificationPlugin from '../plugins/MychuHarmonyNotificationPlugin';
import MychuHarmonyLocationPlugin from '../plugins/MychuHarmonyLocationPlugin';
import MychuHarmonyFileSharePlugin from '../plugins/MychuHarmonyFileSharePlugin';
import MychuHarmonyQrScannerPlugin from '../plugins/MychuHarmonyQrScannerPlugin';
import MychuHarmonyBlePermissionPlugin from '../plugins/MychuHarmonyBlePermissionPlugin';
import MychuHarmonyCaptchaOcrPlugin from '../plugins/MychuHarmonyCaptchaOcrPlugin';
import MychuHarmonyAppLaunchPlugin from '../plugins/MychuHarmonyAppLaunchPlugin';
import MychuHarmonyDesktopWidgetPlugin from '../plugins/MychuHarmonyDesktopWidgetPlugin';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';

export default class EntryAbility extends FlutterAbility {
  private flutterAbilityInitialized: boolean = false;
  private abilityDestroyed: boolean = false;
  private pendingWindowStage: window.WindowStage | null = null;
  private pendingForegroundState: boolean | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    MychuHarmonyAppLaunchPlugin.captureWant(want);
    // Flutter OH copies the 100 MB debug kernel synchronously during onCreate.
    // Run that work after the platform lifecycle transaction has returned.
    setTimeout(() => this.initializeFlutterAbility(want, launchParam), 0);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam) {
    MychuHarmonyAppLaunchPlugin.captureWant(want);
    super.onNewWant(want, launchParam);
  }

  private initializeFlutterAbility(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (this.abilityDestroyed) {
      return;
    }
    super.onCreate(want, launchParam);
    this.flutterAbilityInitialized = true;

    const pendingWindowStage = this.pendingWindowStage;
    this.pendingWindowStage = null;
    if (pendingWindowStage != null) {
      super.onWindowStageCreate(pendingWindowStage);
    }

    const pendingForegroundState = this.pendingForegroundState;
    this.pendingForegroundState = null;
    if (pendingForegroundState === true) {
      super.onForeground();
    } else if (pendingForegroundState === false) {
      super.onBackground();
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    if (!this.flutterAbilityInitialized) {
      this.pendingWindowStage = windowStage;
      return;
    }
    super.onWindowStageCreate(windowStage);
  }

  onForeground() {
    if (!this.flutterAbilityInitialized) {
      this.pendingForegroundState = true;
      return;
    }
    super.onForeground();
  }

  onBackground() {
    if (!this.flutterAbilityInitialized) {
      this.pendingForegroundState = false;
      return;
    }
    super.onBackground();
  }

  onDestroy() {
    this.abilityDestroyed = true;
    if (this.flutterAbilityInitialized) {
      super.onDestroy();
    }
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    flutterEngine.getPlugins()?.add(new MychuHarmonyNotificationPlugin())
    flutterEngine.getPlugins()?.add(new MychuHarmonyLocationPlugin())
    flutterEngine.getPlugins()?.add(new MychuHarmonyFileSharePlugin())
    flutterEngine.getPlugins()?.add(new MychuHarmonyQrScannerPlugin())
    flutterEngine.getPlugins()?.add(new MychuHarmonyBlePermissionPlugin())
    flutterEngine.getPlugins()?.add(new MychuHarmonyCaptchaOcrPlugin())
    flutterEngine.getPlugins()?.add(new MychuHarmonyAppLaunchPlugin())
    flutterEngine.getPlugins()?.add(new MychuHarmonyDesktopWidgetPlugin())
  }
}
