import 'dart:async';

import 'package:flutter/material.dart';

import '../capabilities/campus_places/campus_registry.dart';
import '../services/campus_settings_service.dart';

Future<bool?> showCampusSettingsSheet(BuildContext context) {
  const sheet = CampusSettingsSheet();

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => sheet,
  );
}

/// Profile-only campus selector. Its rows follow the theme settings sheet;
/// onboarding keeps the separate elevated card presentation.
class CampusSettingsSheet extends StatefulWidget {
  final CampusSettingsService? service;

  const CampusSettingsSheet({super.key, this.service});

  @override
  State<CampusSettingsSheet> createState() => _CampusSettingsSheetState();
}

class _CampusSettingsSheetState extends State<CampusSettingsSheet> {
  late final CampusSettingsService _service;
  List<CampusEntry> _campuses = const [];
  String? _selectedCampusId;
  bool _loading = true;
  bool _saving = false;
  bool _defaultFallback = false;
  Object? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? campusSettingsService;
    unawaited(_load());
  }

  Future<bool> _isCurrentSession() async => mounted;

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _saveError = null;
      });
    }
    try {
      final campuses = await _service.enabledCampuses();
      final stored = await _service.readStored();
      final current = await _service.read();
      if (!mounted) return;
      final isCurrentSession = await _isCurrentSession();
      if (!isCurrentSession) return;
      if (!mounted) return;

      final hasCurrent =
          stored != null &&
          campuses.any((campus) => campus.campusId == current);
      final hasDefault = campuses.any(
        (campus) => campus.campusId == CampusSettingsService.defaultCampusId,
      );
      final fallback =
          hasCurrent
              ? current
              : hasDefault
              ? CampusSettingsService.defaultCampusId
              : campuses.firstOrNull?.campusId;
      setState(() {
        _campuses = campuses;
        _selectedCampusId = fallback;
        _defaultFallback = !hasCurrent && hasDefault;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || !(await _isCurrentSession())) return;
      setState(() {
        _campuses = const [];
        _selectedCampusId = null;
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _save(String campusId) async {
    if (_saving || !(await _isCurrentSession())) {
      return;
    }
    setState(() {
      _saving = true;
      _selectedCampusId = campusId;
      _defaultFallback = false;
      _saveError = null;
    });
    try {
      final saved = await _service.set(campusId);
      if (!mounted) return;
      final isCurrentSession = await _isCurrentSession();
      if (!isCurrentSession) return;
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _saving = false;
          _saveError = '校区未能保存，请重试。';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '校区未能保存，请重试。';
      });
    }
  }

  String? _subtitleFor(CampusEntry campus) {
    if (_defaultFallback &&
        campus.campusId == CampusSettingsService.defaultCampusId) {
      return '当前默认使用渭水校区';
    }
    final address = campus.address?.trim();
    return address == null || address.isEmpty ? null : address;
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterialSheet(context);
  }

  Widget _buildMaterialSheet(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                child: Text('校区设置', style: theme.textTheme.titleLarge),
              ),
              if (_loading)
                const SizedBox(
                  height: 112,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null || _campuses.isEmpty)
                _buildMaterialLoadError()
              else
                Flexible(
                  fit: FlexFit.loose,
                  child: RadioGroup<String>(
                    groupValue: _selectedCampusId,
                    onChanged: (campusId) {
                      if (campusId != null && !_saving) {
                        unawaited(_save(campusId));
                      }
                    },
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final campus in _campuses)
                          RadioListTile<String>(
                            value: campus.campusId,
                            title: Text(campus.displayName),
                            subtitle:
                                _subtitleFor(campus) == null
                                    ? null
                                    : Text(_subtitleFor(campus)!),
                            enabled: !_saving,
                            secondary:
                                _saving && campus.campusId == _selectedCampusId
                                    ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : null,
                          ),
                      ],
                    ),
                  ),
                ),
              if (_saveError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _saveError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialLoadError() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Expanded(child: Text('暂时无法加载校区，可以重试。')),
          TextButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }
}
