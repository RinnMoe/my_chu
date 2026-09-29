import Flutter
import UIKit

struct AppleWindowControlsMetrics: Equatable {
  /// Required directional insets measured from the owning view's edges to the
  /// corner-adapted layout region. These are absolute positions, not deltas
  /// from UIKit's ordinary layout margins.
  let leading: CGFloat
  let trailing: CGFloat

  static let zero = AppleWindowControlsMetrics(leading: 0, trailing: 0)

  var payload: [String: Double] {
    [
      "leading": Double(leading),
      "trailing": Double(trailing),
    ]
  }
}

struct AppleWindowControlsMetricsCalculator {
  static func metrics(
    adaptedFrame: CGRect,
    baselineFrame: CGRect,
    containerFrame: CGRect,
    direction: UIUserInterfaceLayoutDirection
  ) -> AppleWindowControlsMetrics {
    let requiresLeftAvoidance = adaptedFrame.minX > baselineFrame.minX
    let requiresRightAvoidance = adaptedFrame.maxX < baselineFrame.maxX
    let requiredLeft =
      requiresLeftAvoidance
        ? max(0, adaptedFrame.minX - containerFrame.minX)
        : 0
    let requiredRight =
      requiresRightAvoidance
        ? max(0, containerFrame.maxX - adaptedFrame.maxX)
        : 0

    switch direction {
    case .rightToLeft:
      return AppleWindowControlsMetrics(
        leading: requiredRight,
        trailing: requiredLeft
      )
    case .leftToRight:
      return AppleWindowControlsMetrics(
        leading: requiredLeft,
        trailing: requiredRight
      )
    @unknown default:
      return AppleWindowControlsMetrics(
        leading: requiredLeft,
        trailing: requiredRight
      )
    }
  }
}

struct AppleWindowControlsMetricsState {
  private(set) var metrics = AppleWindowControlsMetrics.zero

  mutating func update(_ nextMetrics: AppleWindowControlsMetrics) -> Bool {
    guard nextMetrics != metrics else { return false }
    metrics = nextMetrics
    return true
  }
}

private final class AppleWindowControlsStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var latestMetrics = AppleWindowControlsMetrics.zero

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    events(latestMetrics.payload)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func update(_ metrics: AppleWindowControlsMetrics) {
    latestMetrics = metrics
    eventSink?(metrics.payload)
  }
}

final class WindowControlsFlutterViewController: FlutterViewController {
  private static let channelName = "mychu/apple_window_controls"

  private let streamHandler = AppleWindowControlsStreamHandler()
  private var publishedMetrics = AppleWindowControlsMetricsState()
  private var adaptedMarginsGuide: UILayoutGuide?

  override func viewDidLoad() {
    super.viewDidLoad()

    let channel = FlutterEventChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setStreamHandler(streamHandler)
    refreshWindowControlsMetrics()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    refreshWindowControlsMetrics()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    refreshWindowControlsMetrics()
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    refreshWindowControlsMetrics()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    refreshWindowControlsMetrics()
  }

  private func refreshWindowControlsMetrics() {
    guard #available(iOS 26.0, *) else {
      publishIfChanged(.zero)
      return
    }

    guard view.bounds.width > 0, view.bounds.height > 0 else {
      publishIfChanged(.zero)
      return
    }

    if adaptedMarginsGuide == nil {
      adaptedMarginsGuide = view.layoutGuide(
        for: .margins(cornerAdaptation: .horizontal)
      )
    }

    guard let adaptedMarginsGuide else {
      publishIfChanged(.zero)
      return
    }

    let metrics = AppleWindowControlsMetricsCalculator.metrics(
      adaptedFrame: adaptedMarginsGuide.layoutFrame,
      baselineFrame: view.layoutMarginsGuide.layoutFrame,
      containerFrame: view.bounds,
      direction: view.effectiveUserInterfaceLayoutDirection
    )
    publishIfChanged(metrics)
  }

  private func publishIfChanged(_ metrics: AppleWindowControlsMetrics) {
    guard publishedMetrics.update(metrics) else { return }
    streamHandler.update(metrics)
  }
}
