import { DesktopWidgetSnapshot, DesktopWidgetOccurrence } from './DesktopWidgetSnapshotStore';

export interface WeekCourseSlot {
  startPeriod: number;
  endPeriod: number;
  courses: Array<DesktopWidgetOccurrence>;
}

export interface WeekScheduleData {
  today: string;
  weekStart: string;
  currentWeek: number | null;
  status: string;
  days: Array<Array<WeekCourseSlot>>;
}

const DAY_MS = 24 * 60 * 60 * 1000;

export function weekDateAt(weekStart: string, offset: number): string {
  return new Date(Date.parse(`${weekStart}T00:00:00Z`) + offset * DAY_MS).toISOString().slice(0, 10);
}

export function weekCourseColorIndex(name: string): number {
  let hash = 0;
  for (let index = 0; index < name.length; index++) {
    hash = (hash * 31 + name.charCodeAt(index)) | 0;
  }
  return (hash & 0x7fffffff) % 6;
}

export function projectWidgetWeek(snapshot: DesktopWidgetSnapshot | null, now: number): WeekScheduleData {
  const east8 = new Date(now + 8 * 60 * 60 * 1000);
  const today = east8.toISOString().slice(0, 10);
  const mondayOffset = (east8.getUTCDay() + 6) % 7;
  const weekStart = weekDateAt(today, -mondayOffset);
  const result: WeekScheduleData = {
    today: today, weekStart: weekStart, currentWeek: null,
    status: snapshot?.schedule.status ?? 'unavailable', days: [],
  };
  if (snapshot === null || snapshot.schedule.status !== 'ready') return result;
  const firstWeek = snapshot.schedule.firstWeekStartDate;
  const maxWeek = snapshot.schedule.maxWeek;
  if (firstWeek === null || maxWeek === null) {
    result.status = 'unavailable';
    return result;
  }
  const daysSinceStart = (Date.parse(`${today}T00:00:00Z`) - Date.parse(`${firstWeek}T00:00:00Z`)) / DAY_MS;
  if (daysSinceStart < 0 || daysSinceStart >= maxWeek * 7) {
    result.status = 'outsideTerm';
    return result;
  }
  result.currentWeek = Math.floor(daysSinceStart / 7) + 1;
  for (let day = 0; day < 7; day++) {
    const courses = snapshot.schedule.occurrences.filter((course: DesktopWidgetOccurrence) =>
      course.date === weekDateAt(weekStart, day)).sort((a: DesktopWidgetOccurrence, b: DesktopWidgetOccurrence) =>
      a.startPeriod - b.startPeriod || a.endPeriod - b.endPeriod || a.courseName.localeCompare(b.courseName));
    if (courses.some((course: DesktopWidgetOccurrence) => course.endPeriod > 11)) {
      result.status = 'unavailable';
      result.days = [];
      return result;
    }
    const blocks: Array<WeekCourseSlot> = [];
    for (const course of courses) {
      const previous = blocks.length > 0 ? blocks[blocks.length - 1] : null;
      if (previous !== null && course.startPeriod <= previous.endPeriod) {
        previous.endPeriod = Math.max(previous.endPeriod, course.endPeriod);
        previous.courses.push(course);
      } else {
        blocks.push({ startPeriod: course.startPeriod, endPeriod: course.endPeriod, courses: [course] });
      }
    }
    // Explicit empty slots keep every day's eleven periods aligned.
    const slots: Array<WeekCourseSlot> = [];
    let period = 1;
    for (const block of blocks) {
      while (period < block.startPeriod) {
        slots.push({ startPeriod: period, endPeriod: period, courses: [] });
        period++;
      }
      slots.push(block);
      period = block.endPeriod + 1;
    }
    while (period <= 11) {
      slots.push({ startPeriod: period, endPeriod: period, courses: [] });
      period++;
    }
    result.days.push(slots);
  }
  return result;
}
