import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Flutter plugins are registered through the generated registrant.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let scheduledRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "MyCHUScheduledAlertPlugin"
    ) {
      MyCHUScheduledAlertPlugin.register(with: scheduledRegistrar)
    }
    if let liveActivityRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "MyCHUSystemLiveActivityPlugin"
    ) {
      MyCHUSystemLiveActivityPlugin.register(with: liveActivityRegistrar)
    }
    if let appLaunchRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "MyCHUAppLaunchPlugin"
    ) {
      MyCHUAppLaunchPlugin.register(with: appLaunchRegistrar)
    }
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MyCHUFileSavePlugin") else {
      return
    }
    MyCHUFileSavePlugin.register(with: registrar)
  }
}

/// Delivers Live Activity URL actions to the host-owned launch coordinator.
/// Only the target app ID crosses this bridge; the Dart side still validates
/// it against AppRegistry.
final class MyCHUAppLaunchPlugin: NSObject, FlutterPlugin {
  private static let channelName = "mychu/app_launch"
  private static var channel: FlutterMethodChannel?
  private static var pendingLaunch: [String: Any]?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MyCHUAppLaunchPlugin()
    let methodChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    channel = methodChannel
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    if let pendingLaunch {
      DispatchQueue.main.async {
        methodChannel.invokeMethod("launch", arguments: pendingLaunch)
      }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "consume" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let pending = Self.pendingLaunch
    Self.pendingLaunch = nil
    result(pending)
  }

  static func receive(url: URL) {
    guard url.scheme?.lowercased() == "mychu" else { return }
    guard url.host?.lowercased() == "app" else { return }
    let targetAppId = url.pathComponents.dropFirst().joined(separator: "/")
    guard !targetAppId.isEmpty else { return }

    let payload: [String: Any] = [
      "action": "open",
      "targetAppId": targetAppId,
    ]
    pendingLaunch = payload
    channel?.invokeMethod("launch", arguments: payload)
  }
}

/// Apple adapter for the shared ScheduledAlertDraft contract.
///
/// The Flutter host remains the owner of account scoping and alert policy.
/// This adapter only translates bounded future payloads into UNUserNotification
/// requests; it never performs network access or authentication.
private final class MyCHUScheduledAlertPlugin: NSObject, FlutterPlugin {
  private static let channelName = "mychu/scheduled_alerts"
  private static let idsKey = "mychu.scheduled_alert_ids.v1"

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MyCHUScheduledAlertPlugin()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "replace":
      replace(call, result: result)
    case "clearProvider":
      let arguments = call.arguments as? [String: Any]
      clearProvider(
        accountKey: arguments?["accountKey"] as? String,
        providerId: arguments?["providerId"] as? String
      )
      result(nil)
    case "clearAll":
      clearAll()
      result(nil)
    case "reschedule":
      // iOS persists pending requests across process restarts. The Flutter
      // policy layer still calls this method after a settings change; there is
      // no Android-style alarm reschedule operation to repeat here.
      result(nil)
    case "consumeReceipts":
      result([])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func replace(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let accountKey = arguments["accountKey"] as? String,
      let providerId = arguments["providerId"] as? String,
      !accountKey.isEmpty,
      !providerId.isEmpty,
      let rawAlerts = arguments["alerts"] as? String,
      let data = rawAlerts.data(using: .utf8),
      let alerts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      result(FlutterError(
        code: "INVALID_PAYLOAD",
        message: "scheduled alert payload is invalid",
        details: nil
      ))
      return
    }

