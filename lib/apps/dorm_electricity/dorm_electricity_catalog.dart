import 'dart:convert';
import 'package:flutter/services.dart';

class ElectricityRoomNode {
  const ElectricityRoomNode(this.id, this.name);
  final String id, name;
  bool get selectable => !name.contains('充值前请确认');
}

class ElectricityFloorNode extends ElectricityRoomNode {
  const ElectricityFloorNode(super.id, super.name, this.rooms);
  final List<ElectricityRoomNode> rooms;
}

class ElectricityBuildingNode extends ElectricityRoomNode {
  const ElectricityBuildingNode(
    super.id,
    super.name,
    this.group,
    this.area,
    this.floors,
  );
  final String group, area;
  final List<ElectricityFloorNode> floors;
}

class ElectricityGroup {
  const ElectricityGroup(this.code, this.area, {this.status = ''});
  final String code, area, status;
  String get displayName => switch (status) {
    'mixed' => '其他区域',
    _ => area,
  };
  int get priority => switch (status) {
    'verified' => 0,
    'mixed' => 2,
    _ => 1,
  };
}

class ElectricityCatalog {
  const ElectricityCatalog(this.buildings, {List<ElectricityGroup>? groups})
    : _groups = groups;
  final List<ElectricityBuildingNode> buildings;
  final List<ElectricityGroup>? _groups;
  List<ElectricityGroup> get groups {
    final result = List<ElectricityGroup>.of(
      _groups ??
          {
            for (final b in buildings)
              b.group: ElectricityGroup(b.group, b.area),
          }.values,
    );
    result.sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      return priority != 0 ? priority : a.code.compareTo(b.code);
    });
    return result;
  }

  static Future<ElectricityCatalog> load() async {
    final files = await Future.wait([
      rootBundle.loadString('assets/dorm_electricity/changan_tree.json'),
      rootBundle.loadString('assets/dorm_electricity/changan.json'),
    ]);
    return ElectricityCatalog.decode(files[0], profile: files[1]);
  }

  factory ElectricityCatalog.decode(String raw, {String? profile}) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final ids = <String>{};
    String text(Map node, String key) {
      final value = node[key];
      if (value is! String || value.isEmpty) throw const FormatException();
      return value;
    }

    String id(Map node, int length, [String? parent]) {
      final value = text(node, 'id');
      if (!RegExp('^\\d{$length}\$').hasMatch(value) ||
          !ids.add(value) ||
          (parent != null && !value.startsWith(parent))) {
        throw const FormatException();
      }
      return value;
    }

    final buildings = <ElectricityBuildingNode>[];
    for (final b in json['buildings'] as List) {
      final building = b as Map;
      final buildingId = id(building, 15);
      final group = text(building, 'group');
      if (group != buildingId.substring(6, 9)) throw const FormatException();
      final floors = <ElectricityFloorNode>[];
      for (final f in building['floors'] as List) {
        final floor = f as Map;
        final floorId = id(floor, 21, buildingId);
        floors.add(
          ElectricityFloorNode(floorId, text(floor, 'name'), [
            for (final r in floor['rooms'] as List)
              ElectricityRoomNode(id(r as Map, 24, floorId), text(r, 'name')),
          ]),
        );
      }
      buildings.add(
        ElectricityBuildingNode(
          buildingId,
          text(building, 'name'),
          group,
          text(building, 'group_area'),
          floors,
        ),
      );
    }
    List<ElectricityGroup>? groups;
    if (profile != null) {
      final metadata = jsonDecode(profile) as Map<String, dynamic>;
      if (metadata['id'] != '65') throw const FormatException();
      final codes = <String>{};
      groups = [
        for (final g in metadata['groups'] as List)
          ElectricityGroup(
            text(g as Map, 'code'),
            text(g, 'area'),
            status: text(g, 'status'),
          ),
      ];
      for (final g in groups) {
        if (!codes.add(g.code) || !buildings.any((b) => b.group == g.code)) {
          throw const FormatException();
        }
      }
      if (codes.length != buildings.map((b) => b.group).toSet().length) {
        throw const FormatException();
      }
    }
    return ElectricityCatalog(List.unmodifiable(buildings), groups: groups);
  }
}
