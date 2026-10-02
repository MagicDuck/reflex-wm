import Foundation
import PackagePlugin

@main
struct EmbedKWinScriptsPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
    let resources = context.package.directoryURL.appendingPathComponent("Resources/kwin")
    let inputs = ["main.qml", "windows.js"].map { resources.appendingPathComponent($0) }
    let output = context.pluginWorkDirectoryURL.appendingPathComponent("EmbeddedKWinScripts.swift")
    return [
      .buildCommand(
        displayName: "Embed KWin scripts in reflex-wm-kde",
        executable: try context.tool(named: "EmbedKWinScripts").url,
        arguments: inputs.map(\.path) + [output.path],
        inputFiles: inputs, outputFiles: [output])
    ]
  }
}
