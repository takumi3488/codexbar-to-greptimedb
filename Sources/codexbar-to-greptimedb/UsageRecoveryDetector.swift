import Foundation

struct UsageWindowKey: Hashable, Sendable {
  let provider: String
  let source: String
  let accountKey: String
  let window: String
}

struct RecoveredUsageWindow: Sendable, Equatable {
  let key: UsageWindowKey
  let previousPercent: Double
  let currentPercent: Double
}

enum UsageRecoveryDetector {
  static func usagePercents(in snapshots: [ExportSnapshot]) -> [UsageWindowKey: Double] {
    var result: [UsageWindowKey: Double] = [:]
    for snapshot in snapshots {
      for window in snapshot.windows {
        guard let usedPercent = window.usedPercent else {
          continue
        }
        result[
          UsageWindowKey(
            provider: snapshot.provider,
            source: snapshot.source,
            accountKey: snapshot.accountKey,
            window: window.name
          )
        ] = usedPercent
      }
    }
    return result
  }

  /// Windows that were fully used (>= 100%) on the previous poll and are now below 100%.
  /// A window that disappears entirely between polls is not reported: there is no evidence
  /// that it actually dropped below 100% rather than temporarily failing to report.
  static func recoveredWindows(
    previous: [UsageWindowKey: Double],
    current: [UsageWindowKey: Double]
  ) -> [RecoveredUsageWindow] {
    previous.compactMap { key, previousPercent -> RecoveredUsageWindow? in
      guard previousPercent >= 100, let currentPercent = current[key], currentPercent < 100 else {
        return nil
      }
      return RecoveredUsageWindow(
        key: key, previousPercent: previousPercent, currentPercent: currentPercent)
    }.sorted { sortKey(for: $0.key) < sortKey(for: $1.key) }
  }

  private static func sortKey(for key: UsageWindowKey) -> String {
    [key.provider, key.source, key.accountKey, key.window].joined(separator: "\u{0}")
  }
}
