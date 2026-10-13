import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/host_auth_state.dart';
import 'campus_auth_prompt.dart';

/// Prevents account-owned pages (including WebViews) from being constructed for
/// a guest. Existing same-account content survives transient auth failures.
class CampusAuthBoundary extends StatefulWidget {
  const CampusAuthBoundary({
    super.key,
    required this.title,
    required this.builder,
    this.inline = false,
    this.guestBuilder,
    this.retainGuestShell = false,
  });
  final String title;
  final WidgetBuilder builder;
  final bool inline;
  final WidgetBuilder? guestBuilder;
  final bool retainGuestShell;
  @override
  State<CampusAuthBoundary> createState() => _CampusAuthBoundaryState();
}

class _CampusAuthBoundaryState extends State<CampusAuthBoundary> {
  String? _owner;
  bool _ready = false;
  Object _contentKey = Object();
  @override
  void initState() {
    super.initState();
    HostAuthState.snapshot.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (HostAuthState.initialized) {
      final state = HostAuthState.snapshot.value;
      setState(() {
        if (_owner != state.accountKey && _owner != null) {
          _contentKey = Object();
        }
        _owner =
            state.status == HostAuthStatus.storageError
                ? null
                : state.accountKey;
        _ready = true;
      });
    } else {
      unawaited(_readLocal());
    }
  }

  Future<void> _readLocal() async {
    try {
      final account = await AuthService.getCurrentAccount();
      if (mounted) {
        setState(() {
          _owner = account?.accountKey;
          _ready = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    HostAuthState.snapshot.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    if (_owner == null && widget.inline && !widget.retainGuestShell) {
      return widget.guestBuilder?.call(context) ??
          CampusAuthPrompt(title: widget.title);
    }
    if (_owner == null && !widget.retainGuestShell) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: CampusAuthPrompt(title: widget.title),
      );
    }
    final content = KeyedSubtree(
      key: widget.retainGuestShell ? ObjectKey(_contentKey) : ValueKey(_owner),
      child: Builder(builder: widget.builder),
    );
    // Native shells place their status inside their protected data region.
    // Other pages keep their Scaffold geometry while showing a local status.
    if (widget.retainGuestShell) return content;
    return CampusAuthStatusOverlay(child: content);
  }
}

/// Account-free controls stay in their page; only this data region is gated.
class CampusProtectedContent extends StatelessWidget {
  const CampusProtectedContent({
    super.key,
    required this.builder,
    this.title = '校园数据',
    this.icon = Icons.school_outlined,
  });
  final WidgetBuilder builder;
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: HostAuthState.snapshot,
    builder:
        (context, state, _) =>
            HostAuthState.initialized &&
                    (state.accountKey == null ||
                        state.status == HostAuthStatus.storageError)
                ? CampusAuthPrompt(title: title, icon: icon)
                : CampusAuthStatusOverlay(child: builder(context)),
  );
}
