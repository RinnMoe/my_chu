import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deepseek_api_settings_service.dart';

/// 通过宿主代理 DeepSeek ASR，避免 WebView CORS 限制并让 Key 不进入网页请求。
class DeepSeekSpeechService {
  const DeepSeekSpeechService();

  static const _endpoint = 'https://api.deepseek.com/v1/tools/asr';
  static const _timeout = Duration(seconds: 60);

  Future<String> transcribe(
    List<int> bytes, {
    String filename = 'recording.wav',
  }) async {
    final key = await DeepSeekApiSettingsService.instance.read();
    if (key == null) {
      throw StateError('DeepSeek API Key is not configured');
    }
    final request =
        http.MultipartRequest('POST', Uri.parse(_endpoint))
          ..headers['Authorization'] = 'Bearer $key'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
    final response = await http.Response.fromStream(
      await request.send().timeout(_timeout),
    );
    if (response.statusCode != 200) {
      throw StateError('ASR request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['text'] is! String) {
      throw const FormatException('Invalid ASR response');
    }
    return (decoded['text'] as String).trim();
  }
}
