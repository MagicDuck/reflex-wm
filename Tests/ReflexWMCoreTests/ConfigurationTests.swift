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
      bind = "cmd + ctrl + s"
      action = "toggle-app"
      launch_app = "Safari"
      match = [{ app_name = "Safari" }]

      [[shortcut]]
      bind = "cmd + ctrl + i"
      action = "notify-win-info"

      [[shortcut]]
      bind = "cmd + ctrl + j"
      action = "focus-next-app-window"

      [[shortcut]]
      bind = "cmd + ctrl + v"
      action = "toggle-vertical-split"
      """
    )
    XCTAssertEqual(configuration.shortcuts.count, 5)
    XCTAssertEqual(configuration.shortcuts[0].match?.count, 2)
    XCTAssertEqual(configuration.shortcuts[1].launchApplication, "Safari")
    XCTAssertEqual(configuration.shortcuts[2].action, .notifyWindowInfo)
    XCTAssertEqual(configuration.shortcuts[3].action, .focusNextAppWindow)
    XCTAssertEqual(configuration.shortcuts[4].action, .toggleVerticalSplit)
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

  func testNonToggleActionRejectsLaunchApp() {
    let source = Shortcut(
      bind: "cmd+i",
      action: .notifyWindowInfo,
      launchApplication: "Safari"
    )
    XCTAssertThrowsError(
      try ConfigurationValidator.validate(Configuration(shortcuts: [source]))
    )
  }

  func testToggleAppRejectsMultipleLaunchMethods() {
    let source = Shortcut(
      bind: "cmd+s",
      action: .toggleApp,
      launchCommand: "open -a Safari",
      launchApplication: "Safari",
      match: [MatchCondition(appName: "Safari")]
    )
    XCTAssertThrowsError(
      try ConfigurationValidator.validate(Configuration(shortcuts: [source]))
    ) { error in
      XCTAssertEqual(
        error as? ValidationError,
        ValidationError("shortcut 1: launch_cmd and launch_app are mutually exclusive")
      )
    }
  }

  func testToggleAppAcceptsLaunchApp() throws {
    let source = Shortcut(
      bind: "cmd+s",
      action: .toggleApp,
      launchApplication: "Safari",
      match: [MatchCondition(appName: "Safari")]
    )
    let validated = try ConfigurationValidator.validate(Configuration(shortcuts: [source]))
    XCTAssertEqual(validated[0].source.launchApplication, "Safari")
  }

  func testDuplicateNormalizedBindingsAreRejected() {
    let configuration = Configuration(shortcuts: [
      Shortcut(bind: "cmd + ctrl + d", action: .close),
      Shortcut(bind: "CTRL+CMD+D", action: .toggleMaximize),
    ])
    XCTAssertThrowsError(try ConfigurationValidator.validate(configuration))
  }
}
