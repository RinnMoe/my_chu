import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import captchaOcrNative from 'libmychu_captcha_ocr.so';

const CHANNEL_NAME = 'moe.rinn.mychu/harmony_captcha_ocr';

/** Local ONNX bridge for the four-digit captcha model. */
export default class MychuHarmonyCaptchaOcrPlugin
  implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyCaptchaOcrPlugin';
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
    captchaOcrNative.close();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'initialize': {
          const model = call.argument('model') as Uint8Array;
          if (!(model instanceof Uint8Array) || model.length === 0) {
            result.error('OCR_MODEL_INVALID', 'The local model is unavailable.', null);
            return;
          }
          captchaOcrNative.initialize(model);
          result.success(true);
          return;
        }
        case 'run': {
          const input = call.argument('input') as Float32Array;
          const height = call.argument('height') as number;
          const width = call.argument('width') as number;
          if (
            !(input instanceof Float32Array) ||
            !Number.isInteger(height) ||
            !Number.isInteger(width) ||
            height <= 0 ||
            width <= 0
          ) {
            result.error('OCR_INPUT_INVALID', 'The captcha tensor is invalid.', null);
            return;
          }
          result.success(captchaOcrNative.run(input, height, width));
          return;
        }
        case 'close':
          captchaOcrNative.close();
          result.success(null);
          return;
        default:
          result.notImplemented();
          return;
      }
    } catch (_) {
      result.error('OCR_INFERENCE_FAILED', 'Local captcha recognition failed.', null);
    }
  }
}
