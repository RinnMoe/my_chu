import 'package:shared_preferences/shared_preferences.dart';

import 'logging/logger.dart';

/// Stores the one-time campus prompt and versioned contextual guide hints.
class GuidePreferences {
  static const currentMainTourVersion = 1;
  static const currentOnboardingFlowVersion = 1;
  static const currentHintVersion = 2;

  static const mainTourKey = 'guide.main.version';
  static const onboardingFlowKey = 'guide.onboarding.flow.version';

  static const scheduleFeatureTourHintId = 'schedule_course';

  Future<bool> shouldShowCampusPrompt() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return (preferences.getInt(mainTourKey) ?? 0) < currentMainTourVersion;
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    }
  }

  Future<bool> shouldShowMainTour() => shouldShowCampusPrompt();

  Future<void> markCampusPromptSeen() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(mainTourKey, currentMainTourVersion);
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
    }
  }

  Future<void> markMainTourSeen() => markCampusPromptSeen();

  Future<void> resetMainTour() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(mainTourKey);
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
    }
  }

  Future<bool> shouldShowOnboardingFlow() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return (preferences.getInt(onboardingFlowKey) ?? 0) <
          currentOnboardingFlowVersion;
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    }
  }

  Future<void> markOnboardingFlowSeen() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(onboardingFlowKey, currentOnboardingFlowVersion);
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
    }
  }

  Future<bool> shouldShowHint(String id, int version) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return (preferences.getInt(_hintKey(id)) ?? 0) < version;
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
      return false;
    }
  }

  Future<void> markHintSeen(String id, int version) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_hintKey(id), version);
    } catch (diagnosticError, diagnosticStack) {
      AppLogger.error(diagnosticError, stackTrace: diagnosticStack);
    }
  }

  static String _hintKey(String id) => 'guide.hint.$id.version';
}
