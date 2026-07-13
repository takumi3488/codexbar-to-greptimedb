import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct GreptimeDBWriter: Sendable {
  let configuration: Configuration

  func ensureTableExists() async throws {
    try await execute(
      sql: """
        CREATE TABLE IF NOT EXISTS \(configuration.table) (
          ts TIMESTAMP(3) NOT NULL,
          provider STRING NOT NULL,
          provider_source STRING NOT NULL,
          account_key STRING NOT NULL,
          usage_window STRING NOT NULL,
          account_email STRING NULL,
          account_organization STRING NULL,
          used_percent DOUBLE NULL,
          window_minutes INT NULL,
          resets_at TIMESTAMP(3) NULL,
          usage_updated_at TIMESTAMP(3) NULL,
          credits_remaining DOUBLE NULL,
          TIME INDEX (ts),
          PRIMARY KEY (provider, provider_source, account_key, usage_window)
        ) WITH ('append_mode' = 'true')
        """)
  }

  func insert(_ snapshots: [ExportSnapshot]) async throws -> Int {
    let rows = snapshots.flatMap(sqlRows(for:))
    guard let statement = insertStatement(for: rows) else {
      return 0
    }
    try await execute(sql: statement)
    return rows.count
  }

  func insertStatement(for snapshots: [ExportSnapshot]) -> String? {
    insertStatement(for: snapshots.flatMap(sqlRows(for:)))
  }

  private func insertStatement(for rows: [[SQLValue]]) -> String? {
    guard !rows.isEmpty else {
      return nil
    }
    let columnNames = [
      "ts", "provider", "provider_source", "account_key", "usage_window",
      "account_email", "account_organization", "used_percent", "window_minutes",
      "resets_at", "usage_updated_at", "credits_remaining",
    ]
    let columns = "(\(columnNames.joined(separator: ", ")))"
    let values = rows.map { "(\($0.map(sqlLiteral).joined(separator: ", ")))" }.joined(
      separator: ", ")
    return "INSERT INTO \(configuration.table) \(columns) VALUES \(values)"
  }

  private func sqlRows(for snapshot: ExportSnapshot) -> [[SQLValue]] {
    let summary = sqlRow(
      for: snapshot,
      window: "snapshot",
      usedPercent: nil,
      windowMinutes: nil,
      resetsAt: nil
    )
    let windows = snapshot.windows.map { window in
      sqlRow(
        for: snapshot,
        window: window.name,
        usedPercent: window.usedPercent,
        windowMinutes: window.windowMinutes,
        resetsAt: window.resetsAt
      )
    }
    return [summary] + windows
  }

  private func sqlRow(
    for snapshot: ExportSnapshot,
    window: String,
    usedPercent: Double?,
    windowMinutes: Int?,
    resetsAt: Date?
  ) -> [SQLValue] {
    [
      .date(snapshot.capturedAt),
      .string(snapshot.provider),
      .string(snapshot.source),
      .string(snapshot.accountKey),
      .string(window),
      snapshot.accountEmail.map(SQLValue.string) ?? .null,
      snapshot.accountOrganization.map(SQLValue.string) ?? .null,
      usedPercent.map(SQLValue.double) ?? .null,
      windowMinutes.map(SQLValue.integer) ?? .null,
      resetsAt.map(SQLValue.date) ?? .null,
      .date(snapshot.usageUpdatedAt),
      snapshot.creditsRemaining.map(SQLValue.double) ?? .null,
    ]
  }

  private func execute(sql: String) async throws {
    var components = URLComponents(url: configuration.greptimeDBURL, resolvingAgainstBaseURL: false)
    let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
    components?.path = "/\(basePath.isEmpty ? "" : basePath + "/")v1/sql"
    components?.queryItems = [URLQueryItem(name: "db", value: configuration.database)]
    guard let url = components?.url else {
      throw ExportError.invalidConfiguration("could not build GreptimeDB SQL endpoint URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("UTC", forHTTPHeaderField: "X-Greptime-Timezone")
    if let username = configuration.username, let password = configuration.password {
      let credential = Data("\(username):\(password)".utf8).base64EncodedString()
      request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = Data("sql=\(formEncode(sql))".utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ExportError.greptimeDBFailed(status: 0, message: "received a non-HTTP response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw ExportError.greptimeDBFailed(
        status: httpResponse.statusCode,
        message: String(decoding: data.prefix(500), as: UTF8.self)
      )
    }

    if let response = try? JSONDecoder().decode(GreptimeSQLResponse.self, from: data),
      let error = response.error
    {
      throw ExportError.greptimeDBFailed(status: httpResponse.statusCode, message: error)
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

  private func sqlLiteral(_ value: SQLValue) -> String {
    switch value {
    case .null:
      return "NULL"
    case .string(let string):
      return "'\(string.replacingOccurrences(of: "'", with: "''"))'"
    case .integer(let integer):
      return String(integer)
    case .double(let double):
      guard double.isFinite else { return "NULL" }
      return String(double)
    case .date(let date):
      return String(Int64((date.timeIntervalSince1970 * 1_000).rounded()))
    }
  }

  private struct GreptimeSQLResponse: Decodable {
    let error: String?
  }

  private enum SQLValue {
    case null
    case string(String)
    case integer(Int)
    case double(Double)
    case date(Date)
  }
}

extension String {
  fileprivate func leftPadding(to length: Int, with character: Character) -> String {
    guard count < length else { return self }
    return String(repeating: String(character), count: length - count) + self
  }
}
