import Foundation

guard CommandLine.arguments.count == 4 else {
  fatalError("Usage: EmbedKWinScripts MAIN_QML WINDOWS_JS OUTPUT_SWIFT")
}
let inputs = CommandLine.arguments.dropFirst().prefix(2).map { URL(fileURLWithPath: $0) }
let names = ["mainQML", "windowsJS"]
let constants = try zip(names, inputs).map { name, input in
  let encoded = try Data(contentsOf: input).base64EncodedString()
  return "  static let \(name) = Data(base64Encoded: \"\(encoded)\")!"
}
let source = """
  // Generated from Resources/kwin by EmbedKWinScriptsPlugin. Do not edit.
  import Foundation

  enum EmbeddedKWinScripts {
  \(constants.joined(separator: "\n"))
  }

  """
let output = URL(fileURLWithPath: CommandLine.arguments[3])
try FileManager.default.createDirectory(
  at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data(source.utf8).write(to: output, options: .atomic)
