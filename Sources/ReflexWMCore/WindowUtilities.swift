import Foundation

public enum MatchResolver {
  public static func firstMatchingIndexes(
    conditions: [MatchCondition],
    candidates: [WindowMetadata]
  ) -> [Int] {
    for condition in conditions where !condition.isEmpty {
      let indexes = candidates.indices.filter { condition.matches(candidates[$0]) }
      if !indexes.isEmpty {
        return indexes
      }
    }
    return []
  }
}

public enum ScreenGeometry {
  public static func map(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
    let normalizedX = source.width == 0 ? 0 : (frame.minX - source.minX) / source.width
    let normalizedY = source.height == 0 ? 0 : (frame.minY - source.minY) / source.height
    let normalizedWidth = source.width == 0 ? 1 : frame.width / source.width
    let normalizedHeight = source.height == 0 ? 1 : frame.height / source.height
    var mapped = CGRect(
      x: destination.minX + normalizedX * destination.width,
      y: destination.minY + normalizedY * destination.height,
      width: min(normalizedWidth * destination.width, destination.width),
      height: min(normalizedHeight * destination.height, destination.height)
    )
    mapped.origin.x = min(max(mapped.minX, destination.minX), destination.maxX - mapped.width)
    mapped.origin.y = min(max(mapped.minY, destination.minY), destination.maxY - mapped.height)
    return mapped
  }

  public static func verticalHalf(_ screen: CGRect, side: VerticalSplitSide) -> CGRect {
    let leftWidth = floor(screen.width / 2)
    switch side {
    case .left:
      return CGRect(
        x: screen.minX,
        y: screen.minY,
        width: leftWidth,
        height: screen.height
      )
    case .right:
      return CGRect(
        x: screen.minX + leftWidth,
        y: screen.minY,
        width: screen.width - leftWidth,
        height: screen.height
      )
    }
  }
}

public enum VerticalSplitSide: Sendable {
  case left
  case right

  public var opposite: Self {
    switch self {
    case .left: .right
    case .right: .left
    }
  }
}

public enum WindowInfoFormatter {
  public static func body(for metadata: WindowMetadata) -> String {
    let unavailable = "<unavailable>"
    return [
      "Bundle ID: \(metadata.appID ?? unavailable)",
      "Application: \(metadata.appName ?? unavailable)",
      "Executable: \(metadata.executableName ?? unavailable)",
      "Window Title: \(metadata.windowTitle ?? unavailable)",
    ].joined(separator: "\n")
  }
}
