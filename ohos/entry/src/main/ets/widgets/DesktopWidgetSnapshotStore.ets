import fs from '@ohos.file.fs';
import { formBindingData } from '@kit.FormKit';

export const TODAY_SCHEDULE_FORM = 'today_schedule';
export const SCHEDULE_TARGET_ID = 'feature.academic.schedule';

const SNAPSHOT_FILE = 'desktop_widget_snapshot_v1.json';
const FORMS_FILE = 'desktop_widget_forms_v1.json';
const MAX_SNAPSHOT_BYTES = 2 * 1024 * 1024;
const EAST8_OFFSET_MS = 8 * 60 * 60 * 1000;
interface DesktopWidgetSchedulePayload {
  status: string;
  occurrences: Array<Object>;
}

interface DesktopWidgetSnapshotPayload {
  schemaVersion: number;
  generatedAt: string;
  timezoneOffsetMinutes: number;
  schedule: DesktopWidgetSchedulePayload;
}

const EMPTY_SCHEDULE: DesktopWidgetSchedulePayload = {
  status: 'calendarUnavailable',
  occurrences: [],
};

const EMPTY_SNAPSHOT_PAYLOAD: DesktopWidgetSnapshotPayload = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  timezoneOffsetMinutes: 480,
  schedule: EMPTY_SCHEDULE,
};
const EMPTY_SNAPSHOT = JSON.stringify(EMPTY_SNAPSHOT_PAYLOAD);

export interface DesktopWidgetOccurrence {
  id: string;
  date: string;
  courseName: string;
  location: string;
  startPeriod: number;
  endPeriod: number;
  periodLabel: string;
  startTime: string | null;
  endTime: string | null;
}

export interface DesktopWidgetSchedule {
  status: string;
  currentWeek: number | null;
  occurrences: Array<DesktopWidgetOccurrence>;
}

export interface DesktopWidgetSnapshot {
  schedule: DesktopWidgetSchedule;
}

export interface DesktopWidgetFormRegistration {
  formId: string;
  formName: string;
  dimension: number;
}

function utf8ByteLength(value: string): number {
  let size = 0;
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code <= 0x7f) {
      size++;
    } else if (code <= 0x7ff) {
      size += 2;
    } else if (
      code >= 0xd800 && code <= 0xdbff && index + 1 < value.length &&
      value.charCodeAt(index + 1) >= 0xdc00 &&
      value.charCodeAt(index + 1) <= 0xdfff
    ) {
      size += 4;
      index++;
    } else {
      size += 3;
    }
    if (size > MAX_SNAPSHOT_BYTES) return size;
  }
  return size;
}

function asRecord(value: Object | undefined): Record<string, Object> | null {
  if (value === undefined || value === null || typeof value !== 'object' ||
    Array.isArray(value)) {
    return null;
  }
  return value as Record<string, Object>;
}

function isOptionalString(value: Object | undefined): boolean {
  return value === null || value === undefined || typeof value === 'string';
}

export function parseDesktopWidgetSnapshot(
  source: string,
): DesktopWidgetSnapshot | null {
  if (utf8ByteLength(source) > MAX_SNAPSHOT_BYTES) return null;
  try {
    const root = asRecord(JSON.parse(source) as Object);
    if (root === null || root['schemaVersion'] !== 1 ||
      root['timezoneOffsetMinutes'] !== 480) {
      return null;
    }
    const schedule = asRecord(root['schedule']);
    if (schedule === null) {
      return null;
    }

    const statusValue = schedule['status'];
    const weekValue = schedule['currentWeek'];
    const rawOccurrences = schedule['occurrences'];
    if (typeof statusValue !== 'string' || !Array.isArray(rawOccurrences) ||
      !['signedOut', 'noSchedule', 'calendarUnavailable', 'ready']
        .includes(statusValue)) {
      return null;
    }
    if (statusValue !== 'ready' && rawOccurrences.length > 0) return null;
    if (weekValue !== undefined && weekValue !== null &&
      (typeof weekValue !== 'number' || !Number.isInteger(weekValue) || weekValue < 1)) {
      return null;
    }

    const occurrences: Array<DesktopWidgetOccurrence> = [];
    const occurrenceValues = rawOccurrences as Array<Object>;
    for (const raw of occurrenceValues) {
      const item = asRecord(raw);
      if (item === null) return null;
      const id = item['id'];
      const date = item['date'];
      const courseName = item['courseName'];
      const location = item['location'];
      const periodLabel = item['periodLabel'];
      const startTime = item['startTime'];
      const endTime = item['endTime'];
      const startPeriod = item['startPeriod'];
      const endPeriod = item['endPeriod'];
      if (typeof id !== 'string' || id.length === 0 ||
        typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
        typeof courseName !== 'string' || courseName.length === 0 ||
        typeof location !== 'string' || typeof periodLabel !== 'string' ||
        typeof startPeriod !== 'number' || typeof endPeriod !== 'number' ||
        startPeriod < 1 || endPeriod < startPeriod ||
        !isOptionalString(startTime) || !isOptionalString(endTime)) {
        return null;
      }
      occurrences.push({
        id: id,
        date: date,
        courseName: courseName,
        location: location,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        periodLabel: periodLabel,
        startTime: typeof startTime === 'string' ? startTime : null,
        endTime: typeof endTime === 'string' ? endTime : null,
      });
    }

    return {
      schedule: {
        status: statusValue,
        currentWeek: typeof weekValue === 'number' ? weekValue : null,
        occurrences: occurrences,
      },
    };
  } catch (_) {
    return null;
  }
}

