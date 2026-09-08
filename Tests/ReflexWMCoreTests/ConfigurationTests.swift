import XCTest

@testable import ReflexWMCore

final class ConfigurationTests: XCTestCase {
  func testDecodesDocumentedConfiguration() throws {
    let configuration = try ConfigurationLoader.decode(
      """
      [[shortcut]]
      bind = "cmd + ctrl + e"
      action = "toggle-app"
      launch_cmd = "kitty"
      match = [
        { app_id = "net.kovidgoyal.kitty", win_title = "shell" },
        { app_name = "kitty" }
      ]

      [[shortcut]]
      bind = "cmd + ctrl + i"
      action = "notify-win-info"
      """
    )
    XCTAssertEqual(configuration.shortcuts.count, 2)
    XCTAssertEqual(configuration.shortcuts[0].match?.count, 2)
    XCTAssertEqual(configuration.shortcuts[1].action, .notifyWindowInfo)
  }

  func testEmptyDocumentHasNoShortcuts() throws {
    XCTAssertEqual(try ConfigurationLoader.decode("").shortcuts, [])
  }

  func testValidationFiltersEmptyMatchesAndDisablesEmptyBind() throws {
    let source = Shortcut(
      bind: "",
      action: .toggleApp,
      launchCommand: "kitty",
      match: [MatchCondition(), MatchCondition(appName: "kitty")]
    )
    let validated = try ConfigurationValidator.validate(Configuration(shortcuts: [source]))
    XCTAssertNil(validated[0].binding)
    XCTAssertEqual(validated[0].effectiveMatches, [MatchCondition(appName: "kitty")])
  }

  func testToggleAppRequiresMatch() {
    let source = Shortcut(bind: "cmd+e", action: .toggleApp)
    XCTAssertThrowsError(
      try ConfigurationValidator.validate(Configuration(shortcuts: [source]))
    )
  }

  func testNonToggleActionRejectsAppFields() {
    let source = Shortcut(
      bind: "cmd+i",
      action: .notifyWindowInfo,
      launchCommand: "ignored"
    )
    XCTAssertThrowsError(
      try ConfigurationValidator.validate(Configuration(shortcuts: [source]))
    )
  }

  func testDuplicateNormalizedBindingsAreRejected() {
    let configuration = Configuration(shortcuts: [
      Shortcut(bind: "cmd + ctrl + d", action: .close),
      Shortcut(bind: "CTRL+CMD+D", action: .toggleMaximize),
    ])
    XCTAssertThrowsError(try ConfigurationValidator.validate(configuration))
  }
}
