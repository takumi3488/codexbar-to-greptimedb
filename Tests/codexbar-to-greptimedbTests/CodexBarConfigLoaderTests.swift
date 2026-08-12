import CodexBarCore
import Foundation
import Testing

@testable import codexbar_to_greptimedb

@Test func ignoresUnknownDisabledProvidersInCodexBarConfig() throws {
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("json")
  defer { try? FileManager.default.removeItem(at: fileURL) }

  let data = Data(
    """
    {
      "version": 1,
      "providers": [
        { "id": "codex", "enabled": true },
        { "id": "notion", "enabled": false }
      ]
    }
    """.utf8)
  try data.write(to: fileURL)

  let config = try CodexBarConfigLoader.load(fileURL: fileURL)

  #expect(config.providerConfig(for: .codex)?.enabled == true)
  #expect(config.providers.count == UsageProvider.allCases.count)
}
