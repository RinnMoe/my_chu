import 'package:shared_preferences/shared_preferences.dart';

/// Stores the one-time campus prompt and versioned contextual guide hints.
class GuidePreferences {
  static const currentMainTourVersion = 1;
  static const currentOnboardingFlowVersion = 1;
  static const currentHintVersion = 2;

  static const mainTourKey = 'guide.main.version';
  static const onboardingFlowKey = 'guide.onboarding.flow.version';

  static const scheduleFeatureTourHintId = 'schedule_course';
  static const scheduleCourseHintId = scheduleFeatureTourHintId;
  static const pageManagementHintId = 'page_management';

  Future<bool> shouldShowCampusPrompt() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return (preferences.getInt(mainTourKey) ?? 0) < currentMainTourVersion;
    } catch (_) {
      return false;
    }
  }

  Future<bool> shouldShowMainTour() => shouldShowCampusPrompt();

  Future<void> markCampusPromptSeen() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(mainTourKey, currentMainTourVersion);
    } catch (_) {}
  }

  Future<void> markMainTourSeen() => markCampusPromptSeen();

  Future<void> resetMainTour() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(mainTourKey);
    } catch (_) {}
  }

  Future<bool> shouldShowOnboardingFlow() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return (preferences.getInt(onboardingFlowKey) ?? 0) <
          currentOnboardingFlowVersion;
    } catch (_) {
      return false;
    }
  }

  Future<void> markOnboardingFlowSeen() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(onboardingFlowKey, currentOnboardingFlowVersion);
    } catch (_) {}
  }

  Future<bool> shouldShowHint(String id, int version) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return (preferences.getInt(_hintKey(id)) ?? 0) < version;
    } catch (_) {
      return false;
    }
  }

  Future<void> markHintSeen(String id, int version) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_hintKey(id), version);
    } catch (_) {}
  }

  static String _hintKey(String id) => 'guide.hint.$id.version';
}
