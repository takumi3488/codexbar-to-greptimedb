import Foundation

struct Exporter: Sendable {
  let configuration: Configuration

  func runOnce() async throws {
    let snapshots = try await CodexBarCoreFetcher(
      providerSelector: configuration.provider,
      sourceOverride: configuration.source
    ).fetchSnapshots()
    let writer = GreptimeDBWriter(configuration: configuration)
    try await writer.ensureTableExists()
    let rowCount = try await writer.insert(snapshots)

    let providers = Set(snapshots.map(\.provider)).sorted().joined(separator: ", ")
    print("saved \(rowCount) rows for \(snapshots.count) provider snapshot(s): \(providers)")
  }
}
