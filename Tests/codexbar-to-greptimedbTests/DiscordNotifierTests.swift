import Foundation
import Testing

@testable import codexbar_to_greptimedb

@Test func formatsRecoveryMessageWithProviderAccountAndPercents() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovery = RecoveredUsageWindow(key: key, previousPercent: 100, currentPercent: 82.5)

  let message = DiscordNotifier.message(for: recovery)

  #expect(
    message == """
      🎉 **Usage limit recovered**
      **Provider:** claude (`oauth`)
      **Window:** primary
      **Usage:** 100% → 82.5%
      **Account:** a@example.com
      """)
}

@Test func formatsWholeNumberCurrentPercentWithoutADecimalPoint() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovery = RecoveredUsageWindow(key: key, previousPercent: 100, currentPercent: 75)

  let message = DiscordNotifier.message(for: recovery)

  #expect(message.contains("75%"))
  #expect(!message.contains("75.0%"))
}
