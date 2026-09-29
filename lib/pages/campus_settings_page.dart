import 'dart:async';

import 'package:flutter/material.dart';

import '../capabilities/campus_places/campus_registry.dart';
import '../services/auth_service.dart';
import '../services/campus_settings_service.dart';

typedef CampusSelectionSaved = void Function(String campusId);

/// Campus selector used by onboarding. The profile settings sheet has its own
/// presentation so onboarding keeps its card layout and actions.
class CampusSelectionPanel extends StatefulWidget {
  final String accountKey;
  final String title;
  final String message;
  final String? note;
  final String saveLabel;
  final String? skipLabel;
  final CampusSelectionSaved? onSaved;
  final VoidCallback? onSkipped;
  final VoidCallback? onClosed;

  final CampusSettingsService? service;

  const CampusSelectionPanel({
    super.key,
    required this.accountKey,
    required this.title,
    required this.message,
    this.note,
    required this.saveLabel,
    this.skipLabel,
    this.onSaved,
    this.onSkipped,
    this.onClosed,

    this.service,
  });

  @override
  State<CampusSelectionPanel> createState() => _CampusSelectionPanelState();
}

class _CampusSelectionPanelState extends State<CampusSelectionPanel> {
  late final CampusSettingsService _service;
  late final int _sessionRevision;
  List<CampusEntry> _campuses = const [];
  String? _selectedCampusId;
  bool _loading = true;
  bool _saving = false;
  bool _defaultFallback = false;
  Object? _loadError;
  String? _saveError;
  bool _closedForStaleSession = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? campusSettingsService;
    _sessionRevision = AuthService.sessionRevision;
    AuthService.sessionRevisionNotifier.addListener(_onSessionRevisionChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    AuthService.sessionRevisionNotifier.removeListener(
      _onSessionRevisionChanged,
    );
    super.dispose();
  }

  void _onSessionRevisionChanged() {
    if (!mounted || _closedForStaleSession) return;
    if (AuthService.sessionRevision == _sessionRevision) return;
    _closedForStaleSession = true;
    widget.onClosed?.call();
  }

  Future<bool> _isCurrentSession() async {
    if (AuthService.sessionRevision != _sessionRevision) return false;
    final account = await AuthService.getCurrentAccount();
    return account?.accountKey == widget.accountKey &&
        AuthService.sessionRevision == _sessionRevision;
  }

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
      final stored = await _service.readStored(widget.accountKey);
      final current = await _service.read(widget.accountKey);
      if (!mounted || !(await _isCurrentSession())) return;
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

  Future<void> _save() async {
    final selected = _selectedCampusId;
    if (_saving || selected == null || !await _isCurrentSession()) {
      if (AuthService.sessionRevision != _sessionRevision) {
        _onSessionRevisionChanged();
      }
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await _service.set(widget.accountKey, selected);
      if (!mounted || !(await _isCurrentSession())) return;
      if (!saved) {
        setState(() {
          _saving = false;
          _saveError = '校区未能保存，请重试。';
        });
        return;
      }
      widget.onSaved?.call(selected);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '校区未能保存，请重试。';
      });
    }
  }

  void _skip() => widget.onSkipped?.call();

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: widget.title,
      explicitChildNodes: true,
      child: content,
    );
  }

  Widget _buildContent(BuildContext context) {
    final body = ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      children: [
        Text(
          widget.title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(widget.message),
        if (widget.note != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.note!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const _LoadingCampusState()
        else if (_loadError != null || _campuses.isEmpty)
          _CampusLoadError(
            onRetry: _load,
            onSkip: widget.skipLabel == null ? null : _skip,
          )
        else ...[
          for (final campus in _campuses)
            _CampusOption(
              campus: campus,
              selected: campus.campusId == _selectedCampusId,
              showDefaultLabel:
                  _defaultFallback &&
                  campus.campusId == CampusSettingsService.defaultCampusId,

              onTap:
                  () => setState(() {
                    _selectedCampusId = campus.campusId;
                    _defaultFallback = false;
                    _saveError = null;
                  }),
            ),
        ],
        if (_saveError != null) ...[
          const SizedBox(height: 8),
          Text(
            _saveError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.skipLabel != null)
              TextButton(
                onPressed: _saving ? null : _skip,
                child: Text(widget.skipLabel!),
              ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed:
                  _saving || _loading || _selectedCampusId == null
                      ? null
                      : _save,
              child:
                  _saving
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Text(widget.saveLabel),
            ),
          ],
        ),
      ],
    );

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

class _LoadingCampusState extends StatelessWidget {
  const _LoadingCampusState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 116,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载校区…'),
          ],
        ),
      ),
    );
  }
}

class _CampusLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback? onSkip;

  const _CampusLoadError({required this.onRetry, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    const message = '暂时无法加载校区，可以重试，或稍后在「我的」中设置。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(message),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            if (onSkip != null)
              TextButton(onPressed: onSkip, child: const Text('暂不设置')),
          ],
        ),
      ],
    );
  }
}

class _CampusOption extends StatelessWidget {
  final CampusEntry campus;
  final bool selected;
  final bool showDefaultLabel;

  final VoidCallback onTap;

  const _CampusOption({
    required this.campus,
    required this.selected,
    required this.showDefaultLabel,

    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label =
        showDefaultLabel
            ? '当前默认使用渭水校区'
            : (campus.address?.trim().isNotEmpty == true
                ? campus.address!.trim()
                : null);

    return Semantics(
      button: true,
      selected: selected,
      label: campus.displayName,
      onTap: onTap,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Text(campus.displayName),
        subtitle: label == null ? null : Text(label),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
