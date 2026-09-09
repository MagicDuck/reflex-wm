import XCTest

@testable import ReflexWMCore

final class MatchConditionTests: XCTestCase {
  private let candidate = WindowMetadata(
    appID: "net.kovidgoyal.kitty",
    appName: "kitty",
    executableName: "kitty-bin",
    windowTitle: "Shell"
  )

  func testAllSpecifiedFieldsUseAndSemantics() {
    XCTAssertTrue(
      MatchCondition(
        appID: "net.kovidgoyal.kitty",
        appName: "KITTY",
        windowTitle: "shell"
      ).matches(candidate)
    )
    XCTAssertFalse(
      MatchCondition(
        appID: "wrong.bundle",
        appName: "kitty",
        windowTitle: "shell"
      ).matches(candidate)
    )
  }

  func testAppNameCanMatchExecutableBasename() {
    XCTAssertTrue(MatchCondition(appName: "KITTY-BIN").matches(candidate))
  }

  func testMissingCandidateValueDoesNotMatch() {
    let missingTitle = WindowMetadata(
      appID: candidate.appID,
      appName: candidate.appName,
      executableName: candidate.executableName,
      windowTitle: nil
    )
    XCTAssertFalse(MatchCondition(windowTitle: "shell").matches(missingTitle))
  }

  func testApplicationPrefilterIgnoresWindowTitle() {
    let condition = MatchCondition(
      appID: "net.kovidgoyal.kitty",
      appName: "KITTY-BIN",
      windowTitle: "different window"
    )
    XCTAssertTrue(condition.matchesApplication(candidate))
    XCTAssertFalse(condition.matches(candidate))
  }

  func testApplicationPrefilterRejectsWrongApplication() {
    XCTAssertFalse(MatchCondition(appID: "wrong.bundle").matchesApplication(candidate))
    XCTAssertFalse(MatchCondition(appName: "Safari").matchesApplication(candidate))
  }
}
