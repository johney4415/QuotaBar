import Foundation

enum CodexProviderError: LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case timedOut
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound: "找不到 Codex CLI，請先安裝並登入 Codex"
        case .launchFailed(let message): "無法啟動 Codex：\(message)"
        case .timedOut: "讀取 Codex 額度逾時"
        case .serverError(let message): "Codex 回報錯誤：\(message)"
        }
    }
}

final class CodexProvider: @unchecked Sendable {
    func fetch() async throws -> ProviderSnapshot {
        try await Task.detached(priority: .utility) {
            try self.fetchSynchronously()
        }.value
    }

    func fetchSynchronously() throws -> ProviderSnapshot {
        guard let executable = locateCodex() else {
            throw CodexProviderError.executableNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let response = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if response.consume(data: data) { semaphore.signal() }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw CodexProviderError.launchFailed(error.localizedDescription)
        }

        let requests = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"quota-bar","title":"QuotaBar","version":"0.1.0"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"id":2,"method":"account/rateLimits/read","params":{}}"#,
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(requests.utf8))

        let result = semaphore.wait(timeout: .now() + 8)
        output.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }

        guard result == .success else { throw CodexProviderError.timedOut }
        guard let data = response.matchingResponse else { throw CodexProviderError.timedOut }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any] {
            throw CodexProviderError.serverError(error["message"] as? String ?? "未知錯誤")
        }
        return try SnapshotParser.codex(from: data)
    }

    private func locateCodex() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["QUOTABAR_CODEX_PATH"],
            nativeCodex(under: "/opt/homebrew/lib/node_modules/@openai/codex"),
            nativeCodex(under: "/usr/local/lib/node_modules/@openai/codex"),
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func nativeCodex(under packageRoot: String) -> String? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: packageRoot) else { return nil }
        while let relative = enumerator.nextObject() as? String {
            guard relative.hasSuffix("/bin/codex"), relative.contains("/vendor/") else { continue }
            let path = URL(fileURLWithPath: packageRoot).appendingPathComponent(relative).path
            if fileManager.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

private final class ResponseBox: @unchecked Sendable {
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
                  (object["id"] as? NSNumber)?.intValue == 2
            else { continue }
            matchingResponse = Data(line)
            return true
        }
        return false
    }
}
