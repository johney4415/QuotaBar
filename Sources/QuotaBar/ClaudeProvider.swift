import Foundation

enum ClaudeProviderError: LocalizedError {
    case notConnected
    case stale

    var errorDescription: String? {
        switch self {
        case .notConnected: "尚未連接 Claude Code status line"
        case .stale: "Claude 額度資料已過期，請開啟一個 Claude Code 工作階段"
        }
    }
}

struct ClaudeProvider {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuotaBar", isDirectory: true)
    }

    static var snapshotURL: URL {
        supportDirectory.appendingPathComponent("claude-status.json")
    }

    static var originalStatusLineURL: URL {
        supportDirectory.appendingPathComponent("claude-original-statusline.json")
    }

    func fetch() throws -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: Self.snapshotURL.path) else {
            throw ClaudeProviderError.notConnected
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: Self.snapshotURL.path)
        let modifiedAt = attributes[.modificationDate] as? Date
        if let modifiedAt, Date().timeIntervalSince(modifiedAt) > 3_600 {
            throw ClaudeProviderError.stale
        }
        return try SnapshotParser.claude(
            from: Data(contentsOf: Self.snapshotURL),
            modifiedAt: modifiedAt
        )
    }
}

enum ClaudeConnectionManager {
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    static func isConnected() -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = root["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String
        else { return false }
        return command.contains("--claude-statusline-bridge")
    }

    static func connect() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: ClaudeProvider.supportDirectory,
            withIntermediateDirectories: true
        )

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL), !data.isEmpty {
            root = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }

        if let existing = root["statusLine"] as? [String: Any],
           let command = existing["command"] as? String,
           !command.contains("--claude-statusline-bridge") {
            let original = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
            try original.write(to: ClaudeProvider.originalStatusLineURL, options: .atomic)
        }

        guard let executable = Bundle.main.executableURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let escaped = executable.path.replacingOccurrences(of: "'", with: "'\\''")
        root["statusLine"] = [
            "type": "command",
            "command": "'\(escaped)' --claude-statusline-bridge",
            "padding": 0,
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    static func disconnect() throws {
        guard let data = try? Data(contentsOf: settingsURL),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let originalData = try? Data(contentsOf: ClaudeProvider.originalStatusLineURL),
           let original = try? JSONSerialization.jsonObject(with: originalData) as? [String: Any] {
            root["statusLine"] = original
        } else {
            root.removeValue(forKey: "statusLine")
        }
        let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: settingsURL, options: .atomic)
        try? FileManager.default.removeItem(at: ClaudeProvider.originalStatusLineURL)
    }
}
