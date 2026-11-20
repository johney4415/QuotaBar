import Foundation

enum ClaudeProviderError: LocalizedError {
    case notConnected
    case stale
    case cliNotFound
    case liveUnavailable
    case liveTimedOut

    var errorDescription: String? {
        switch self {
        case .notConnected: "尚未連接 Claude Code status line"
        case .stale: "Claude 額度資料已過期，請開啟一個 Claude Code 工作階段"
        case .cliNotFound: "找不到 Claude Code CLI"
        case .liveUnavailable: "Claude Code 暫時未提供即時額度"
        case .liveTimedOut: "讀取 Claude Code 即時額度逾時"
        }
    }
}

final class ClaudeProvider: @unchecked Sendable {
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

    func fetchLatest() async throws -> ProviderSnapshot {
        do {
            return try await fetchLive()
        } catch {
            return try fetch()
        }
    }

    private func fetchLive() async throws -> ProviderSnapshot {
        try await Task.detached(priority: .utility) {
            try self.fetchLiveSynchronously()
        }.value
    }

    private func fetchLiveSynchronously() throws -> ProviderSnapshot {
        guard let executable = locateClaude() else { throw ClaudeProviderError.cliNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--safe-mode",
            "--no-session-persistence",
        ]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let response = ClaudeResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if response.consume(data: data) { semaphore.signal() }
        }

        try process.run()
        let request = #"{"type":"control_request","request_id":"quota-bar","request":{"subtype":"get_usage","skip_behaviors":true}}"# + "\n"
        input.fileHandleForWriting.write(Data(request.utf8))
        input.fileHandleForWriting.closeFile()

        let result = semaphore.wait(timeout: .now() + 8)
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }

        guard result == .success, let data = response.matchingResponse else {
            throw ClaudeProviderError.liveTimedOut
        }
        do {
            return try SnapshotParser.claudeControlResponse(from: data)
        } catch {
            throw ClaudeProviderError.liveUnavailable
        }
    }

    private func locateClaude() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["QUOTABAR_CLAUDE_PATH"],
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private final class ClaudeResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private(set) var matchingResponse: Data?

    func consume(data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "control_response"
            else { continue }
            matchingResponse = Data(line)
            return true
        }
        return false
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
