import 'package:flutter/foundation.dart';

/// Host-owned requests for selecting an existing root navigation tab.
///
/// Feature pages and notification surfaces may be pushed above the shell, so
/// they must not construct a second copy of a root page.  A request is kept
/// until [takePendingTab] is consumed by `MainScreen`; the revision notifier
/// also makes repeated requests for the same tab observable.
class RootNavigationService {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static String? _pendingTabId;

  static void selectTab(String tabId) {
    final normalized = tabId.trim();
    if (normalized.isEmpty) return;
    _pendingTabId = normalized;
    revision.value++;
  }

  static String? get pendingTabId => _pendingTabId;

  static String? takePendingTab() {
    final tabId = _pendingTabId;
    _pendingTabId = null;
    return tabId;
  }
}
