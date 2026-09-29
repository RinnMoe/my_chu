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
import { UIAbility } from '@kit.AbilityKit';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import geoLocationManager from '@ohos.geoLocationManager';

const CHANNEL_NAME = 'moe.rinn.mychu/harmony_location';
const LOCATION_PERMISSION = 'ohos.permission.APPROXIMATELY_LOCATION';

/** Foreground, user-initiated location adapter for CampusUserLocationService. */
export default class MychuHarmonyLocationPlugin
  implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyLocationPlugin';
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
        try {
          result.success(await this.hasLocationPermission());
        } catch (_) {
          result.success(false);
        }
        return;
      case 'requestPermission':
        await this.requestLocationPermission(result);
        return;
      case 'getCurrentLocation':
        await this.getCurrentLocation(result);
        return;
      default:
        result.notImplemented();
        return;
    }
  }

  private async hasLocationPermission(): Promise<boolean> {
    const ability = this.ability;
    if (ability === null) return false;
    const accessManager = abilityAccessCtrl.createAtManager();
    return accessManager.checkAccessTokenSync(
      ability.context.applicationInfo.accessTokenId,
      LOCATION_PERMISSION,
    ) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private async requestLocationPermission(result: MethodResult): Promise<void> {
    const ability = this.ability;
    if (ability === null) {
      result.success(false);
      return;
    }
    try {
      const accessManager = abilityAccessCtrl.createAtManager();
      const request = await accessManager.requestPermissionsFromUser(
        ability.context,
        [LOCATION_PERMISSION],
      );
      result.success(
        request.authResults.length > 0 &&
          request.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED,
      );
    } catch (_) {
      result.success(false);
    }
  }

  private async getCurrentLocation(result: MethodResult): Promise<void> {
    try {
      if (!await this.hasLocationPermission()) {
        result.success(null);
        return;
      }
      const location = await geoLocationManager.getCurrentLocation();
      result.success({
        latitude: location.latitude,
        longitude: location.longitude,
      });
    } catch (_) {
      result.success(null);
    }
  }
}
