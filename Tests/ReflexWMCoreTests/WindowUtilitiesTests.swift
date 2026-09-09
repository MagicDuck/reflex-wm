import XCTest

@testable import ReflexWMCore

final class WindowUtilitiesTests: XCTestCase {
  func testOrderedMatchStopsAtFirstSuccessfulCondition() {
    let candidates = [
      WindowMetadata(appID: "first", appName: "Editor", executableName: "editor", windowTitle: "A"),
      WindowMetadata(
        appID: "second", appName: "Terminal", executableName: "term", windowTitle: "B"),
      WindowMetadata(
        appID: "second", appName: "Terminal", executableName: "term", windowTitle: "C"),
    ]
    let indexes = MatchResolver.firstMatchingIndexes(
      conditions: [
        MatchCondition(),
        MatchCondition(appID: "missing"),
        MatchCondition(appID: "second", appName: "terminal"),
        MatchCondition(appID: "first"),
      ],
      candidates: candidates
    )
    XCTAssertEqual(indexes, [1, 2])
  }

  func testMapsProportionalFrameAcrossScreensAndClamps() {
    let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let destination = CGRect(x: -2000, y: 100, width: 2000, height: 1000)
    XCTAssertEqual(
      ScreenGeometry.map(
        CGRect(x: 250, y: 200, width: 500, height: 400),
        from: source,
        to: destination
      ),
      CGRect(x: -1500, y: 350, width: 1000, height: 500)
    )
    XCTAssertEqual(
      ScreenGeometry.map(
        CGRect(x: -100, y: -100, width: 1200, height: 1000),
        from: source,
        to: destination
      ),
      destination
    )
  }

  func testFullScreenFrameFillsLargerDestinationScreen() {
    let source = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let destination = CGRect(x: 1440, y: 0, width: 2560, height: 1415)

    XCTAssertEqual(
      ScreenGeometry.map(source, from: source, to: destination),
      destination
    )
  }

  func testWindowInfoFormattingIncludesUnavailableFields() {
    let body = WindowInfoFormatter.body(
      for: WindowMetadata(
        appID: nil,
        appName: "Kitty",
        executableName: "kitty",
        windowTitle: nil
      )
    )
    XCTAssertEqual(
      body,
      """
      Bundle ID: <unavailable>
      Application: Kitty
      Executable: kitty
      Window Title: <unavailable>
      """
    )
  }
}
