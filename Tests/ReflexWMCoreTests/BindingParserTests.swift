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

  func testEmptyBindingIsDisabled() throws {
    XCTAssertEqual(try BindingParser.parse("  \n"), .disabled)
  }

  func testRejectsInvalidBindings() {
    for value in ["cmd+cmd+d", "cmd+ctrl", "cmd+d+e", "cmd++d", "hyper+d", "d+cmd"] {
      XCTAssertThrowsError(try BindingParser.parse(value), value)
    }
  }
}
