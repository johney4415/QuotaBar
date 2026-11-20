import Foundation

enum LocalSecurity {
    static let ownerDirectoryPermissions = 0o700
    static let ownerFilePermissions = 0o600

    static func ensureOwnerOnlyDirectory(_ url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: ownerDirectoryPermissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: ownerDirectoryPermissions],
            ofItemAtPath: url.path
        )
    }

    static func writeOwnerOnly(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try enforceOwnerOnlyFile(url)
    }

    static func enforceOwnerOnlyFile(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: ownerFilePermissions],
            ofItemAtPath: url.path
        )
    }

    static func sanitizedClaudeSnapshot(from input: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: input)
        guard let root = object as? [String: Any],
              let sourceRateLimits = root["rate_limits"] as? [String: Any]
        else { throw SnapshotParserError.missingRateLimits }

        var rateLimits: [String: Any] = [:]
        for key in ["five_hour", "seven_day"] {
            guard let source = sourceRateLimits[key] as? [String: Any] else { continue }
            var window: [String: Any] = [:]
            if let value = source["used_percentage"] as? NSNumber {
                window["used_percentage"] = value
            }
            if let value = source["resets_at"] as? NSNumber {
                window["resets_at"] = value
            }
            if !window.isEmpty { rateLimits[key] = window }
        }
        guard !rateLimits.isEmpty else { throw SnapshotParserError.missingRateLimits }

        var snapshot: [String: Any] = ["rate_limits": rateLimits]
        if let model = root["model"] as? [String: Any],
           let displayName = model["display_name"] as? String {
            snapshot["model"] = ["display_name": displayName]
        }
        return try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
    }
}
