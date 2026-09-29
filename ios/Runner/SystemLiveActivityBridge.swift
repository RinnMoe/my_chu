import ActivityKit
import Flutter
import UIKit

/// Shared ActivityKit attributes for the MyCHU course activity.
///
/// The ActivityKit extension uses the same file/contract. Only sanitized course
/// display data crosses this boundary; credentials and campus responses stay
/// in the Flutter host.
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

/// Flutter bridge for local-first Apple Live Activities.
///
/// No push token is requested. The app starts and reconciles activities from
/// the current schedule snapshot whenever Flutter explicitly refreshes it.
final class MyCHUSystemLiveActivityPlugin: NSObject, FlutterPlugin {
  private static let channelName = "mychu/system_live_activity"

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MyCHUSystemLiveActivityPlugin()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      if call.method == "getStatus" {
        result(["supported": false, "activitiesEnabled": false])
      } else {
        result(nil)
      }
      return
    }

    switch call.method {
    case "upsert":
      guard
        let arguments = call.arguments as? [String: Any],
        let rawPackage = arguments["package"] as? String,
        let packageData = rawPackage.data(using: .utf8),
        let package = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any]
      else {
        result(FlutterError(
          code: "INVALID_PAYLOAD",
          message: "live activity payload is invalid",
          details: nil
        ))
        return
      }
      Task {
        await self.upsert(package: package)
        result(nil)
      }
    case "cancel", "cancelDemo", "clearAll":
      Task {
        await self.endAll()
        result(nil)
      }
    case "openChannelSettings", "openPromotionSettings":
      DispatchQueue.main.async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(false)
          return
        }
        UIApplication.shared.open(url) { opened in
          result(opened)
        }
      }
    case "getStatus":
      result([
        "supported": true,
        "activitiesEnabled": ActivityAuthorizationInfo().areActivitiesEnabled,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 16.1, *)
  private func upsert(package: [String: Any]) async {
    guard
      let definitionId = package["definitionId"] as? String,
      let targetAppId = package["targetAppId"] as? String,
      let ownerGeneration = package["ownerGeneration"] as? String,
      let render = package["render"] as? [String: Any]
    else { return }

    let cancelExisting = package["cancelExisting"] as? Bool ?? false
    let state = contentState(
      render: render,
      targetAppId: targetAppId
    )
    let matching = Activity<MyCHULiveActivityAttributes>.activities.filter {
      $0.attributes.definitionId == definitionId &&
        $0.attributes.ownerGeneration == ownerGeneration
    }
    if cancelExisting || state.phase == "ended" {
      for activity in matching {
        await end(activity)
      }
      return
    }

    let attributes = MyCHULiveActivityAttributes(
      definitionId: definitionId,
      ownerGeneration: ownerGeneration,
      targetAppId: targetAppId
    )
    if let current = matching.first {
      if #available(iOS 16.2, *) {
        let content = ActivityContent(
          state: state,
          staleDate: date(render["validUntil"])
        )
        await current.update(content)
      } else {
        await current.update(using: state)
      }
      for duplicate in matching.dropFirst() {
        await end(duplicate)
      }
      return
    }
    if #available(iOS 16.2, *) {
      let content = ActivityContent(
        state: state,
        staleDate: date(render["validUntil"])
      )
      _ = try? Activity.request(
        attributes: attributes,
        content: content,
        pushType: nil
      )
    } else {
      _ = try? Activity.request(
        attributes: attributes,
        contentState: state,
        pushType: nil
      )
    }
  }

  @available(iOS 16.1, *)
  private func endAll() async {
    for activity in Activity<MyCHULiveActivityAttributes>.activities {
      await end(activity)
    }
  }

  @available(iOS 16.1, *)
  private func end(_ activity: Activity<MyCHULiveActivityAttributes>) async {
    if #available(iOS 16.2, *) {
      await activity.end(nil, dismissalPolicy: .immediate)
    } else {
      await activity.end(using: nil, dismissalPolicy: .immediate)
    }
  }

  @available(iOS 16.1, *)
  private func contentState(
    render: [String: Any],
    targetAppId: String
  ) -> MyCHULiveActivityAttributes.ContentState {
    let phase = render["phase"] as? String ?? "active"
    return MyCHULiveActivityAttributes.ContentState(
      phase: phase,
      title: render["title"] as? String ?? "MyCHU",
      body: render["body"] as? String ?? "",
      shortCriticalText: render["shortCriticalText"] as? String,
      progress: render["progress"] as? Int ?? 0,
      progressMax: render["progressMax"] as? Int ?? 0,
      startAt: date(render["startAt"]),
      endAt: date(render["endAt"]),
      targetAppId: targetAppId
    )
  }

  private func date(_ value: Any?) -> Date? {
    guard let value = value as? String else { return nil }
    return ISO8601DateFormatter().date(from: value)
  }
}
