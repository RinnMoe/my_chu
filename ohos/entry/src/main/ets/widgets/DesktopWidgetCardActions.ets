import { SCHEDULE_TARGET_ID } from './DesktopWidgetSnapshotStore';

const APP_BUNDLE_NAME = 'moe.rinn.mychu.hm';
const ENTRY_ABILITY_NAME = 'EntryAbility';

export function openDesktopWidgetTarget(
  component: Object,
  targetId: string,
): void {
  postCardAction(component, {
    action: 'router',
    bundleName: APP_BUNDLE_NAME,
    moduleName: 'entry',
    abilityName: ENTRY_ABILITY_NAME,
    params: { desktopWidgetTargetId: targetId },
  });
}

export function openTodaySchedule(component: Object): void {
  openDesktopWidgetTarget(component, SCHEDULE_TARGET_ID);
}