function atomicWrite(path: string, source: string): void {
  const temporaryPath = `${path}.tmp`;
  const file = fs.openSync(
    temporaryPath,
    fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
  );
  try {
    fs.writeSync(file.fd, source);
  } finally {
    fs.closeSync(file);
  }
  fs.renameSync(temporaryPath, path);
}

export function writeDesktopWidgetSnapshot(
  filesDir: string,
  source: string,
): boolean {
  if (parseDesktopWidgetSnapshot(source) === null) return false;
  try {
    atomicWrite(`${filesDir}/${SNAPSHOT_FILE}`, source);
    return true;
  } catch (_) {
    return false;
  }
}

export function readDesktopWidgetSnapshot(
  filesDir: string,
): DesktopWidgetSnapshot | null {
  try {
    const source = fs.readTextSync(`${filesDir}/${SNAPSHOT_FILE}`);
    return parseDesktopWidgetSnapshot(source);
  } catch (_) {
    return null;
  }
}

function readRegistrations(filesDir: string): Array<DesktopWidgetFormRegistration> {
  try {
    const raw = JSON.parse(fs.readTextSync(`${filesDir}/${FORMS_FILE}`)) as Object;
    if (!Array.isArray(raw)) return [];
    const result: Array<DesktopWidgetFormRegistration> = [];
    const registrationValues = raw as Array<Object>;
    for (const itemValue of registrationValues) {
      const item = asRecord(itemValue);
      if (item === null) continue;
      const formId = item['formId'];
      const formName = item['formName'];
      const dimension = item['dimension'];
      if (typeof formId !== 'string' || formId.length === 0 ||
        typeof formName !== 'string' ||
        formName !== TODAY_SCHEDULE_FORM ||
        typeof dimension !== 'number') {
        continue;
      }
      result.push({ formId: formId, formName: formName, dimension: dimension });
    }
    return result;
  } catch (_) {
    return [];
  }
}

export function getDesktopWidgetFormRegistration(
  filesDir: string,
  formId: string,
): DesktopWidgetFormRegistration | null {
  const registration = readRegistrations(filesDir).find(
    (item) => item.formId === formId,
  );
  return registration ?? null;
}

export function getDesktopWidgetFormRegistrations(
  filesDir: string,
): Array<DesktopWidgetFormRegistration> {
  return readRegistrations(filesDir);
}

export function registerDesktopWidgetForm(
  filesDir: string,
  registration: DesktopWidgetFormRegistration,
): void {
  const registrations = readRegistrations(filesDir).filter(
    (item) => item.formId !== registration.formId,
  );
  registrations.push(registration);
  atomicWrite(`${filesDir}/${FORMS_FILE}`, JSON.stringify(registrations));
}

export function removeDesktopWidgetForm(filesDir: string, formId: string): void {
  const registrations = readRegistrations(filesDir).filter(
    (item) => item.formId !== formId,
  );
  atomicWrite(`${filesDir}/${FORMS_FILE}`, JSON.stringify(registrations));
}

export function createDesktopWidgetFormData(
  filesDir: string,
  formName: string,
  dimension: number,
): formBindingData.FormBindingData {
  let source = EMPTY_SNAPSHOT;
  try {
    source = fs.readTextSync(`${filesDir}/${SNAPSHOT_FILE}`);
  } catch (_) {
    // A newly added card renders an empty state until the host publishes V1.
  }
  const snapshot = parseDesktopWidgetSnapshot(source);
  return formBindingData.createFormBindingData({
    formName: formName,
    snapshot: snapshot === null ? EMPTY_SNAPSHOT : source,
    snapshotAvailable: snapshot !== null,
    formDimension: dimension,
  });
}

export function todayEast8Date(): string {
  return new Date(Date.now() + EAST8_OFFSET_MS).toISOString().slice(0, 10);
}
