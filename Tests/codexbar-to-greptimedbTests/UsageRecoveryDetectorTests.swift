import CodexBarCore
import Foundation
import Testing

@testable import codexbar_to_greptimedb

@Test func reportsWindowThatDroppedBelow100Percent() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovered = UsageRecoveryDetector.recoveredWindows(
    previous: [key: 100],
    current: [key: 82]
  )

  #expect(recovered == [RecoveredUsageWindow(key: key, previousPercent: 100, currentPercent: 82)])
}

@Test func ignoresWindowThatWasNeverAt100Percent() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovered = UsageRecoveryDetector.recoveredWindows(
    previous: [key: 90],
    current: [key: 82]
  )

  #expect(recovered.isEmpty)
}

@Test func ignoresWindowThatIsStillAt100Percent() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovered = UsageRecoveryDetector.recoveredWindows(
    previous: [key: 100],
    current: [key: 100]
  )

  #expect(recovered.isEmpty)
}

@Test func ignoresWindowMissingFromTheCurrentPoll() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovered = UsageRecoveryDetector.recoveredWindows(
    previous: [key: 100],
    current: [:]
  )

  #expect(recovered.isEmpty)
}

@Test func treatsSlightlyOver100PercentAsFullyUsed() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovered = UsageRecoveryDetector.recoveredWindows(
    previous: [key: 100.5],
    current: [key: 82]
  )

  #expect(recovered == [RecoveredUsageWindow(key: key, previousPercent: 100.5, currentPercent: 82)])
}

@Test func distinguishesWindowsBySameProviderDifferentAccountOrWindow() {
  let primaryWindow = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let secondaryWindow = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "secondary")
  let otherAccount = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "b@example.com", window: "primary")
  let recovered = UsageRecoveryDetector.recoveredWindows(
    previous: [primaryWindow: 100, secondaryWindow: 100, otherAccount: 100],
    current: [primaryWindow: 82, secondaryWindow: 100, otherAccount: 100]
  )

  #expect(recovered.map(\.key) == [primaryWindow])
}

@Test func excludesWindowsWithUnknownUsageFromUsagePercents() {
  let exported = ExportSnapshot(
    provider: .claude,
    result: providerResult(
      primary: nil,
      secondary: nil,
      extras: [
        NamedRateWindow(
          id: "metadata-only",
          title: "Metadata only",
          window: RateWindow(
            usedPercent: 0, windowMinutes: 10, resetsAt: nil, resetDescription: nil),
          usageKnown: false
        )
      ],
      email: "a@example.com"
    ),
    capturedAt: Date(timeIntervalSince1970: 0)
  )

  let percents = UsageRecoveryDetector.usagePercents(in: [exported])

  #expect(percents.isEmpty)
}

@Test func sortsMultipleRecoveredWindowsDeterministically() {
  let claudeKey = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let codexKey = UsageWindowKey(
    provider: "codex", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovered = UsageRecoveryDetector.recoveredWindows(
    previous: [claudeKey: 100, codexKey: 100],
    current: [claudeKey: 50, codexKey: 10]
  )

  #expect(recovered.map(\.key.provider) == ["claude", "codex"])
}

@Test func collectsUsagePercentsKeyedByProviderSourceAccountAndWindow() {
  let exported = ExportSnapshot(
    provider: .claude,
    result: providerResult(
      primary: RateWindow(
        usedPercent: 100,
        windowMinutes: 300,
        resetsAt: nil,
        resetDescription: nil
      ),
      secondary: nil,
      extras: [],
      email: "a@example.com"
    ),
    capturedAt: Date(timeIntervalSince1970: 0)
  )

  let percents = UsageRecoveryDetector.usagePercents(in: [exported])

  #expect(
    percents[
      UsageWindowKey(
        provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")]
      == 100)
}
