import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }

}

enum MenuBarFormatter {
    static func value(
        for provider: ProviderKind,
        snapshots: [ProviderKind: ProviderSnapshot],
        mode: DisplayMode,
        showPercentages: Bool
    ) -> String {
        guard showPercentages else { return "" }
        guard let window = snapshots[provider]?.mostConstrainedWindow else { return "--" }
        return "\(Int(window.value(for: mode).rounded()))%"
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }

    var label: String {
        switch self {
        case .remaining: "剩餘"
        case .used: "已使用"
        }
    }
}

struct UsageWindow: Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    func value(for mode: DisplayMode) -> Double {
        mode == .used ? usedPercent : remainingPercent
    }
}

struct ProviderSnapshot: Codable, Equatable {
    let provider: ProviderKind
    let windows: [UsageWindow]
    let updatedAt: Date
    let detail: String?

    var mostConstrainedWindow: UsageWindow? {
        windows.max(by: { $0.usedPercent < $1.usedPercent })
    }
}

enum SnapshotParserError: LocalizedError {
    case malformedResponse
    case missingRateLimits

    var errorDescription: String? {
        switch self {
        case .malformedResponse: "無法解析額度資料"
        case .missingRateLimits: "尚未收到額度資料"
        }
    }
}

enum SnapshotParser {
    static func codex(from data: Data, now: Date = Date()) throws -> ProviderSnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let result = root["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any]
        else { throw SnapshotParserError.malformedResponse }

        var windows: [UsageWindow] = []
        if let primary = rateLimits["primary"] as? [String: Any] {
            windows.append(try codexWindow(primary, fallbackName: "主要週期"))
        }
        if let secondary = rateLimits["secondary"] as? [String: Any] {
            windows.append(try codexWindow(secondary, fallbackName: "次要週期"))
        }
        guard !windows.isEmpty else { throw SnapshotParserError.missingRateLimits }

        return ProviderSnapshot(
            provider: .codex,
            windows: windows,
            updatedAt: now,
            detail: rateLimits["planType"] as? String
        )
    }

    static func claude(from data: Data, modifiedAt: Date? = nil, now: Date = Date()) throws -> ProviderSnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let rateLimits = root["rate_limits"] as? [String: Any]
        else { throw SnapshotParserError.missingRateLimits }

        let mappings = [("five_hour", "5 小時"), ("seven_day", "7 天")]
        let windows = mappings.compactMap { key, label -> UsageWindow? in
            guard let value = rateLimits[key] as? [String: Any],
                  let used = number(value["used_percentage"])
            else { return nil }
            return UsageWindow(
                name: label,
                usedPercent: min(100, max(0, used)),
                resetsAt: unixDate(value["resets_at"])
            )
        }
        guard !windows.isEmpty else { throw SnapshotParserError.missingRateLimits }

        return ProviderSnapshot(
            provider: .claude,
            windows: windows,
            updatedAt: modifiedAt ?? now,
            detail: (root["model"] as? [String: Any])?["display_name"] as? String
        )
    }

    private static func codexWindow(_ value: [String: Any], fallbackName: String) throws -> UsageWindow {
        guard let used = number(value["usedPercent"]) else {
            throw SnapshotParserError.malformedResponse
        }
        let duration = number(value["windowDurationMins"])
        let name: String
        if let duration {
            if duration <= 360 {
                name = "\(Int((duration / 60).rounded())) 小時"
            } else if duration >= 10_000 {
                name = "7 天"
            } else {
                name = "\(Int((duration / 1_440).rounded())) 天"
            }
        } else {
            name = fallbackName
        }
        return UsageWindow(
            name: name,
            usedPercent: min(100, max(0, used)),
            resetsAt: unixDate(value["resetsAt"])
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func unixDate(_ value: Any?) -> Date? {
        guard let seconds = number(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