    let key = storageKey(accountKey: accountKey, providerId: providerId)
    let defaults = UserDefaults.standard
    let oldIds = defaults.stringArray(forKey: key) ?? []
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: oldIds)

    let now = Date()
    var newIds: [String] = []
    for alert in alerts {
      guard
        let eventId = alert["eventId"] as? String,
        let title = alert["title"] as? String,
        let triggerMilliseconds = alert["triggerAt"] as? NSNumber,
        let validUntilMilliseconds = alert["validUntil"] as? NSNumber
      else { continue }
      let triggerDate = Date(timeIntervalSince1970: triggerMilliseconds.doubleValue / 1000)
      let validUntil = Date(timeIntervalSince1970: validUntilMilliseconds.doubleValue / 1000)
      guard triggerDate > now, triggerDate <= validUntil else { continue }

      let identifier = requestIdentifier(
        accountKey: accountKey,
        providerId: providerId,
        eventId: eventId
      )
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = alert["body"] as? String ?? ""
      content.sound = .default
      if let targetAppId = alert["targetAppId"] as? String {
        content.userInfo = ["targetAppId": targetAppId]
      }
      let interval = max(1, triggerDate.timeIntervalSinceNow)
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
      )
      newIds.append(identifier)
    }

    defaults.set(newIds, forKey: key)
    var allIds = defaults.stringArray(forKey: Self.idsKey) ?? []
    allIds.removeAll { oldIds.contains($0) }
    allIds.append(contentsOf: newIds)
    defaults.set(Array(Set(allIds)), forKey: Self.idsKey)
    result(nil)
  }

  private func clearProvider(accountKey: String?, providerId: String?) {
    guard
      let accountKey,
      let providerId,
      !accountKey.isEmpty,
      !providerId.isEmpty
    else { return }
    let defaults = UserDefaults.standard
    let key = storageKey(accountKey: accountKey, providerId: providerId)
    let ids = defaults.stringArray(forKey: key) ?? []
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    defaults.removeObject(forKey: key)
    var allIds = defaults.stringArray(forKey: Self.idsKey) ?? []
    allIds.removeAll { ids.contains($0) }
    defaults.set(allIds, forKey: Self.idsKey)
  }

  private func clearAll() {
    let defaults = UserDefaults.standard
    let ids = defaults.stringArray(forKey: Self.idsKey) ?? []
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("mychu.scheduled.ids.") {
      defaults.removeObject(forKey: key)
    }
    defaults.removeObject(forKey: Self.idsKey)
  }

  private func storageKey(accountKey: String, providerId: String) -> String {
    "mychu.scheduled.ids.\(safeToken(accountKey)).\(safeToken(providerId))"
  }

  private func requestIdentifier(accountKey: String, providerId: String, eventId: String) -> String {
    "mychu.alert.\(safeToken(accountKey)).\(safeToken(providerId)).\(safeToken(eventId))"
  }

  private func safeToken(_ value: String) -> String {
    Data(value.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

/// Native file chooser/share bridge used by schedule exports on Apple.
///
/// The Dart service keeps the file lifecycle and feature semantics shared
/// across platforms. UIKit owns only the final presentation step here.
private final class MyCHUFileSavePlugin: NSObject, FlutterPlugin, UIDocumentInteractionControllerDelegate {
  private var documentController: UIDocumentInteractionController?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MyCHUFileSavePlugin()
    let channel = FlutterMethodChannel(
      name: "mychu/file_save",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      !path.isEmpty
    else {
      result(false)
      return
    }

    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(false)
      return
    }

    switch call.method {
    case "openFile":
      openFile(fileURL, result: result)
    case "shareFile":
      shareFile(fileURL, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openFile(_ fileURL: URL, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let presenter = Self.topViewController() else {
        result(false)
        return
      }
      let controller = UIDocumentInteractionController(url: fileURL)
      controller.delegate = self
      self.documentController = controller
      let presented = controller.presentOptionsMenu(
        from: presenter.view.bounds,
        in: presenter.view,
        animated: true
      )
      result(presented)
    }
  }

  private func shareFile(_ fileURL: URL, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let presenter = Self.topViewController() else {
        result(false)
        return
      }
      let controller = UIActivityViewController(
        activityItems: [fileURL],
        applicationActivities: nil
      )
      if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = presenter.view.bounds
        popover.permittedArrowDirections = []
      }
      presenter.present(controller, animated: true) {
        result(true)
      }
    }
  }

  private static func topViewController(
    from root: UIViewController? = nil
  ) -> UIViewController? {
    let rootController = root ?? activeRootViewController()
    if let presented = rootController?.presentedViewController {
      return topViewController(from: presented)
    }
    if let navigation = rootController as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tab = rootController as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    return rootController
  }

  private static func activeRootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
    let window = scenes
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })
      ?? scenes.flatMap { $0.windows }.first(where: { $0.rootViewController != nil })
    return window?.rootViewController
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    return Self.topViewController() ?? UIViewController()
  }
}
