import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../services/campus_session.dart';
import '../../services/service_endpoints.dart';
import 'network_self_service_models.dart';

/// Read-only adapter for network self-service pages.
///
/// Mutating flows stay in the authenticated WebView. This adapter turns the
/// pages people check most often into typed, credential-free feature models.
class NetworkSelfServiceService {
  NetworkSelfServiceService({CampusSessionClient? client})
    : _client =
          client ?? CampusSession.client(CampusServices.networkSelfService);

  final CampusSessionClient _client;

  Future<NetworkSelfServiceOverview> loadOverview() async {
    final source = await _loadHtml(
      CampusServiceEndpoints.networkSelfServiceHomeUri,
    );
    return parseOverviewHtml(source);
  }

  Future<String> _loadHtml(Uri uri) async {
    final response = await _client.request(
      'GET',
      uri.toString(),
      followRedirects: false,
      throwOnHttpError: false,
    );
    final source = response.body;
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        (response.statusCode >= 300 && response.statusCode < 400) ||
        _looksLikeAuthenticationPage(source)) {
      throw const NetworkSelfServiceAuthenticationRequiredException();
    }
    if (response.statusCode != 200) {
      throw const NetworkSelfServiceParseException('网络自服返回了异常状态。');
    }
    return source;
  }

  static NetworkSelfServiceOverview parseOverviewHtml(String source) {
    final document = _parseDocument(source);
    final sessions = _tableRows(
      document,
      const ['IP地址', '上线时间', '套餐名称', 'MAC地址'],
      tableName: '在线信息',
      missingIsEmpty: true,
    );
    final packages = _tableRows(document, const [
      '套餐名称',
      '已用流量',
      '套餐余额',
      '结算日期',
    ], tableName: '套餐信息');

    return NetworkSelfServiceOverview(
      onlineSessions: sessions
          .map(
            (row) => NetworkOnlineSession(
              ipAddress: row['IP地址'] ?? '',
              onlineAt: row['上线时间'] ?? '',
              packageName: row['套餐名称'] ?? '',
              macAddress: row['MAC地址'] ?? '',
            ),
          )
          .toList(growable: false),
      packages: packages
          .map(
            (row) => NetworkPackageUsage(
              packageName: row['套餐名称'] ?? '',
              usedTraffic: row['已用流量'] ?? '',
              balance: row['套餐余额'] ?? '',
              settlementDate: row['结算日期'] ?? '',
            ),
          )
          .toList(growable: false),
    );
  }

  static Document _parseDocument(String source) {
    if (_looksLikeAuthenticationPage(source)) {
      throw const NetworkSelfServiceAuthenticationRequiredException();
    }
    return html_parser.parse(source);
  }

  static bool _looksLikeAuthenticationPage(String source) {
    final lower = source.toLowerCase();
    return lower.contains('id="loginform-username"') ||
        lower.contains("id='loginform-username'") ||
        lower.contains('site/validate-user');
  }

  static List<Map<String, String>> _tableRows(
    Document document,
    List<String> requiredHeaders, {
    required String tableName,
    bool missingIsEmpty = false,
  }) {
    for (final table in document.querySelectorAll('table')) {
      final rows = table.querySelectorAll('tr');
      for (var headerIndex = 0; headerIndex < rows.length; headerIndex++) {
        final headers = _rowCells(
          rows[headerIndex],
        ).map((cell) => _clean(cell.text)).toList(growable: false);
        if (headers.isEmpty) continue;
        final indexes = <String, int>{};
        for (var index = 0; index < headers.length; index++) {
          for (final expected in requiredHeaders) {
            if (_sameLabel(headers[index], expected)) indexes[expected] = index;
          }
        }
        if (!requiredHeaders.every(indexes.containsKey)) continue;

        final parsed = <Map<String, String>>[];
        for (final row in rows.skip(headerIndex + 1)) {
          final cells = row.querySelectorAll('td');
          if (cells.isEmpty ||
              _isEmptyDataRow(row) ||
              _clean(cells.first.text).startsWith('总计')) {
            continue;
          }
          final maxIndex = indexes.values.reduce(
            (current, value) => current > value ? current : value,
          );
          if (cells.length <= maxIndex) {
            throw NetworkSelfServiceParseException('$tableName数据列不完整。');
          }
          parsed.add({
            for (final entry in indexes.entries)
              entry.key: _clean(cells[entry.value].text),
          });
        }
        return parsed;
      }
    }
    if (missingIsEmpty) return const [];
    throw NetworkSelfServiceParseException('未找到$tableName数据。');
  }

  static List<Element> _rowCells(Element row) => row.querySelectorAll('th, td');

  static bool _sameLabel(String actual, String expected) =>
      actual.replaceAll(RegExp(r'[\s:：]'), '') ==
      expected.replaceAll(RegExp(r'[\s:：]'), '');

  static String _clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isEmptyDataRow(Element row) {
    final text = _clean(row.text).toLowerCase();
    return text.contains('没有找到数据') ||
        text.contains('暂无') ||
        text.contains('无记录') ||
        text.contains('no data') ||
        text.contains('no records');
  }
}
