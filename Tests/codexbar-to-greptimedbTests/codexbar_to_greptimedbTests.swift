import CodexBarCore
import Foundation
import Testing

@testable import codexbar_to_greptimedb

@Test func mapsCoreSnapshotsIncludingExtraWindows() {
  let exported = ExportSnapshot(
    provider: .claude,
    result: providerResult(
      primary: RateWindow(
        usedPercent: 28,
        windowMinutes: 300,
        resetsAt: Date(timeIntervalSince1970: 1_000),
        resetDescription: nil
      ),
      secondary: RateWindow(
        usedPercent: 59,
        windowMinutes: 10_080,
        resetsAt: Date(timeIntervalSince1970: 2_000),
        resetDescription: nil
      ),
      extras: [
        NamedRateWindow(
          id: "burst",
          title: "Burst",
          window: RateWindow(
            usedPercent: 80,
            windowMinutes: 60,
            resetsAt: Date(timeIntervalSince1970: 3_000),
            resetDescription: nil
          )
        ),
        NamedRateWindow(
          id: "metadata-only",
          title: "Metadata only",
          window: RateWindow(
            usedPercent: 0,
            windowMinutes: 10,
            resetsAt: nil,
            resetDescription: nil
          ),
          usageKnown: false
        ),
      ],
      email: "person@example.com",
      organization: "Example",
      credits: 18.5
    ),
    capturedAt: Date(timeIntervalSince1970: 500)
  )

  #expect(exported.provider == "claude")
  #expect(exported.source == "oauth")
  #expect(exported.accountEmail == "person@example.com")
  #expect(exported.creditsRemaining == 18.5)
  #expect(
    exported.windows.map(\.name) == ["primary", "secondary", "extra:burst", "extra:metadata-only"])
  #expect(exported.windows[2].usedPercent == 80)
  #expect(exported.windows[3].usedPercent == nil)
}

@Test func preservesCreditOnlyCoreProviderAsSummaryRow() throws {
  let exported = ExportSnapshot(
    provider: .elevenlabs,
    result: providerResult(primary: nil, secondary: nil, extras: [], credits: 42),
    capturedAt: Date(timeIntervalSince1970: 0)
  )
  let configuration = try Configuration.parse(
    arguments: ["--greptime-url", "http://localhost:4000"],
    environment: [:]
  )

  let statement = try #require(
    GreptimeDBWriter(configuration: configuration).insertStatement(for: [exported])
  )

  #expect(exported.windows.isEmpty)
  #expect(statement.contains("'snapshot'"))
  #expect(statement.contains("42.0"))
}

@Test func commandLineOptionsOverrideEnvironmentAndOnceDisablesPolling() throws {
  let configuration = try Configuration.parse(
    arguments: [
      "--greptime-url", "https://greptime.example",
      "--database", "usage",
      "--table", "snapshots",
      "--provider", "claude",
      "--once",
    ],
    environment: [
      "GREPTIMEDB_URL": "http://ignored.example:4000",
      "GREPTIMEDB_DATABASE": "ignored",
      "CODEXBAR_TO_GREPTIMEDB_INTERVAL_SECONDS": "60",
    ]
  )

  #expect(configuration.greptimeDBURL.absoluteString == "https://greptime.example")
  #expect(configuration.database == "usage")
  #expect(configuration.table == "snapshots")
  #expect(configuration.provider == "claude")
  #expect(configuration.pollInterval == nil)
}

@Test func pollingEnvironmentAndBasicAuthenticationMustBeValid() throws {
  let configuration = try Configuration.parse(
    arguments: [],
    environment: [
      "GREPTIMEDB_URL": "http://localhost:4000",
      "CODEXBAR_TO_GREPTIMEDB_INTERVAL_SECONDS": "60",
      "GREPTIMEDB_USERNAME": "writer",
      "GREPTIMEDB_PASSWORD": "secret",
    ]
  )
  #expect(configuration.pollInterval == 60)
  #expect(configuration.username == "writer")
  #expect(configuration.password == "secret")

  #expect(throws: ExportError.self) {
    try Configuration.parse(
      arguments: ["--greptime-url", "http://localhost:4000", "--username", "writer"],
      environment: [:]
    )
  }
}

@Test func generatesOrderedSQLRowsFromCoreTypes() throws {
  let exported = ExportSnapshot(
    provider: .claude,
    result: providerResult(
      primary: RateWindow(
        usedPercent: 20,
        windowMinutes: 300,
        resetsAt: Date(timeIntervalSince1970: 1),
        resetDescription: nil
      ),
      secondary: nil,
      extras: [],
      email: "o'hara@example.com",
      credits: 12.5
    ),
    capturedAt: Date(timeIntervalSince1970: 0)
  )
  let configuration = try Configuration.parse(
    arguments: ["--greptime-url", "http://localhost:4000"],
    environment: [:]
  )

  let statement = try #require(
    GreptimeDBWriter(configuration: configuration).insertStatement(for: [exported])
  )

  #expect(
    statement.contains(
      "(0, 'claude', 'oauth', 'o''hara@example.com', 'snapshot', 'o''hara@example.com', NULL, NULL, NULL, NULL, 0, 12.5)"
    ))
  #expect(
    statement.contains(
      "(0, 'claude', 'oauth', 'o''hara@example.com', 'primary', 'o''hara@example.com', NULL, 20.0, 300, 1000, 0, 12.5)"
    ))
}

private func providerResult(
  primary: RateWindow?,
  secondary: RateWindow?,
  extras: [NamedRateWindow],
  email: String? = nil,
  organization: String? = nil,
  credits: Double? = nil
) -> ProviderFetchResult {
  let usage = UsageSnapshot(
    primary: primary,
    secondary: secondary,
    extraRateWindows: extras,
    updatedAt: Date(timeIntervalSince1970: 0),
    identity: ProviderIdentitySnapshot(
      providerID: .claude,
      accountEmail: email,
      accountOrganization: organization,
      loginMethod: "oauth"
    ),
    dataConfidence: .exact
  )
  return ProviderFetchResult(
    usage: usage,
    credits: credits.map {
      CreditsSnapshot(remaining: $0, events: [], updatedAt: Date(timeIntervalSince1970: 0))
    },
    dashboard: nil,
    sourceLabel: "oauth",
    strategyID: "test",
    strategyKind: .oauth
  )
}

@Test func usesActiveAccountLabelOnlyAsAccountKeyFallback() {
  let exported = ExportSnapshot(
    provider: .claude,
    result: providerResult(primary: nil, secondary: nil, extras: []),
    capturedAt: Date(timeIntervalSince1970: 0),
    accountLabel: "  active-account@example.com  "
  )

  #expect(exported.accountEmail == nil)
  #expect(exported.accountKey == "active-account@example.com")
}
