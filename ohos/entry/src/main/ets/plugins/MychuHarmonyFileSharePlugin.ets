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
import { common, UIAbility } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import uniformTypeDescriptor from '@ohos.data.uniformTypeDescriptor';
import fileUri from '@ohos.file.fileuri';
import fs from '@ohos.file.fs';

const CHANNEL_NAME = 'mychu/file_save';

/** MyCHU adapter for sharing a file through the HarmonyOS system panel. */
export default class MychuHarmonyFileSharePlugin
  implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyFileSharePlugin';
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
    if (call.method !== 'shareFile') {
      result.notImplemented();
      return;
    }

    const ability = this.ability;
    const path = call.argument('path') as string;
    const fileName = call.argument('fileName') as string;
    if (
      ability === null ||
      typeof path !== 'string' ||
      typeof fileName !== 'string' ||
      fileName.trim().length === 0 ||
      !this.isAppFile(path, ability.context.filesDir)
    ) {
      result.success(false);
      return;
    }

    try {
      if (!fs.accessSync(path) || !fs.statSync(path).isFile()) {
        result.success(false);
        return;
      }

      const safeName = fileName.split(/[\\/]/).pop()?.trim() ?? '';
      if (safeName.length === 0 || safeName === '.' || safeName === '..') {
        result.success(false);
        return;
      }
      const extension =
        safeName.includes('.')
          ? safeName.split('.').pop()?.toLowerCase() ?? ''
          : '';
      let dataType: string = uniformTypeDescriptor.UniformDataType.FILE;
      if (extension.length > 0) {
        try {
          const detectedType = uniformTypeDescriptor
            .getUniformDataTypeByFilenameExtension(extension);
          if (detectedType.length > 0) dataType = detectedType;
        } catch (_) {
          // Keep the generic file type for an extension without a known UTD.
        }
      }

      const data = new systemShare.SharedData({
        utd: dataType,
        uri: fileUri.getUriFromPath(path),
        title: safeName,
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(ability.context as common.UIAbilityContext, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT,
      });
      result.success(true);
    } catch (_) {
      result.success(false);
    }
  }

  private isAppFile(path: string, filesDir: string): boolean {
    const normalizedPath = path.replace(/\\/g, '/');
    const normalizedRoot = filesDir.replace(/\\/g, '/').replace(/\/$/, '');
    if (
      normalizedRoot.length === 0 ||
      !normalizedPath.startsWith(`${normalizedRoot}/`)
    ) {
      return false;
    }
    const relativePath = normalizedPath.substring(normalizedRoot.length + 1);
    return (
      relativePath.length > 0 &&
      !relativePath.split('/').some(
        (segment: string) =>
          segment.length === 0 || segment === '.' || segment === '..',
      )
    );
  }
}
