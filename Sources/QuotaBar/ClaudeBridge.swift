import Foundation

enum ClaudeBridge {
    static func run() -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        do {
            try FileManager.default.createDirectory(
                at: ClaudeProvider.supportDirectory,
                withIntermediateDirectories: true
            )
            try input.write(to: ClaudeProvider.snapshotURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("QuotaBar: \(error.localizedDescription)\n".utf8))
        }

        if let originalData = try? Data(contentsOf: ClaudeProvider.originalStatusLineURL),
           let original = try? JSONSerialization.jsonObject(with: originalData) as? [String: Any],
           let command = original["command"] as? String,
           !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            let pipe = Pipe()
            process.standardInput = pipe
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            do {
                try process.run()
                pipe.fileHandleForWriting.write(input)
                pipe.fileHandleForWriting.closeFile()
                process.waitUntilExit()
                exit(process.terminationStatus)
            } catch {
                FileHandle.standardError.write(Data("QuotaBar wrapper: \(error.localizedDescription)\n".utf8))
            }
        }
        exit(0)
    }
}
