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
import { formProvider } from '@kit.FormKit';
import {
  createDesktopWidgetFormData,
  getDesktopWidgetFormRegistrations,
  writeDesktopWidgetSnapshot,
} from '../widgets/DesktopWidgetSnapshotStore';

const CHANNEL_NAME = 'mychu/desktop_widgets';

/** Publishes the shared V1 snapshot to local Form Kit cards. */
export default class MychuHarmonyDesktopWidgetPlugin
  implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyDesktopWidgetPlugin';
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
    if (call.method !== 'publishSnapshot') {
      result.notImplemented();
      return;
    }
    const ability = this.ability;
    const snapshot = call.argument('snapshot') as string;
    if (ability === null || typeof snapshot !== 'string' ||
      !writeDesktopWidgetSnapshot(ability.context.filesDir, snapshot)) {
      result.error(
        'INVALID_SNAPSHOT',
        'Harmony desktop widget snapshot could not be published',
        null,
      );
      return;
    }

    const filesDir = ability.context.filesDir;
    const registrations = getDesktopWidgetFormRegistrations(filesDir);
    for (const registration of registrations) {
      const data = createDesktopWidgetFormData(
        filesDir,
        registration.formName,
        registration.dimension,
      );
      try {
        await formProvider.updateForm(registration.formId, data);
      } catch (_) {
        // The local snapshot remains current; the system can retry on its next update.
      }
    }
    result.success(null);
  }
}
