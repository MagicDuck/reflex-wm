import Foundation

struct IconEntry {
  let type: String
  let filename: String
}

let entries = [
  IconEntry(type: "icp4", filename: "icon_16x16.png"),
  IconEntry(type: "icp5", filename: "icon_32x32.png"),
  IconEntry(type: "icp6", filename: "icon_32x32@2x.png"),
  IconEntry(type: "ic07", filename: "icon_128x128.png"),
  IconEntry(type: "ic08", filename: "icon_256x256.png"),
  IconEntry(type: "ic09", filename: "icon_512x512.png"),
  IconEntry(type: "ic10", filename: "icon_512x512@2x.png"),
]

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(
    Data("usage: make-icns.swift <input.iconset> <output.icns>\n".utf8)
  )
  exit(2)
}

let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
var body = Data()

func appendBigEndian(_ value: UInt32, to data: inout Data) {
  var encoded = value.bigEndian
  withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

for entry in entries {
  guard let typeData = entry.type.data(using: .ascii), typeData.count == 4 else {
    fatalError("invalid ICNS entry type: \(entry.type)")
  }
  let imageData = try Data(contentsOf: inputDirectory.appendingPathComponent(entry.filename))
  body.append(typeData)
  appendBigEndian(UInt32(imageData.count + 8), to: &body)
  body.append(imageData)
}

var output = Data("icns".utf8)
appendBigEndian(UInt32(body.count + 8), to: &output)
output.append(body)
try output.write(to: outputURL, options: .atomic)
