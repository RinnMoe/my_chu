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
import notificationManager from '@ohos.notificationManager';

const CHANNEL_NAME = 'moe.rinn.mychu/harmony_notifications';

/** MyCHU host adapter for user-authorized HarmonyOS system notifications. */
export default class MychuHarmonyNotificationPlugin
  implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyNotificationPlugin';
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
      case 'isNotificationEnabled': {
        try {
          result.success(await notificationManager.isNotificationEnabled());
        } catch (_) {
          result.success(false);
        }
        return;
      }
      case 'requestPermission': {
        const ability = this.ability;
        if (ability === null) {
          result.success(false);
          return;
        }
        try {
          await notificationManager.requestEnableNotification(ability.context);
        } catch (_) {
          // A denial is reported by the enabled-state query below.
        }
        try {
          result.success(await notificationManager.isNotificationEnabled());
        } catch (_) {
          result.success(false);
        }
        return;
      }
      case 'show': {
        const id = call.argument('id') as number;
        const title = call.argument('title') as string;
        const body = call.argument('body') as string | null;
        if (!Number.isInteger(id) || title === null || title.length === 0) {
          result.success(false);
          return;
        }
        try {
          if (!await notificationManager.isNotificationEnabled()) {
            result.success(false);
            return;
          }
          await notificationManager.publish({
            id: id,
            content: {
              notificationContentType:
                notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
              normal: {
                title: title,
                text: body !== null && body.length > 0 ? body : title,
              },
            },
          });
          result.success(true);
        } catch (_) {
          result.success(false);
        }
        return;
      }
      default:
        result.notImplemented();
        return;
    }
  }
}
