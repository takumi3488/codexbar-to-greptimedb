import CodexBarCore
import Foundation

struct CodexBarConfigLoader {
  static func load(fileURL: URL = CodexBarConfigStore().fileURL) throws -> CodexBarConfig {
    let store = CodexBarConfigStore(fileURL: fileURL)
    do {
      return try store.load() ?? .makeDefault()
    } catch {
      guard let compatibleConfig = try loadIgnoringUnknownDisabledProviders(from: fileURL) else {
        throw error
      }
      return compatibleConfig
    }
  }

  private static func loadIgnoringUnknownDisabledProviders(from fileURL: URL) throws
    -> CodexBarConfig?
  {
    guard let data = try? Data(contentsOf: fileURL),
      let object = try? JSONSerialization.jsonObject(with: data),
      let root = object as? [String: Any],
      let providers = root["providers"] as? [Any]
    else {
      return nil
    }

    let knownProviderIDs = Set(UsageProvider.allCases.map(\.rawValue))
    var filteredProviders: [Any] = []
    var ignoredUnknownProvider = false
    filteredProviders.reserveCapacity(providers.count)

    for provider in providers {
      guard let providerObject = provider as? [String: Any],
        let providerID = providerObject["id"] as? String
      else {
        return nil
      }

      if knownProviderIDs.contains(providerID) {
        filteredProviders.append(provider)
      } else {
        guard providerObject["enabled"] as? Bool == false else {
          return nil
        }
        ignoredUnknownProvider = true
      }
    }

    guard ignoredUnknownProvider,
      let filteredData = try? JSONSerialization.data(withJSONObject: root.merging(
        ["providers": filteredProviders],
        uniquingKeysWith: { _, new in new }
      )),
      let config = try? JSONDecoder().decode(CodexBarConfig.self, from: filteredData)
    else {
      return nil
    }

    return config.normalized()
  }
}
