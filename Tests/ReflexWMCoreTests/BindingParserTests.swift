import XCTest

@testable import ReflexWMCore

#if os(macOS)
  import Carbon
  import ReflexWMMacSupport
#endif

final class BindingParserTests: XCTestCase {
  func testParsesAndNormalizesBinding() throws {
    let result = try BindingParser.parse(" CTRL + Cmd + D ")
    guard case .binding(let binding) = result else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(binding.normalized, "cmd+ctrl+d")
    XCTAssertEqual(binding.key, "d")
    XCTAssertEqual(binding.modifiers, [.command, .control])
  }

  func testPrintScreenRemainsLogical() throws {
    guard case .binding(let binding) = try BindingParser.parse("PrintScr") else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(binding.key, "printscr")
  }

  func testMultiwordKeyAlias() throws {
    guard case .binding(let binding) = try BindingParser.parse("cmd + Page Up") else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(binding.key, "pageup")
  }

  func testUnshiftedPunctuationKeys() throws {
    for key in Array("`-=[]\\;'.,/").map(String.init) {
      guard case .binding(let binding) = try BindingParser.parse("cmd + \(key)") else {
        return XCTFail("expected binding")
      }
      XCTAssertEqual(binding.key, key)
      XCTAssertEqual(binding.normalized, "cmd+\(key)")
    }
  }

  func testPunctuationAliasesNormalizeToSymbols() throws {
    let aliases = [
      "semicolon": ";",
      "dot": ".",
      "period": ".",
      "slash": "/",
      "forward slash": "/",
    ]

    for (alias, symbol) in aliases {
      guard case .binding(let binding) = try BindingParser.parse("ctrl + \(alias)") else {
        return XCTFail("expected binding for \(alias)")
      }
      XCTAssertEqual(binding.normalized, "ctrl+\(symbol)", alias)
    }
  }

  func testBuiltinAliases() throws {
    guard case .binding(let hyper) = try BindingParser.parse("hyper + j") else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(hyper.normalized, "cmd+ctrl+shift+opt+j")
    XCTAssertEqual(hyper.modifiers, [.command, .control, .shift, .option])

    guard case .binding(let aliases) = try BindingParser.parse("super + alt + j") else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(aliases.normalized, "cmd+opt+j")
  }

  func testConfiguredAndNestedAliases() throws {
    let aliases = [
      "meh": "ctrl + shift + alt",
      "window": "meh + super",
    ]
    guard case .binding(let binding) = try BindingParser.parse("WINDOW + J", aliases: aliases)
    else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(binding.normalized, "cmd+ctrl+shift+opt+j")
  }

  func testRejectsInvalidAliasDefinitions() {
    XCTAssertThrowsError(
      try BindingParser.validateAliases(["first": "second", "second": "first"])
    )
    XCTAssertThrowsError(try BindingParser.validateAliases(["hyper": "cmd"]))
    XCTAssertThrowsError(try BindingParser.validateAliases(["cmd": "ctrl"]))
    XCTAssertThrowsError(try BindingParser.validateAliases(["meh": "ctrl+ctrl"]))
    XCTAssertThrowsError(try BindingParser.validateAliases(["meh": "mystery"]))
  }

  func testEmptyBindingIsDisabled() throws {
    XCTAssertEqual(try BindingParser.parse("  \n"), .disabled)
  }

  func testRejectsInvalidBindings() {
    for value in ["cmd+cmd+d", "cmd+ctrl", "cmd+d+e", "cmd++d", "d+cmd"] {
      XCTAssertThrowsError(try BindingParser.parse(value), value)
    }
  }

  func testParsesModifierExpressionsWithAliases() throws {
    let modifiers = try BindingParser.parseModifiers(
      "meh + super",
      aliases: ["meh": "ctrl+shift+alt"]
    )
    XCTAssertEqual(modifiers.normalized, "cmd+ctrl+shift+opt")
    XCTAssertEqual(modifiers.modifiers, [.command, .control, .shift, .option])
  }

  #if os(macOS)
    func testCarbonTranslationPreservesExistingCodes() throws {
      for (key, code) in [("d", kVK_ANSI_D), ("printscr", kVK_F13), ("pageup", kVK_PageUp)] {
        guard case .binding(let binding) = try BindingParser.parse("hyper+\(key)") else {
          return XCTFail("expected binding")
        }
        XCTAssertEqual(binding.carbonKeyCode, UInt32(code))
        XCTAssertEqual(
          binding.modifiers.carbonModifiers, UInt32(cmdKey | controlKey | shiftKey | optionKey))
      }
    }
  #endif

  func testRejectsInvalidModifierExpressions() {
    for value in ["", "hyper+e", "cmd+cmd", "cmd++ctrl"] {
      XCTAssertThrowsError(try BindingParser.parseModifiers(value), value)
    }
  }
}
