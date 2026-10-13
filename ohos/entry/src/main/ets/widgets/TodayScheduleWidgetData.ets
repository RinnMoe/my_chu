import { DesktopWidgetOccurrence, DesktopWidgetSnapshot } from './DesktopWidgetSnapshotStore';

export interface TodayScheduleWidgetData {
  status: string;
  sourceLabel: string;
  courses: Array<DesktopWidgetOccurrence>;
}

export function projectWidgetToday(snapshot: DesktopWidgetSnapshot | null, now: number = Date.now()): TodayScheduleWidgetData {
  const today = new Date(now + 8 * 3600000).toISOString().slice(0, 10);
  if (snapshot === null) return { status: 'unavailable', sourceLabel: '', courses: [] };
  const recent = snapshot.recentSchedule;
  const covered = snapshot.schedule.status !== 'signedOut' && recent !== null &&
    today >= recent.startDate && today <= recent.endDate;
  const fetchedDay = recent === null ? '' : new Date(Date.parse(recent.fetchedAt) + 8 * 3600000).toISOString().slice(0, 10);
  const status = covered ? 'ready' : snapshot.schedule.status;
  const source = covered && recent !== null ? recent.occurrences : snapshot.schedule.occurrences;
  const courses = status !== 'ready' ? [] : source.filter((course: DesktopWidgetOccurrence) => {
    if (course.date !== today) return false;
    const end = course.endAt ?? (course.endTime === null ? '' : course.date + 'T' + course.endTime + ':00+08:00');
    return end === '' || isNaN(Date.parse(end)) || Date.parse(end) > now;
  }).sort((a: DesktopWidgetOccurrence, b: DesktopWidgetOccurrence) =>
    (a.startTime ?? '').localeCompare(b.startTime ?? '') || a.startPeriod - b.startPeriod ||
    a.endPeriod - b.endPeriod || a.courseName.localeCompare(b.courseName));
  return {
    status: status,
    sourceLabel: covered ? (recent?.fresh && fetchedDay === today ? '' : '课程待更新 · 打开更新') :
      status === 'ready' ? '课程可能未反映调休，打开更新' : '',
    courses: courses,
  };
}
