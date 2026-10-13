import Flutter
import UIKit
import UserNotifications
import ActivityKit

/// Kept only to end activities created by retired releases; no publishing path.
@available(iOS 16.1, *)
struct MyCHULiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let phase: String
    let title: String
    let body: String
    let shortCriticalText: String?
    let progress: Int
    let progressMax: Int
    let startAt: Date?
    let endAt: Date?
    let targetAppId: String
  }

  let definitionId: String
  let ownerGeneration: String
  let targetAppId: String
}


final class MyCHUTimeReminderPlugin: NSObject, FlutterPlugin {
  private static let prefix = "mychu.time.v2."
  private let defaults = UserDefaults.standard
  private let center = UNUserNotificationCenter.current()
  private var tail: Task<Void, Never>?
  private let targets = ["course": "feature.academic.schedule", "exam": "feature.academic.exams", "deadline": "feature.portal.personal"]

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MyCHUTimeReminderPlugin()
    instance.tail = Task { @MainActor in await instance.resetLegacy() }
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
      name: "mychu/time_reminders", binaryMessenger: registrar.messenger()))
  }
  private var owner: String { defaults.string(forKey: Self.prefix + "owner") ?? "" }
  private var generation: Int { defaults.integer(forKey: Self.prefix + "generation") }
  private var events: [[String: Any]] {
    get { defaults.array(forKey: Self.prefix + "events") as? [[String: Any]] ?? [] }
    set { defaults.set(newValue, forKey: Self.prefix + "events") }
  }
  private func identity(_ event: [String: Any]) -> String {
    let parts = [owner, event["category"] as? String ?? "", event["eventId"] as? String ?? ""]
    return Self.prefix + parts.map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
  }
  private func matches(_ args: [String: Any]) -> Bool {
    !owner.isEmpty && args["owner"] as? String == owner && (args["generation"] as? NSNumber)?.intValue == generation
  }
  private func cancel(_ ids: [String], delivered: Bool = true) {
    center.removePendingNotificationRequests(withIdentifiers: ids)
    if delivered { center.removeDeliveredNotifications(withIdentifiers: ids) }
  }
  private func deactivate() {
    cancel(events.map(identity))
    events = []
    defaults.set(generation + 1, forKey: Self.prefix + "generation")
    defaults.removeObject(forKey: Self.prefix + "owner")
    defaults.removeObject(forKey: Self.prefix + "ledger")
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let previous = tail
    tail = Task { @MainActor in
      await previous?.value
      let args = call.arguments as? [String: Any] ?? [:]
      do {
        switch call.method {
        case "resetLegacy":
          await self.resetLegacy(); result(nil)
        case "status":
          let status = await self.center.notificationSettings()
          result(["notifications": status.authorizationStatus == .authorized || status.authorizationStatus == .provisional, "exact": true])
        case "activate":
          guard let token = args["owner"] as? String, token.count == 48 else { throw ReminderError.invalid }
          if self.owner != token { self.deactivate() }
          self.defaults.set(token, forKey: Self.prefix + "owner")
          self.defaults.set(self.generation + 1, forKey: Self.prefix + "generation")
          result(self.generation)
        case "deactivate": self.deactivate(); result(nil)
        case "replaceCategory":
          guard self.matches(args) else { result(nil); return }
          guard let category = args["category"] as? String, self.targets[category] != nil,
            let input = args["events"] as? [[String: Any]], let active = args["activeEvents"] as? [String]
          else { throw ReminderError.invalid }
          let now = Date().timeIntervalSince1970 * 1000
          let old = self.events
          var ledger = self.defaults.dictionary(forKey: Self.prefix + "ledger") as? [String: Double] ?? [:]
          for event in old where event["scheduled"] as? Bool == true {
            if let trigger = event["triggerAt"] as? Double, trigger <= now,
               let until = event["validUntil"] as? Double {
              ledger[self.identity(event)] = until
            }
          }
          ledger = ledger.filter { $0.value > now }
          self.defaults.set(ledger, forKey: Self.prefix + "ledger")
          var incoming: [[String: Any]] = []
          var seen = Set<String>()
          for var event in input {
            guard let id = event["eventId"] as? String, !id.isEmpty,
              let title = event["title"] as? String, !title.isEmpty,
              let trigger = event["triggerAt"] as? Double, let until = event["validUntil"] as? Double,
              trigger > now, trigger <= now + 14 * 86400000, until >= trigger,
              event["category"] as? String == category, event["targetAppId"] as? String == self.targets[category], seen.insert(id).inserted
            else { continue }
            event["delivered"] = ledger[self.identity(event)] != nil
            event["scheduled"] = false
            incoming.append(event)
          }
          let covered = args["coveredDays"] as? [Double]
          let outside = old.filter { event in
            guard event["category"] as? String == category, let covered = covered else { return false }
            let at = event["validUntil"] as? Double ?? 0
            return !covered.contains { at >= $0 && at < $0 + 86400000 }
          }
          let retained = old.filter { $0["category"] as? String == category &&
            active.contains($0["eventId"] as? String ?? "") && ledger[self.identity($0)] != nil &&
            !seen.contains($0["eventId"] as? String ?? "") }
          let next = incoming + retained + outside
          for event in old where event["category"] as? String == category {
            let keep = next.contains { $0["eventId"] as? String == event["eventId"] as? String }
            self.cancel([self.identity(event)], delivered: !keep)
          }
          self.events = old.filter { $0["category"] as? String != category } + next
          try await self.reconcile(); result(nil)
        case "cancelCategory":
          if self.matches(args), let category = args["category"] as? String {
            try await self.reconcile()
            self.cancel(self.events.filter { $0["category"] as? String == category }.map(self.identity))
            self.events = self.events.filter { $0["category"] as? String != category }
            try await self.reconcile()
          }
          result(nil)
        case "reschedule": try await self.reconcile(); result(nil)
        case "validateLaunch":
          let now = Date().timeIntervalSince1970 * 1000
          result(args["owner"] as? String == self.owner && !self.owner.isEmpty && self.events.contains {
            $0["eventId"] as? String == args["eventId"] as? String &&
            $0["category"] as? String == args["category"] as? String &&
            ($0["validUntil"] as? Double ?? 0) > now &&
            self.targets[$0["category"] as? String ?? ""] == args["targetAppId"] as? String
          })
        default: result(FlutterMethodNotImplemented)
        }
      } catch { result(FlutterError(code: "REMINDER_FAILED", message: "时间提醒操作失败", details: nil)) }
    }
  }
  private func reconcile() async throws {
    let now = Date().timeIntervalSince1970 * 1000
    let old = events
    let pending = await center.pendingNotificationRequests()
    let known = Set(pending.map(\.identifier))
    var ledger = defaults.dictionary(forKey: Self.prefix + "ledger") as? [String: Double] ?? [:]
    var live: [[String: Any]] = []
    for var event in old {
      let id = identity(event)
      let until = event["validUntil"] as? Double ?? 0
      let trigger = event["triggerAt"] as? Double ?? 0
      if until <= now { cancel([id]); continue }
      if event["scheduled"] as? Bool == true && trigger <= now { ledger[id] = until }
      if ledger[id] != nil { event["delivered"] = true }
      if trigger > now || event["delivered"] as? Bool == true { live.append(event) }
      else { cancel([id]) }
    }
    defaults.set(ledger.filter { $0.value > now }, forKey: Self.prefix + "ledger")
    let status = await center.notificationSettings()
    let enabled = !owner.isEmpty && (status.authorizationStatus == .authorized || status.authorizationStatus == .provisional)
    let candidates = live.filter { $0["delivered"] as? Bool != true && ($0["triggerAt"] as? Double ?? 0) > now }
      .sorted { ($0["triggerAt"] as? Double ?? 0) < ($1["triggerAt"] as? Double ?? 0) }.prefix(64)
    let selected = enabled ? Set(candidates.map(identity)) : Set<String>()
    center.removePendingNotificationRequests(withIdentifiers: pending.filter {
      $0.identifier.hasPrefix(Self.prefix) && !selected.contains($0.identifier)
    }.map(\.identifier))
    var firstError: Error?
    for index in live.indices {
      let event = live[index]; let id = identity(event)
      guard selected.contains(id) else { live[index]["scheduled"] = false; continue }
      // Replacing the same identifier updates content/lead policy, without duplicates.
      let content = UNMutableNotificationContent()
      content.title = event["title"] as? String ?? ""
      content.body = event["body"] as? String ?? ""
      content.sound = .default
      content.categoryIdentifier = "mychu_time_" + (event["category"] as? String ?? "")
      content.userInfo = ["source": "timeReminder", "owner": owner,
        "eventId": event["eventId"] as? String ?? "", "category": event["category"] as? String ?? "",
        "targetAppId": event["targetAppId"] as? String ?? "", "validUntil": event["validUntil"] as? Double ?? 0]
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, ((event["triggerAt"] as? Double ?? 0) - now) / 1000), repeats: false)
      do {
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        live[index]["scheduled"] = true
      } catch { live[index]["scheduled"] = known.contains(id); firstError = error }
    }
    events = live
    if let error = firstError { throw error }
  }
  private func resetLegacy() async {
    guard !defaults.bool(forKey: Self.prefix + "legacy_reset") else { return }
    let pending = await center.pendingNotificationRequests()
    let delivered = await center.deliveredNotifications()
    let retired = Set((defaults.stringArray(forKey: "mychu.scheduled_alert_ids.v1") ?? []) +
      pending.map(\.identifier).filter { $0.hasPrefix("mychu.alert.") || Int($0) != nil } +
      delivered.map { $0.request.identifier }.filter { $0.hasPrefix("mychu.alert.") || Int($0) != nil })
    cancel(Array(retired))
    if #available(iOS 16.1, *) {
      for activity in Activity<MyCHULiveActivityAttributes>.activities {
        await activity.end(dismissalPolicy: .immediate)
      }
    }
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("mychu.scheduled.") || key == "mychu.scheduled_alert_ids.v1" {
      defaults.removeObject(forKey: key)
    }
    center.setNotificationCategories(Set(["course", "exam", "deadline"].map {
      UNNotificationCategory(identifier: "mychu_time_" + $0, actions: [], intentIdentifiers: [], options: [])
    }))
    defaults.set(true, forKey: Self.prefix + "legacy_reset")
  }
  private enum ReminderError: Error { case invalid }
}
