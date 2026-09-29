import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { UIAbility } from '@kit.AbilityKit';
import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import preferences from '@ohos.data.preferences';

const CHANNEL_NAME = 'mychu/scheduled_alerts';
const STORE_NAME = 'mychu_scheduled_alerts';
const SCHEDULES_KEY = 'schedules.v1';
const RECEIPTS_KEY = 'receipts.v1';
const NEXT_NOTIFICATION_ID_KEY = 'next_notification_id.v1';
const MAX_SCHEDULED_ALERTS = 64;
const MAX_HORIZON_MS = 14 * 24 * 60 * 60 * 1000;

interface StoredHarmonyAlert {
  accountKey: string;
  providerId: string;
  eventId: string;
  triggerAt: number;
  title: string;
  body?: string;
  targetAppId?: string;
  validUntil: number;
  reminderId: number;
  notificationId: number;
}

interface StoredHarmonyReceipt {
  key: string;
  accountKey: string;
  providerId: string;
  eventId: string;
  title: string;
  body?: string;
  targetAppId?: string;
  validUntil: number;
  deliveredAt: number;
}

interface ReceiptChannelItem {
  key: string;
  accountKey: string;
  providerId: string;
  eventId: string;
  title: string;
  body?: string;
  targetAppId?: string;
  validUntil: number;
  deliveredAt: number;
}

interface NotificationIdAllocation {
  id: number;
  next: number;
}

