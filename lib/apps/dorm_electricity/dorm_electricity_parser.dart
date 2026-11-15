import 'dart:convert';

import '../../capabilities/dorm_electricity.dart';
import 'dorm_electricity_models.dart';

/// Parses data literals only. Never evaluates the upstream page's JavaScript.
class ElectricityParser {
  static const _quoted = r'''('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")''';

  static String _string(String literal) {
    if (literal.startsWith('"')) return jsonDecode(literal) as String;
    final result = StringBuffer();
    for (var i = 1; i < literal.length - 1; i++) {
      var char = literal[i];
      if (char != r'\') {
        result.write(char);
        continue;
      }
      if (++i >= literal.length - 1) throw const FormatException();
      char = literal[i];
      if (char == 'u') {
        if (i + 4 >= literal.length) throw const FormatException();
        result.writeCharCode(
          int.parse(literal.substring(i + 1, i + 5), radix: 16),
        );
        i += 4;
      } else {
        result.write(switch (char) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          "'" => "'",
          '"' => '"',
          r'\' => r'\',
          '/' => '/',
          _ => throw const FormatException(),
        });
      }
    }
    return result.toString();
  }

  static Map<String, String> _refs(String html) {
    final pattern = RegExp(
      '(?:const|let|var)\\s+(\\w+)\\s*=\\s*ref\\(\\s*$_quoted\\s*\\)',
    );
    return {
      for (final match in pattern.allMatches(html))
        match.group(1)!: _string(match.group(2)!),
    };
  }

  static List<dynamic> _array(String body, String name) {
    final pattern = RegExp(
      '\\b$name\\s*=\\s*ref\\(\\s*JSON\\.parse\\(\\s*$_quoted\\s*\\)\\s*\\)',
    );
    final match = pattern.firstMatch(body);
    if (match == null) throw const FormatException();
    final data = jsonDecode(_string(match.group(1)!));
    if (data is! List) throw const FormatException();
    return data;
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    if (value is! String && value is! num) throw const FormatException();
    final text = '$value'.trim();
    if ([
      '',
      'null',
      'undefined',
      'none',
      '--',
      '---',
    ].contains(text.toLowerCase())) {
      return null;
    }
    if (text.length > 100) throw const FormatException();
    return text;
  }

  static String? _number(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final parsed = num.tryParse(text);
    if (parsed == null || !parsed.isFinite) throw const FormatException();
    return text;
  }

  static T _parse<T>(T Function() action) {
    try {
      return action();
    } on DormElectricityException {
      rethrow;
    } catch (_) {
      throw const DormElectricityException('malformed');
    }
  }

  static List<String> meters(DormElectricityResponse response) =>
      meterRows(response).map((meter) => meter.id).toList();

  static List<ElectricityMeter> meterRows(DormElectricityResponse response) =>
      _parse(() {
        final seen = <String>{};
        final meters = <ElectricityMeter>[];
        for (final row in _array(response.body, 'data')) {
          if (row is! Map) throw const FormatException();
          final raw = row['comAddress'];
          final meter =
              raw is String
                  ? raw.trim()
                  : raw is int
                  ? '$raw'
                  : '';
          if (!RegExp(r'^\d{8,32}$').hasMatch(meter)) {
            throw const FormatException();
          }
          if (!seen.add(meter)) continue;
          final pipeline = _text(row['PipLineName']);
          final usage =
              pipeline == null
                  ? null
                  : RegExp(
                    r'[（(]([^（）()]+)[）)]\s*$',
                  ).firstMatch(pipeline)?.group(1);
          meters.add(ElectricityMeter(meter, name: usage ?? pipeline));
        }
        return meters;
      });

  static ElectricityBalance balance(
    DormElectricityResponse response, {
    DateTime? now,
  }) => _parse(() {
    if (response.body.contains('errorApp')) throw const FormatException();
    final refs = _refs(response.body);
    final prepaid = _number(refs['yffye']);
    final total = _number(refs['zye']);
    final kwh = _number(refs['zydl']);
    if (prepaid == null && total == null && kwh == null) {
      throw const FormatException();
    }
    return ElectricityBalance(
      total: total,
      prepaid: prepaid,
      subsidy: _number(refs['bzdye']),
      totalKwh: kwh,
      status: _text(refs['dbzt']),
      readingTime: _text(refs['cbsj']),
      chargeType: _text(refs['chargeType']),
      fetchedAt: now ?? DateTime.now(),
    );
  });

  static void _month(Object? actual, String requested) {
    final value = _text(actual);
    if (value != null && value != requested) throw const FormatException();
  }

  static ElectricityBill bill(DormElectricityResponse response, String month) =>
      _parse(() {
        if (response.month != month) throw const FormatException();
        Map data;
        if (response.body.trimLeft().startsWith('{')) {
          Object? value = jsonDecode(response.body);
          for (var i = 0; i < 5; i++) {
            if (value is String) value = jsonDecode(value);
            if (value is! Map) throw const FormatException();
            _month(value['month'], month);
            if (['qcdl', 'qmdl', 'ydl', 'ydje'].any(value.containsKey)) break;
            value =
                value['billData'] ??
                value['billdata'] ??
                value['bill'] ??
                value['data'];
          }
          if (value is! Map) throw const FormatException();
          data = value;
        } else {
          final refs = _refs(response.body);
          // An HTML default-month response needs an explicit matching month.
          if (refs['month'] != month) throw const FormatException();
          final match = RegExp(
            r'billData\s*=\s*ref\(\s*(\{[^{}]*\})\s*\)',
          ).firstMatch(response.body);
          if (match == null) throw const FormatException();
          data = {};
          final fields = RegExp(
            '(\\w+|"\\w+"|\'\\w+\')\\s*:\\s*($_quoted|-?\\d+(?:\\.\\d+)?|null)',
          );
          for (final field in fields.allMatches(match.group(1)!)) {
            final key = field.group(1)!.replaceAll(RegExp('["\']'), '');
            final raw = field.group(2)!;
            data[key] =
                raw.startsWith("'") || raw.startsWith('"')
                    ? _string(raw)
                    : jsonDecode(raw);
          }
        }
        if (!['qcdl', 'qmdl', 'ydl', 'ydje'].any(data.containsKey)) {
          throw const FormatException();
        }
        return ElectricityBill(
          month,
          start: _number(data['qcdl']),
          end: _number(data['qmdl']),
          kwh: _number(data['ydl']),
          amount: _number(data['ydje']),
        );
      });

  static List<ElectricityDailyUsage> daily(
    DormElectricityResponse response,
    String month,
  ) => _parse(() {
    if (response.month != month) throw const FormatException();
    _month(_refs(response.body)['month'], month);
    final result = <ElectricityDailyUsage>[];
    final seen = <String>{};
    for (final row in _array(response.body, 'comments')) {
      if (row is! Map) throw const FormatException();
      final raw = _text(row['sj'])?.replaceAll('-', '');
      if (raw == null || !RegExp(r'^\d{8}$').hasMatch(raw)) {
        throw const FormatException();
      }
      final date = DateTime(
        int.parse(raw.substring(0, 4)),
        int.parse(raw.substring(4, 6)),
        int.parse(raw.substring(6, 8)),
      );
      final expected =
          '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
      if (expected != raw ||
          '${raw.substring(0, 4)}-${raw.substring(4, 6)}' != month ||
          !seen.add(raw)) {
        throw const FormatException();
      }
      result.add(
        ElectricityDailyUsage(date, _number(row['ydl']), _number(row['ydje'])),
      );
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  });
}
