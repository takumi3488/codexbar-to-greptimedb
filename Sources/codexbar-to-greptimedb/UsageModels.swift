import CodexBarCore
import Foundation

enum ExportError: LocalizedError, Equatable {
  case invalidConfiguration(String)
  case providerFetchFailed(provider: String, message: String)
  case greptimeDBFailed(status: Int, message: String)
  case exportTimedOut(seconds: TimeInterval)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration(let message):
      return message
    case .providerFetchFailed(let provider, let message):
      return "CodexBarCore could not fetch \(provider): \(message)"
    case .greptimeDBFailed(let status, let message):
      return "GreptimeDB returned HTTP \(status): \(message)"
    case .exportTimedOut(let seconds):
      return "export timed out after \(seconds) seconds"
    }
  }
}

struct ExportWindow: Sendable {
  let name: String
  let usedPercent: Double?
  let windowMinutes: Int?
  let resetsAt: Date?
}

struct ExportSnapshot: Sendable {
  let capturedAt: Date
  let provider: String
  let source: String
  let accountKey: String
  let accountEmail: String?
  let accountOrganization: String?
  let usageUpdatedAt: Date
  let creditsRemaining: Double?
  let windows: [ExportWindow]

  init(
    provider: UsageProvider, result: ProviderFetchResult, capturedAt: Date,
    accountLabel: String? = nil
  ) {
    self.capturedAt = capturedAt
    self.provider = provider.rawValue
    source = result.sourceLabel
    let email = Self.nonEmpty(result.usage.identity?.accountEmail)
    accountEmail = email
    accountKey = email ?? Self.nonEmpty(accountLabel) ?? "__default__"
    accountOrganization = result.usage.identity?.accountOrganization
    usageUpdatedAt = result.usage.updatedAt
    creditsRemaining = result.credits?.remaining ?? result.usage.openRouterUsage?.balance

    windows =
      [
        Self.window(name: "primary", value: result.usage.primary),
        Self.window(name: "secondary", value: result.usage.secondary),
        Self.window(name: "tertiary", value: result.usage.tertiary),
      ].compactMap { $0 }
      + (result.usage.extraRateWindows ?? []).map {
        ExportWindow(
          name: "extra:\($0.id)",
          usedPercent: $0.usageKnown ? $0.window.usedPercent : nil,
          windowMinutes: $0.window.windowMinutes,
          resetsAt: $0.window.resetsAt
        )
      }
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func window(name: String, value: RateWindow?) -> ExportWindow? {
    guard let value else {
      return nil
    }
    return ExportWindow(
      name: name,
      usedPercent: value.usedPercent,
      windowMinutes: value.windowMinutes,
      resetsAt: value.resetsAt
    )
  }
}
