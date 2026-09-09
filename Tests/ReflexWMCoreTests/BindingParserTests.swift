import Carbon
import XCTest

@testable import ReflexWMCore

final class BindingParserTests: XCTestCase {
  func testParsesAndNormalizesBinding() throws {
    let result = try BindingParser.parse(" CTRL + Cmd + D ")
    guard case .binding(let binding) = result else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(binding.normalized, "cmd+ctrl+d")
    XCTAssertEqual(binding.keyCode, UInt32(kVK_ANSI_D))
    XCTAssertEqual(binding.modifiers, UInt32(cmdKey | controlKey))
  }

  func testPrintScreenMapsToF13() throws {
    guard case .binding(let binding) = try BindingParser.parse("PrintScr") else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(binding.keyCode, UInt32(kVK_F13))
  }

  func testMultiwordKeyAlias() throws {
    guard case .binding(let binding) = try BindingParser.parse("cmd + Page Up") else {
      return XCTFail("expected binding")
    }
    XCTAssertEqual(binding.keyCode, UInt32(kVK_PageUp))
  }

  func testUnshiftedPunctuationKeys() throws {
    let expected: [(String, UInt32)] = [
      ("`", UInt32(kVK_ANSI_Grave)),
      ("-", UInt32(kVK_ANSI_Minus)),
      ("=", UInt32(kVK_ANSI_Equal)),
      ("[", UInt32(kVK_ANSI_LeftBracket)),
      ("]", UInt32(kVK_ANSI_RightBracket)),
      ("\\", UInt32(kVK_ANSI_Backslash)),
      (";", UInt32(kVK_ANSI_Semicolon)),
      ("'", UInt32(kVK_ANSI_Quote)),
      (",", UInt32(kVK_ANSI_Comma)),
      (".", UInt32(kVK_ANSI_Period)),
      ("/", UInt32(kVK_ANSI_Slash)),
    ]

    for (key, keyCode) in expected {
      guard case .binding(let binding) = try BindingParser.parse("cmd + \(key)") else {
        return XCTFail("expected binding for \(key)")
      }
      XCTAssertEqual(binding.keyCode, keyCode, key)
      XCTAssertEqual(binding.normalized, "cmd+\(key)", key)
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
    XCTAssertEqual(hyper.modifiers, UInt32(cmdKey | controlKey | shiftKey | optionKey))

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
}
