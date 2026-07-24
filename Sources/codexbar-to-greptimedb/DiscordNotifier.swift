import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct DiscordNotifier: Sendable {
  struct Failure: Sendable {
    let window: RecoveredUsageWindow
    let error: Error
  }

  let webhookURL: URL

  /// Attempts every window independently so one failed webhook call cannot suppress
  /// notifications for the others. Returns the windows that failed to send.
  func notify(recovered windows: [RecoveredUsageWindow]) async -> [Failure] {
    var failures: [Failure] = []
    for window in windows {
      do {
        try await send(content: Self.message(for: window))
      } catch {
        failures.append(Failure(window: window, error: error))
      }
    }
    return failures
  }

  static func message(for recovery: RecoveredUsageWindow) -> String {
    let key = recovery.key
    let previous = formatPercent(recovery.previousPercent)
    let current = formatPercent(recovery.currentPercent)
    return
      "codexbar-to-greptimedb: \(key.provider) (\(key.source)) account \(key.accountKey) "
      + "usage window \"\(key.window)\" is no longer at 100% (\(previous)% -> \(current)%)."
  }

  private static func formatPercent(_ percent: Double) -> String {
    percent.rounded() == percent ? String(Int(percent)) : String(percent)
  }

  private func send(content: String) async throws {
    var request = URLRequest(url: webhookURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["content": content])

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ExportError.discordNotificationFailed(
        status: 0, message: "received a non-HTTP response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw ExportError.discordNotificationFailed(
        status: httpResponse.statusCode,
        message: String(decoding: data.prefix(500), as: UTF8.self)
      )
    }
  }
}
