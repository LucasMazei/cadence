import Foundation

struct CadenceAccount: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var credentialsPath: String
    var tokenPath: String
    var calendar: Bool
    var tasks: Bool

    var tokenURL: URL {
        URL(fileURLWithPath: CadenceConfiguration.expandPath(tokenPath))
    }
}

struct CadenceConfiguration: Codable {
    var cacheDirectory: String? = nil
    var syncScript: String? = nil
    var backendCommand: String? = nil
    var credentialsPath: String? = nil
    var tokenPath: String? = nil
    var syncIntervalMinutes: Double? = nil
    var completedTaskDays: Int? = nil
    var accounts: [CadenceAccount]? = nil

    static func load() -> Self {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cadence/config.json")
        let configuredPath = ProcessInfo.processInfo.environment["CADENCE_CONFIG_PATH"]
            .map(expandPath)
            .map { URL(fileURLWithPath: $0) }
        let path = configuredPath ?? defaultPath

        guard let data = try? Data(contentsOf: path),
            let configuration = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return Self()
        }
        return configuration
    }

    var cacheDirectoryURL: URL {
        path(cacheDirectory, default: ".cache/cadence")
    }

    var syncScriptURL: URL {
        path(syncScript, default: ".local/share/cadence/bin/sync.sh")
    }

    var backendCommandURL: URL {
        path(backendCommand, default: ".local/share/cadence/bin/backend.sh")
    }

    /// Background Google sync interval. Defaults to 30 minutes, never below 1 minute.
    var syncInterval: TimeInterval {
        max(syncIntervalMinutes ?? 30, 1) * 60
    }

    var configuredAccounts: [CadenceAccount] {
        if let accounts { return accounts }
        return [
            CadenceAccount(
                id: "default",
                label: "Default",
                credentialsPath: credentialsPath ?? "~/.config/cadence/credentials.json",
                tokenPath: tokenPath ?? "~/.cache/cadence/token.json",
                calendar: true,
                tasks: true
            )
        ]
    }

    mutating func replaceAccounts(_ accounts: [CadenceAccount]) {
        self.accounts = accounts
    }

    func save() throws {
        let path = Self.configURL
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: path, options: .atomic)
    }

    static var configURL: URL {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cadence/config.json")
        guard let configuredPath = ProcessInfo.processInfo.environment["CADENCE_CONFIG_PATH"] else {
            return defaultPath
        }
        return URL(fileURLWithPath: expandPath(configuredPath))
    }

    private func path(_ configuredValue: String?, default relativePath: String) -> URL {
        if let configuredValue, !configuredValue.isEmpty {
            return URL(fileURLWithPath: Self.expandPath(configuredValue))
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
    }

    static func expandPath(_ value: String) -> String {
        (value as NSString).expandingTildeInPath
    }
}
