import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { UIAbility, abilityAccessCtrl } from '@kit.AbilityKit';

const CHANNEL_NAME = 'moe.rinn.mychu/harmony_ble_permission';
const BLE_PERMISSION = 'ohos.permission.ACCESS_BLUETOOTH';

/** On-demand, foreground permission adapter for the QR-bound BLE test. */
export default class MychuHarmonyBlePermissionPlugin
  implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyBlePermissionPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_NAME,
    );
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.ability = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'checkPermission':
        result.success(this.hasBlePermission());
        return;
      case 'requestPermission':
        await this.requestBlePermission(result);
        return;
      default:
        result.notImplemented();
        return;
    }
  }

  private hasBlePermission(): boolean {
    const ability = this.ability;
    if (ability === null) return false;
    try {
      const accessManager = abilityAccessCtrl.createAtManager();
      return accessManager.checkAccessTokenSync(
        ability.context.applicationInfo.accessTokenId,
        BLE_PERMISSION,
      ) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_) {
      return false;
    }
  }

  private async requestBlePermission(result: MethodResult): Promise<void> {
    const ability = this.ability;
    if (ability === null) {
      result.success(false);
      return;
    }
    try {
      const accessManager = abilityAccessCtrl.createAtManager();
      const request = await accessManager.requestPermissionsFromUser(
        ability.context,
        [BLE_PERMISSION],
      );
      result.success(
        request.authResults.length > 0 &&
          request.authResults[0] ===
            abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED,
      );
    } catch (_) {
      result.success(false);
    }
  }
}
