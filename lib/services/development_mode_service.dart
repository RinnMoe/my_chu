import 'package:flutter/foundation.dart';

/// Development visibility state declared by an app.
enum DevelopmentFlag { none, dev }

/// Maps a build mode to the development visibility flag used by app metadata.
///
/// This is deliberately pure so build gating can be tested without mutating
/// process state.
DevelopmentFlag developmentFlagForBuild({required bool debugBuild}) {
  return debugBuild ? DevelopmentFlag.dev : DevelopmentFlag.none;
}

/// Exposes the immutable DEV state of the current Flutter build.
class DevelopmentModeService {
  static bool get isDev => kDebugMode;
}
