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
import { scanBarcode, scanCore } from '@kit.ScanKit';

const CHANNEL_NAME = 'moe.rinn.mychu/harmony_qr_scanner';
const USER_CANCELLED = 1000500002;

/** MyCHU adapter for the system-owned HarmonyOS QR scanner. */
export default class MychuHarmonyQrScannerPlugin
  implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyQrScannerPlugin';
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
    if (call.method !== 'scan') {
      result.notImplemented();
      return;
    }

    const ability = this.ability;
    if (ability === null) {
      result.error('SCAN_UNAVAILABLE', 'The scanner ability is unavailable.', null);
      return;
    }

    try {
      try {
        if (!scanCore.isDefaultScanSupported()) {
          result.error(
            'SCAN_UNAVAILABLE',
            'The default scanner is not supported on this device.',
            null,
          );
          return;
        }
      } catch (_) {
        // This support query was added after Scan Kit itself. Older systems
        // are checked by attempting the scanner API below.
      }

      const scan = await scanBarcode.startScanForResult(ability.context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true,
      });
      const rawValue = scan.originalValue.trim();
      if (rawValue.length === 0) {
        result.success(null);
        return;
      }
      result.success({
        rawValue: rawValue,
        source:
          scan.source === scanCore.ScanSource.PHOTO ? 'gallery' : 'camera',
      });
    } catch (error) {
      const code = (error as Record<string, Object>)['code'];
      if (code === USER_CANCELLED) {
        result.success(null);
      } else {
        result.error(
          'SCAN_UNAVAILABLE',
          'The HarmonyOS system scanner is unavailable.',
          null,
        );
      }
    }
  }
}
