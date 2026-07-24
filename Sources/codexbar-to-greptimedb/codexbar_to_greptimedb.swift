import Foundation

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

@main
struct CodexBarToGreptimeDB {
  static func main() async {
    do {
      let configuration = try Configuration.parse(
        arguments: Array(CommandLine.arguments.dropFirst()),
        environment: ProcessInfo.processInfo.environment
      )

      if configuration.showHelp {
        print(Configuration.usage)
        return
      }

      let exporter = Exporter(configuration: configuration)
      let timeoutSeconds = configuration.exportTimeoutSeconds
      guard let interval = configuration.pollInterval else {
        _ = try await withExportTimeout(seconds: timeoutSeconds) {
          try await exporter.runOnce()
        }
        return
      }

      let discordNotifier = configuration.discordWebhookURL.map(DiscordNotifier.init(webhookURL:))
      var previousUsagePercents: [UsageWindowKey: Double] = [:]

      while !Task.isCancelled {
        do {
          let snapshots = try await withExportTimeout(seconds: timeoutSeconds) {
            try await exporter.runOnce()
          }
          if let discordNotifier {
            var nextUsagePercents = UsageRecoveryDetector.usagePercents(in: snapshots)
            let recovered = UsageRecoveryDetector.recoveredWindows(
              previous: previousUsagePercents, current: nextUsagePercents)
            if !recovered.isEmpty {
              // Windows that fail to notify keep their pre-recovery baseline so the
              // next poll re-detects and retries them instead of losing the alert.
              do {
                let failures = try await withExportTimeout(seconds: timeoutSeconds) {
                  await discordNotifier.notify(recovered: recovered)
                }
                for failure in failures {
                  let key = failure.window.key
                  FileHandle.standardError.write(
                    Data(
                      "warning: failed to send Discord notification for \(key.provider)/\(key.window): \(failure.error.localizedDescription)\n"
                        .utf8))
                  nextUsagePercents[key] = failure.window.previousPercent
                }
              } catch {
                FileHandle.standardError.write(
                  Data(
                    "warning: failed to send Discord notifications: \(error.localizedDescription)\n"
                      .utf8))
                for window in recovered {
                  nextUsagePercents[window.key] = window.previousPercent
                }
              }
            }
            previousUsagePercents = nextUsagePercents
          }
        } catch {
          FileHandle.standardError.write(
            Data("error: \(error.localizedDescription); retrying in \(interval) seconds\n".utf8)
          )
        }
        try? await Task.sleep(for: .seconds(interval))
      }
    } catch {
      FileHandle.standardError.write(
        Data("error: \(error.localizedDescription)\n".utf8)
      )
      exit(1)
    }
  }
}