/** Native adapter for the shared, account-scoped ScheduledAlertDraft contract. */
export default class MychuHarmonyScheduledAlertPlugin
  implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return 'MychuHarmonyScheduledAlertPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_NAME,
    );
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.ability = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      switch (call.method) {
        case 'replace':
          await this.replace(call);
          result.success(null);
          return;
        case 'clearProvider':
          await this.clearProvider(call);
          result.success(null);
          return;
        case 'clearAll':
          await this.clearAll();
          result.success(null);
          return;
        case 'reschedule':
          await this.reschedule();
          result.success(null);
          return;
        case 'consumeReceipts':
          result.success(await this.consumeReceipts());
          return;
        default:
          result.notImplemented();
          return;
      }
    } catch (_) {
      result.error(
        'SCHEDULE_FAILED',
        'Harmony scheduled reminder operation failed',
        null,
      );
    }
  }

  private async getStore(): Promise<preferences.Preferences | null> {
    const ability = this.ability;
    if (ability === null) return null;
    return await preferences.getPreferences(ability.context, STORE_NAME);
  }

  private async readAlerts(
    store: preferences.Preferences,
  ): Promise<StoredHarmonyAlert[]> {
    const raw = await store.get(SCHEDULES_KEY, '[]');
    if (typeof raw !== 'string') return [];
    try {
      const values = JSON.parse(raw) as Array<Record<string, string | number>>;
      if (!Array.isArray(values)) return [];
      const alerts: StoredHarmonyAlert[] = [];
      for (const value of values) {
        const accountKey = value['accountKey'];
        const providerId = value['providerId'];
        const eventId = value['eventId'];
        const triggerAt = value['triggerAt'];
        const title = value['title'];
        const validUntil = value['validUntil'];
        const reminderId = value['reminderId'];
        const notificationId = value['notificationId'];
        if (
          typeof accountKey !== 'string' || accountKey.length === 0 ||
          typeof providerId !== 'string' || providerId.length === 0 ||
          typeof eventId !== 'string' || eventId.length === 0 ||
          typeof triggerAt !== 'number' || typeof title !== 'string' ||
          title.length === 0 || typeof validUntil !== 'number' ||
          typeof reminderId !== 'number' || typeof notificationId !== 'number'
        ) continue;
        const alert: StoredHarmonyAlert = {
          accountKey: accountKey,
          providerId: providerId,
          eventId: eventId,
          triggerAt: triggerAt,
          title: title,
          validUntil: validUntil,
          reminderId: reminderId,
          notificationId: notificationId,
        };
        const body = value['body'];
        const targetAppId = value['targetAppId'];
        if (typeof body === 'string' && body.length > 0) alert.body = body;
        if (typeof targetAppId === 'string' && targetAppId.length > 0) {
          alert.targetAppId = targetAppId;
        }
        alerts.push(alert);
      }
      return alerts;
    } catch (_) {
      return [];
    }
  }

  private async readReceipts(
    store: preferences.Preferences,
  ): Promise<StoredHarmonyReceipt[]> {
    const raw = await store.get(RECEIPTS_KEY, '[]');
    if (typeof raw !== 'string') return [];
    try {
      const values = JSON.parse(raw) as Array<Record<string, string | number>>;
      if (!Array.isArray(values)) return [];
      const receipts: StoredHarmonyReceipt[] = [];
      for (const value of values) {
        const key = value['key'];
        const accountKey = value['accountKey'];
        const providerId = value['providerId'];
        const eventId = value['eventId'];
        const title = value['title'];
        const validUntil = value['validUntil'];
        const deliveredAt = value['deliveredAt'];
        if (
          typeof key !== 'string' || typeof accountKey !== 'string' ||
          typeof providerId !== 'string' || typeof eventId !== 'string' ||
          typeof title !== 'string' || typeof validUntil !== 'number' ||
          typeof deliveredAt !== 'number'
        ) continue;
        const receipt: StoredHarmonyReceipt = {
          key: key,
          accountKey: accountKey,
          providerId: providerId,
          eventId: eventId,
          title: title,
          validUntil: validUntil,
          deliveredAt: deliveredAt,
        };
        const body = value['body'];
        const targetAppId = value['targetAppId'];
        if (typeof body === 'string' && body.length > 0) receipt.body = body;
        if (typeof targetAppId === 'string' && targetAppId.length > 0) {
          receipt.targetAppId = targetAppId;
        }
        receipts.push(receipt);
      }
      return receipts;
    } catch (_) {
      return [];
    }
  }

  private parseIncomingAlerts(
    accountKey: string,
    providerId: string,
    raw: string,
  ): StoredHarmonyAlert[] {
    const values = JSON.parse(raw) as Array<Record<string, string | number>>;
    if (!Array.isArray(values)) throw new Error('invalid alerts');
    const now = Date.now();
    const unique = new Map<string, StoredHarmonyAlert>();
    for (const value of values) {
      const eventId = value['eventId'];
      const triggerAt = value['triggerAt'];
      const title = value['title'];
      const validUntil = value['validUntil'];
      if (
        typeof eventId !== 'string' || eventId.trim().length === 0 ||
        typeof triggerAt !== 'number' || typeof title !== 'string' ||
        title.trim().length === 0 || typeof validUntil !== 'number' ||
        triggerAt <= now || triggerAt > now + MAX_HORIZON_MS ||
        validUntil < triggerAt
      ) continue;
      const alert: StoredHarmonyAlert = {
        accountKey: accountKey,
        providerId: providerId,
        eventId: eventId.trim(),
        triggerAt: triggerAt,
        title: title.trim().slice(0, 80),
        validUntil: validUntil,
        reminderId: 0,
        notificationId: 0,
      };
      const body = value['body'];
      const targetAppId = value['targetAppId'];
      if (typeof body === 'string' && body.trim().length > 0) {
        alert.body = body.trim().slice(0, 160);
      }
      if (typeof targetAppId === 'string' && targetAppId.trim().length > 0) {
        alert.targetAppId = targetAppId.trim();
      }
      unique.set(this.identity(alert), alert);
    }
    const result: StoredHarmonyAlert[] = [];
    unique.forEach((alert) => result.push(alert));
    return result.sort((a, b) => a.triggerAt - b.triggerAt);
  }

  private identity(alert: StoredHarmonyAlert): string {
    return `${alert.accountKey}|${alert.providerId}|${alert.eventId}|${alert.triggerAt}`;
  }

  private async replace(call: MethodCall): Promise<void> {
    const accountKey = call.argument('accountKey') as string;
    const providerId = call.argument('providerId') as string;
    const raw = call.argument('alerts') as string;
    if (
      typeof accountKey !== 'string' || accountKey.length === 0 ||
      typeof providerId !== 'string' || providerId.length === 0 ||
      typeof raw !== 'string'
    ) throw new Error('invalid payload');

    const store = await this.getStore();
    if (store === null) throw new Error('ability unavailable');
    const alerts = await this.readAlerts(store);
    const receipts = await this.readReceipts(store);
    const now = Date.now();
    const active = this.collectDue(alerts, receipts, now);
    const replaced = active.filter(
      (item) => item.accountKey === accountKey && item.providerId === providerId,
    );
    for (const item of replaced) await this.cancel(item.reminderId);

    const retained = active.filter(
      (item) => item.accountKey !== accountKey || item.providerId !== providerId,
    );
    const incoming = this.parseIncomingAlerts(accountKey, providerId, raw);
    const bounded = [...retained, ...incoming]
      .sort((a, b) => a.triggerAt - b.triggerAt)
      .slice(0, MAX_SCHEDULED_ALERTS);
    const selected = new Set<string>(bounded.map((item) => this.identity(item)));
    for (const item of retained) {
      if (!selected.has(this.identity(item))) await this.cancel(item.reminderId);
    }

    const usedNotificationIds = new Set<number>(
      bounded
        .filter((item) => item.notificationId > 0)
        .map((item) => item.notificationId),
    );
    let nextId = await this.readNextNotificationId(store);
    for (const item of bounded) {
      if (item.notificationId > 0) continue;
      const allocated = this.allocateNotificationId(usedNotificationIds, nextId);
      item.notificationId = allocated.id;
      nextId = allocated.next;
    }

    const reconciled = await this.reconcile(bounded);
    await this.writeState(store, reconciled, receipts, nextId);
  }

  private async clearProvider(call: MethodCall): Promise<void> {
    const accountKey = call.argument('accountKey') as string;
    const providerId = call.argument('providerId') as string;
    if (
      typeof accountKey !== 'string' || accountKey.length === 0 ||
      typeof providerId !== 'string' || providerId.length === 0
    ) return;
    const store = await this.getStore();
    if (store === null) return;
    const alerts = await this.readAlerts(store);
    const receipts = await this.readReceipts(store);
    const removed = alerts.filter(
      (item) => item.accountKey === accountKey && item.providerId === providerId,
    );
    for (const item of removed) await this.cancel(item.reminderId);
    await this.writeState(
      store,
      alerts.filter(
        (item) => item.accountKey !== accountKey || item.providerId !== providerId,
      ),
      receipts.filter(
        (item) => item.accountKey !== accountKey || item.providerId !== providerId,
      ),
      await this.readNextNotificationId(store),
    );
  }

  private async clearAll(): Promise<void> {
    const store = await this.getStore();
    if (store === null) return;
    const alerts = await this.readAlerts(store);
    for (const item of alerts) await this.cancel(item.reminderId);
    await this.writeState(store, [], [], await this.readNextNotificationId(store));
  }

  private async reschedule(): Promise<void> {
    const store = await this.getStore();
    if (store === null) return;
    const alerts = await this.readAlerts(store);
    const receipts = await this.readReceipts(store);
    const active = this.collectDue(alerts, receipts, Date.now());
    const reconciled = await this.reconcile(active);
    await this.writeState(
      store,
      reconciled,
      receipts,
      await this.readNextNotificationId(store),
    );
  }

  private async consumeReceipts(): Promise<ReceiptChannelItem[]> {
    const store = await this.getStore();
    if (store === null) return [];
    const alerts = await this.readAlerts(store);
    const receipts = await this.readReceipts(store);
    const active = this.collectDue(alerts, receipts, Date.now());
    const result: ReceiptChannelItem[] = [];
    for (const item of receipts) {
      const receipt: ReceiptChannelItem = {
        key: item.key,
        accountKey: item.accountKey,
        providerId: item.providerId,
        eventId: item.eventId,
        title: item.title,
        validUntil: item.validUntil,
        deliveredAt: item.deliveredAt,
      };
      if (item.body !== undefined) receipt.body = item.body;
      if (item.targetAppId !== undefined) receipt.targetAppId = item.targetAppId;
      result.push(receipt);
    }
    await this.writeState(
      store,
      active,
      [],
      await this.readNextNotificationId(store),
    );
    return result;
  }

  /** Moves elapsed, successfully-published alerts into the durable receipt queue. */
  private collectDue(
    alerts: StoredHarmonyAlert[],
    receipts: StoredHarmonyReceipt[],
    now: number,
  ): StoredHarmonyAlert[] {
    const receiptKeys = new Set<string>(receipts.map((item) => item.key));
    const active: StoredHarmonyAlert[] = [];
    for (const alert of alerts) {
      if (alert.triggerAt > now && alert.validUntil >= now) {
        active.push(alert);
        continue;
      }
      if (
        alert.triggerAt <= now && alert.validUntil >= now &&
        alert.reminderId > 0
      ) {
        const key = `${alert.providerId}|${alert.eventId}|${alert.triggerAt}`;
        if (!receiptKeys.has(key)) {
          const receipt: StoredHarmonyReceipt = {
            key: key,
            accountKey: alert.accountKey,
            providerId: alert.providerId,
            eventId: alert.eventId,
            title: alert.title,
            validUntil: alert.validUntil,
            deliveredAt: now,
          };
          if (alert.body !== undefined) receipt.body = alert.body;
          if (alert.targetAppId !== undefined) receipt.targetAppId = alert.targetAppId;
          receipts.push(receipt);
          receiptKeys.add(key);
        }
      }
    }
    return active;
  }

  private async reconcile(
    alerts: StoredHarmonyAlert[],
  ): Promise<StoredHarmonyAlert[]> {
    if (alerts.length === 0) return alerts;
    let enabled = false;
    try {
      enabled = await notificationManager.isNotificationEnabled();
    } catch (_) {
      return alerts;
    }
    if (!enabled) return alerts;

    let valid: Array<reminderAgentManager.ReminderInfo> = [];
    try {
      valid = await reminderAgentManager.getAllValidReminders();
    } catch (_) {
      return alerts;
    }
    const activeByNotificationId = new Map<number, number>();
    for (const item of valid) {
      const notificationId = item.reminderReq.notificationId;
      if (typeof notificationId === 'number') {
        activeByNotificationId.set(notificationId, item.reminderId);
      }
    }

    for (const alert of alerts) {
      const existingId = activeByNotificationId.get(alert.notificationId);
      if (existingId !== undefined) {
        alert.reminderId = existingId;
        continue;
      }
      try {
        const request: reminderAgentManager.ReminderRequestTimer = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
          triggerTimeInSeconds: Math.max(
            1,
            Math.ceil((alert.triggerAt - Date.now()) / 1000),
          ),
          title: alert.title,
          content: alert.body ?? alert.title,
          notificationId: alert.notificationId,
          ringDuration: 0,
          wantAgent: {
            pkgName: 'moe.rinn.mychu.hm',
            abilityName: 'EntryAbility',
          },
        };
        alert.reminderId = await reminderAgentManager.publishReminder(request);
      } catch (_) {
        // Keep the bounded local schedule so a later settings refresh can retry.
        alert.reminderId = 0;
      }
    }
    return alerts;
  }

  private async cancel(reminderId: number): Promise<void> {
    if (reminderId <= 0) return;
    try {
      await reminderAgentManager.cancelReminder(reminderId);
    } catch (_) {
      // The reminder may already have fired or expired.
    }
  }

  private async readNextNotificationId(
    store: preferences.Preferences,
  ): Promise<number> {
    const value = await store.get(NEXT_NOTIFICATION_ID_KEY, 1);
    return typeof value === 'number' && value > 0 ? Math.floor(value) : 1;
  }

  private allocateNotificationId(
    used: Set<number>,
    start: number,
  ): NotificationIdAllocation {
    let candidate = start > 0 && start <= 2147483647 ? start : 1;
    while (used.has(candidate)) {
      candidate = candidate >= 2147483647 ? 1 : candidate + 1;
    }
    used.add(candidate);
    return { id: candidate, next: candidate >= 2147483647 ? 1 : candidate + 1 };
  }

  private async writeState(
    store: preferences.Preferences,
    alerts: StoredHarmonyAlert[],
    receipts: StoredHarmonyReceipt[],
    nextNotificationId: number,
  ): Promise<void> {
    await store.put(SCHEDULES_KEY, JSON.stringify(alerts));
    await store.put(RECEIPTS_KEY, JSON.stringify(receipts.slice(-64)));
    await store.put(NEXT_NOTIFICATION_ID_KEY, nextNotificationId);
    await store.flush();
  }
}
