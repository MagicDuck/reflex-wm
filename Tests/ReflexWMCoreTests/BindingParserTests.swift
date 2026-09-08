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

  func testEmptyBindingIsDisabled() throws {
    XCTAssertEqual(try BindingParser.parse("  \n"), .disabled)
  }

  func testRejectsInvalidBindings() {
    for value in ["cmd+cmd+d", "cmd+ctrl", "cmd+d+e", "cmd++d", "hyper+d", "d+cmd"] {
      XCTAssertThrowsError(try BindingParser.parse(value), value)
    }
  }
}
