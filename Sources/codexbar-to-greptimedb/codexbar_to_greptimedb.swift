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
      guard let interval = configuration.pollInterval else {
        try await exporter.runOnce()
        return
      }

      while !Task.isCancelled {
        do {
          try await exporter.runOnce()
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
