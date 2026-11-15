import '../../capabilities/dorm_electricity.dart';

class ElectricityMeter {
  const ElectricityMeter(this.id, {this.name});
  final String id;
  final String? name;
  String get displayName =>
      name == null ? id : '$name · ${id.substring(id.length - 4)}';

  Map<String, Object?> toJson() => {'id': id, if (name != null) 'name': name};
  factory ElectricityMeter.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String ||
        !RegExp(r'^\d{8,32}$').hasMatch(id) ||
        (name != null &&
            (name is! String || name.isEmpty || name.length > 100))) {
      throw const DormElectricityException('malformed');
    }
    return ElectricityMeter(id, name: name as String?);
  }
}

class ElectricityBalance {
  const ElectricityBalance({
    this.total,
    this.prepaid,
    this.subsidy,
    this.totalKwh,
    this.status,
    this.readingTime,
    this.chargeType,
    required this.fetchedAt,
  });
  final String? total, prepaid, subsidy, totalKwh;
  final String? status, readingTime, chargeType;
  final DateTime fetchedAt;

  Map<String, Object?> toJson() => {
    'total': total,
    'prepaid': prepaid,
    'subsidy': subsidy,
    'totalKwh': totalKwh,
    'status': status,
    'readingTime': readingTime,
    'chargeType': chargeType,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
  };

  factory ElectricityBalance.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse('${json['fetchedAt']}');
    if (date == null) throw const DormElectricityException('malformed');
    String? field(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.length > 100) {
        throw const DormElectricityException('malformed');
      }
      return value;
    }

    return ElectricityBalance(
      total: field('total'),
      prepaid: field('prepaid'),
      subsidy: field('subsidy'),
      totalKwh: field('totalKwh'),
      status: field('status'),
      readingTime: field('readingTime'),
      chargeType: field('chargeType'),
      fetchedAt: date,
    );
  }
}

class ElectricityMeterRecord {
  const ElectricityMeterRecord(this.meter, this.balance);
  final ElectricityMeter meter;
  final ElectricityBalance balance;

  Map<String, Object?> toJson() => {
    'meter': meter.toJson(),
    'balance': balance.toJson(),
  };
  factory ElectricityMeterRecord.fromJson(Map<String, dynamic> json) {
    if (json['meter'] is! Map<String, dynamic> ||
        json['balance'] is! Map<String, dynamic>) {
      throw const DormElectricityException('malformed');
    }
    return ElectricityMeterRecord(
      ElectricityMeter.fromJson(json['meter'] as Map<String, dynamic>),
      ElectricityBalance.fromJson(json['balance'] as Map<String, dynamic>),
    );
  }
}

class ElectricityRecord {
  const ElectricityRecord(this.label, this.meters);
  final String label;
  final List<ElectricityMeterRecord> meters;

  Map<String, Object?> toJson() => {
    'version': 2,
    'label': label,
    'meters': meters.map((meter) => meter.toJson()).toList(),
  };
  factory ElectricityRecord.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final raw = json['meters'];
    if (json['version'] != 2 ||
        label is! String ||
        label.isEmpty ||
        label.length > 300 ||
        raw is! List ||
        raw.isEmpty ||
        raw.length > 64) {
      throw const DormElectricityException('malformed');
    }
    final meters = [
      for (final meter in raw)
        if (meter is Map<String, dynamic>)
          ElectricityMeterRecord.fromJson(meter)
        else
          throw const DormElectricityException('malformed'),
    ];
    if (meters.map((m) => m.meter.id).toSet().length != meters.length) {
      throw const DormElectricityException('malformed');
    }
    return ElectricityRecord(label, List.unmodifiable(meters));
  }
}

class ElectricityBill {
  const ElectricityBill(
    this.month, {
    this.start,
    this.end,
    this.kwh,
    this.amount,
  });
  final String month;
  final String? start, end, kwh, amount;
  bool get isEmpty =>
      start == null && end == null && kwh == null && amount == null;
}

class ElectricityDailyUsage {
  const ElectricityDailyUsage(this.date, this.kwh, this.amount);
  final DateTime date;
  final String? kwh, amount;
}
