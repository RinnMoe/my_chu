import '../../widgets/app_bottom_sheet.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/dorm_electricity.dart';
import 'dorm_electricity_catalog.dart';
import 'dorm_electricity_repository.dart';

Future<void> showElectricityPicker(
  BuildContext context,
  ElectricityRepository repository,
) => showAppBottomSheet<void>(
  context: context,
  builder: (_) => ElectricityPicker(repository: repository),
);

class ElectricityPicker extends StatefulWidget {
  const ElectricityPicker({
    super.key,
    required this.repository,
    this.catalogLoader,
  });
  final ElectricityRepository repository;
  final Future<ElectricityCatalog> Function()? catalogLoader;

  @override
  State<ElectricityPicker> createState() => _ElectricityPickerState();
}

class _ElectricityPickerState extends State<ElectricityPicker> {
  ElectricityCatalog? _catalog;
  String? _group, _error;
  ElectricityBuildingNode? _building;
  ElectricityFloorNode? _floor;
  ElectricityRoomNode? _room;
  bool _busy = false, _catalogFailed = false, _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCatalog());
  }

  Future<void> _loadCatalog() async {
    setState(() => _catalogFailed = false);
    try {
      final catalog = await (widget.catalogLoader ?? ElectricityCatalog.load)();
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _group ??= catalog.groups.firstOrNull?.code;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _catalogFailed = true);
    }
  }

  @override
  void dispose() {
    if (_busy && !_closed) widget.repository.cancelPending();
    _closed = true;
    super.dispose();
  }

  Future<void> _submit() async {
    if (_closed || _busy || _room == null || !_room!.selectable) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final group = _catalog!.groups.firstWhere(
        (g) => g.code == _group,
        orElse: () => throw const DormElectricityException('malformed'),
      );
      final label =
          '${group.displayName} / ${_building!.name} / ${_floor!.name} / ${_roomName(_room!)}';
      final meters = await widget.repository.resolveRoom(
        _room!.id,
        '长安大学|${_building!.name}|${_floor!.name}|${_room!.name}',
      );
      if (!mounted || _closed) return;
      if (meters.isEmpty) throw const DormElectricityException('empty');
      await widget.repository.select(label: label, meters: meters);
      if (mounted && !_closed) Navigator.of(context).pop();
    } on DormElectricityException catch (error) {
      if (mounted && !_closed && error.code != 'cancelled') {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _roomName(ElectricityRoomNode room) {
    final prefix = '${_building!.area}${_building!.name}${_floor!.name}';
    return room.name.startsWith(prefix) && room.name.length > prefix.length
        ? room.name.substring(prefix.length)
        : room.name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _catalog?.groups ?? const <ElectricityGroup>[];
    final buildings =
        _catalog?.buildings.where((b) => b.group == _group).toList() ?? [];
    final floorField = DropdownButtonFormField<ElectricityFloorNode>(
      key: ValueKey('floor:${_building?.id}'),
      initialValue: _floor,
      decoration: const InputDecoration(labelText: '楼层'),
      hint: Text(
        _building == null
            ? '先选楼栋'
            : _building!.floors.isEmpty
            ? '暂无楼层'
            : '选择楼层',
      ),
      isExpanded: true,
      menuMaxHeight: 360,
      items: [
        for (final floor in _building?.floors ?? const <ElectricityFloorNode>[])
          DropdownMenuItem(value: floor, child: Text(floor.name)),
      ],
      onChanged:
          _busy || _building == null
              ? null
              : (value) {
                if (value == _floor) return;
                setState(() {
                  _floor = value;
                  _room = null;
                  _error = null;
                });
              },
    );
    final roomField = DropdownButtonFormField<ElectricityRoomNode>(
      key: ValueKey('room:${_floor?.id}'),
      initialValue: _room,
      decoration: const InputDecoration(labelText: '房间'),
      hint: Text(
        _floor == null
            ? '先选楼层'
            : _floor!.rooms.every((room) => !room.selectable)
            ? '暂无可查询房间'
            : '选择房间',
      ),
      isExpanded: true,
      menuMaxHeight: 360,
      items: [
        for (final room in _floor?.rooms ?? const <ElectricityRoomNode>[])
          DropdownMenuItem(
            value: room,
            enabled: room.selectable,
            child: Text(_roomName(room)),
          ),
      ],
      onChanged:
          _busy || _floor == null
              ? null
              : (value) => setState(() {
                _room = value;
                _error = null;
              }),
    );
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        _closed = true;
        if (_busy) widget.repository.cancelPending();
      },
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: appBottomSheetContentHeight(context),
            maxWidth: 640,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSheetHeader(title: '选择宿舍'),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_catalogFailed) ...[
                        const Text('房间目录无法读取，请重试。'),
                        TextButton(
                          onPressed: _loadCatalog,
                          child: const Text('重试'),
                        ),
                      ] else if (_catalog == null)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (groups.isEmpty)
                        const Text('暂无可用的宿舍目录。')
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _group,
                          decoration: const InputDecoration(labelText: '区域'),
                          isExpanded: true,
                          items: [
                            for (final group in groups)
                              DropdownMenuItem(
                                value: group.code,
                                child: Text(group.displayName),
                              ),
                          ],
                          onChanged:
                              _busy
                                  ? null
                                  : (value) {
                                    if (value == _group) return;
                                    setState(() {
                                      _group = value;
                                      _building = null;
                                      _floor = null;
                                      _room = null;
                                      _error = null;
                                    });
                                  },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<ElectricityBuildingNode>(
                          key: ValueKey('building:$_group'),
                          initialValue: _building,
                          decoration: const InputDecoration(labelText: '楼栋'),
                          hint: Text(buildings.isEmpty ? '该区域暂无楼栋' : '选择楼栋'),
                          isExpanded: true,
                          menuMaxHeight: 360,
                          items: [
                            for (final building in buildings)
                              DropdownMenuItem(
                                value: building,
                                child: Text(building.name),
                              ),
                          ],
                          onChanged:
                              _busy
                                  ? null
                                  : (value) {
                                    if (value == _building) return;
                                    setState(() {
                                      _building = value;
                                      _floor = null;
                                      _room = null;
                                      _error = null;
                                    });
                                  },
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final scale =
                                MediaQuery.textScalerOf(context).scale(14) / 14;
                            if ((constraints.maxWidth - 16) / 2 >=
                                136 * scale) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: floorField),
                                  const SizedBox(width: 16),
                                  Expanded(child: roomField),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                floorField,
                                const SizedBox(height: 16),
                                roomField,
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: _busy || _room == null ? null : _submit,
                      child: Text(_busy ? '正在查询…' : '查询并保存'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
