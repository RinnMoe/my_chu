import 'guide_preferences.dart';
import 'navigation_layout_service.dart';
import 'root_navigation_service.dart';

enum OnboardingFlowStep { inactive, schedule, complete }

/// Coordinates the one continuous, cross-page first-run guide.
abstract final class OnboardingFlowService {
  static OnboardingFlowStep _step = OnboardingFlowStep.inactive;

  static OnboardingFlowStep get step => _step;

  static Future<void> start({bool includeSchedule = true}) async {
    if (!includeSchedule) {
      await _complete();
      return;
    }
    _step = OnboardingFlowStep.schedule;
    RootNavigationService.selectTab(
      NavigationLayoutService.academicScheduleKey,
    );
  }

  static Future<void> finish() async {
    if (_step != OnboardingFlowStep.schedule) return;
    await _complete();
  }

  static Future<void> _complete() async {
    _step = OnboardingFlowStep.complete;
    await GuidePreferences().markOnboardingFlowSeen();
    RootNavigationService.selectTab(NavigationLayoutService.hostHomeKey);
  }
}
