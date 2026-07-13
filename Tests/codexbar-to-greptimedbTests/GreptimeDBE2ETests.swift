import CodexBarCore
import Foundation
import Testing

@testable import codexbar_to_greptimedb

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Test func writesSyntheticSnapshotToGreptimeDB() async throws {
  let environment = ProcessInfo.processInfo.environment
  guard environment["RUN_GREPTIMEDB_E2E"] == "1" else {
    return
  }
  guard let baseURL = environment["GREPTIMEDB_URL"] else {
    Issue.record("GREPTIMEDB_URL is required when RUN_GREPTIMEDB_E2E=1")
    return
  }

  let table = environment["GREPTIMEDB_E2E_TABLE"] ?? "ci_e2e_usage"
  let configuration = try Configuration.parse(
    arguments: ["--greptime-url", baseURL, "--table", table],
    environment: environment
  )
  let snapshot = ExportSnapshot(
    provider: .claude,
    result: ProviderFetchResult(
      usage: UsageSnapshot(
        primary: RateWindow(
          usedPercent: 25,
          windowMinutes: 300,
          resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
          resetDescription: nil
        ),
        secondary: nil,
        extraRateWindows: [],
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        identity: ProviderIdentitySnapshot(
          providerID: .claude,
          accountEmail: "e2e@example.invalid",
          accountOrganization: "e2e",
          loginMethod: "test"
        ),
        dataConfidence: .exact
      ),
      credits: CreditsSnapshot(
        remaining: 12.5,
        events: [],
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      dashboard: nil,
      sourceLabel: "e2e",
      strategyID: "integration-test",
      strategyKind: .apiToken
    ),
    capturedAt: Date(timeIntervalSince1970: 1_700_000_100)
  )

  let writer = GreptimeDBWriter(configuration: configuration)
  try await writer.ensureTableExists()
  #expect(try await writer.insert([snapshot]) == 2)

  let primaryRows = try await queryRowCount(
    baseURL: baseURL,
    database: configuration.database,
    sql: """
      SELECT count(*) AS row_count FROM \(table)
      WHERE provider = 'claude' AND provider_source = 'e2e'
        AND account_key = 'e2e@example.invalid'
        AND account_email = 'e2e@example.invalid'
        AND account_organization = 'e2e'
        AND usage_window = 'primary'
        AND used_percent = 25
        AND window_minutes = 300
        AND credits_remaining = 12.5
      """
  )
  #expect(primaryRows == 1)

  let summaryRows = try await queryRowCount(
    baseURL: baseURL,
    database: configuration.database,
    sql: """
      SELECT count(*) AS row_count FROM \(table)
      WHERE provider = 'claude' AND provider_source = 'e2e'
        AND account_key = 'e2e@example.invalid'
        AND usage_window = 'snapshot'
        AND used_percent IS NULL
        AND window_minutes IS NULL
        AND resets_at IS NULL
        AND credits_remaining = 12.5
      """
  )
  #expect(summaryRows == 1)
}

private func queryRowCount(
  baseURL: String,
  database: String,
  sql: String
) async throws -> Int {
  var components = URLComponents(string: baseURL)
  let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
  components?.path = "/\(basePath.isEmpty ? "" : basePath + "/")v1/sql"
  components?.queryItems = [URLQueryItem(name: "db", value: database)]
  let url = try #require(components?.url)

  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
  request.httpBody = Data("sql=\(formEncode(sql))".utf8)

  let (data, response) = try await URLSession.shared.data(for: request)
  let httpResponse = try #require(response as? HTTPURLResponse)
  #expect(httpResponse.statusCode == 200)
  let payload = try JSONDecoder().decode(GreptimeQueryResponse.self, from: data)
  return try #require(payload.output.first?.records?.rows.first?.first)
}

private struct GreptimeQueryResponse: Decodable {
  let output: [Output]

  struct Output: Decodable {
    let records: Records?
  }

  struct Records: Decodable {
    let rows: [[Int]]
  }
}

private func formEncode(_ value: String) -> String {
  value.utf8.map { byte in
    switch byte {
    case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x7E:
      return String(UnicodeScalar(byte))
    case 0x20:
      return "+"
    default:
      return "%\(String(byte, radix: 16, uppercase: true).leftPadding(to: 2, with: "0"))"
    }
  }.joined()
}

extension String {
  fileprivate func leftPadding(to length: Int, with character: Character) -> String {
    guard count < length else { return self }
    return String(repeating: String(character), count: length - count) + self
  }
}
