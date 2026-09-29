import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testWindowControlsMetricsCalculatorUsesHorizontalMarginsOnly() {
    let container = CGRect(x: 0, y: 0, width: 400, height: 100)
    let baseline = CGRect(x: 20, y: 0, width: 360, height: 100)
    let adapted = CGRect(x: 80, y: 32, width: 260, height: 36)

    let leftToRight = AppleWindowControlsMetricsCalculator.metrics(
      adaptedFrame: adapted,
      baselineFrame: baseline,
      containerFrame: container,
      direction: .leftToRight
    )
    XCTAssertEqual(leftToRight.leading, 80)
    XCTAssertEqual(leftToRight.trailing, 60)

    let rightToLeft = AppleWindowControlsMetricsCalculator.metrics(
      adaptedFrame: adapted,
      baselineFrame: baseline,
      containerFrame: container,
      direction: .rightToLeft
    )
    XCTAssertEqual(rightToLeft.leading, 60)
    XCTAssertEqual(rightToLeft.trailing, 80)
  }

  func testWindowControlsMetricsCalculatorReturnsZeroWithoutAdaptation() {
    let container = CGRect(x: 0, y: 0, width: 400, height: 100)
    let baseline = CGRect(x: 20, y: 0, width: 360, height: 100)

    let metrics = AppleWindowControlsMetricsCalculator.metrics(
      adaptedFrame: baseline,
      baselineFrame: baseline,
      containerFrame: container,
      direction: .leftToRight
    )

    XCTAssertEqual(metrics, .zero)
  }

  func testWindowControlsMetricsCalculatorClampsToZero() {
    let frame = CGRect(x: 0, y: 0, width: 400, height: 100)
    let metrics = AppleWindowControlsMetricsCalculator.metrics(
      adaptedFrame: frame.insetBy(dx: -12, dy: -8),
      baselineFrame: frame,
      containerFrame: frame,
      direction: .leftToRight
    )
    XCTAssertEqual(metrics, .zero)
  }

  func testWindowControlsMetricsStateSuppressesRepeatedValues() {
    var state = AppleWindowControlsMetricsState()
    let metrics = AppleWindowControlsMetrics(leading: 20, trailing: 8)

    XCTAssertFalse(state.update(.zero))
    XCTAssertTrue(state.update(metrics))
    XCTAssertFalse(state.update(metrics))
    XCTAssertEqual(state.metrics, metrics)
  }

  func testWindowControlsControllerDoesNotAddSafeAreaInsets() throws {
    let storyboard = UIStoryboard(
      name: "Main",
      bundle: Bundle(for: WindowControlsFlutterViewController.self)
    )
    let controller = try XCTUnwrap(
      storyboard.instantiateInitialViewController()
        as? WindowControlsFlutterViewController
    )

    XCTAssertEqual(controller.additionalSafeAreaInsets, .zero)
  }

  @available(iOS 26.0, *)
  func testSceneDelegateExposesWindowingControlStyleSelector() {
    let delegate = SceneDelegate()
    let selector = NSSelectorFromString(
      "preferredWindowingControlStyleForScene:"
    )

    XCTAssertTrue(delegate.responds(to: selector))
  }

}
