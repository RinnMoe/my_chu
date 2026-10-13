import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    if info["source"] as? String == "timeReminder" {
      var payload: [String: Any] = [:]
      for (key, value) in info { if let key = key as? String { payload[key] = value } }
      MyCHUAppLaunchPlugin.receive(payload: payload)
      completionHandler()
    } else { super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler) }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if notification.request.content.userInfo["source"] as? String == "timeReminder" {
      completionHandler([.banner, .list, .sound])
    } else { super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Flutter plugins are registered through the generated registrant.
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let scheduledRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "MyCHUTimeReminderPlugin"
    ) {
      MyCHUTimeReminderPlugin.register(with: scheduledRegistrar)
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

/// Delivers typed reminder launches and app URLs to the host coordinator.
/// Dart validates ownership, consent, authentication and AppRegistry targets.
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

  static func receive(payload: [String: Any]) {
    pendingLaunch = payload
    channel?.invokeMethod("launch", arguments: payload)
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
