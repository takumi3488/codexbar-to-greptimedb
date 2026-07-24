import Foundation
import Testing

@testable import codexbar_to_greptimedb

@Test func formatsRecoveryMessageWithProviderAccountAndPercents() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovery = RecoveredUsageWindow(key: key, previousPercent: 100, currentPercent: 82.5)

  let message = DiscordNotifier.message(for: recovery)

  #expect(message.contains("claude"))
  #expect(message.contains("oauth"))
  #expect(message.contains("a@example.com"))
  #expect(message.contains("primary"))
  #expect(message.contains("100%"))
  #expect(message.contains("82.5%"))
}

@Test func formatsWholeNumberCurrentPercentWithoutADecimalPoint() {
  let key = UsageWindowKey(
    provider: "claude", source: "oauth", accountKey: "a@example.com", window: "primary")
  let recovery = RecoveredUsageWindow(key: key, previousPercent: 100, currentPercent: 75)

  let message = DiscordNotifier.message(for: recovery)

  #expect(message.contains("75%"))
  #expect(!message.contains("75.0%"))
}
