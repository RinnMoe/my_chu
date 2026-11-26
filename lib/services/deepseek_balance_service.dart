import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deepseek_api_settings_service.dart';

/// 查询 DeepSeek 官方账户余额；Key 只在宿主侧读取，不返回 WebView。
class DeepSeekBalanceService {
  const DeepSeekBalanceService();

  static const _endpoint = 'https://api.deepseek.com/user/balance';
  static const _timeout = Duration(seconds: 10);

  Future<({String currency, String totalBalance})> fetch() async {
    final key = await DeepSeekApiSettingsService.instance.read();
    if (key == null) {
      throw StateError('DeepSeek API Key is not configured');
    }
    final response = await http
        .get(
          Uri.parse(_endpoint),
          headers: {
            'Authorization': 'Bearer $key',
            'Accept': 'application/json',
          },
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('Balance request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid balance response');
    }
    final infos = decoded['balance_infos'];
    if (infos is! List) {
      throw const FormatException('Missing balance_infos');
    }
    Map<String, dynamic>? cny;
    for (final item in infos) {
      if (item is Map<String, dynamic> && item['currency'] == 'CNY') {
        cny = item;
        break;
      }
    }
    final info =
        cny ??
        (infos.isNotEmpty && infos.first is Map<String, dynamic>
            ? infos.first as Map<String, dynamic>
            : null);
    final total = info?['total_balance'];
    if (total is! String || total.trim().isEmpty) {
      throw const FormatException('Missing total_balance');
    }
    return (
      currency:
          info?['currency'] is String ? info!['currency'] as String : 'CNY',
      totalBalance: total.trim(),
    );
  }
}
