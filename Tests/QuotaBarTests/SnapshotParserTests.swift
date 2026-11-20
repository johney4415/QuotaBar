import Foundation
import Testing
@testable import QuotaBar

struct SnapshotParserTests {
    @Test func parsesCodexWindows() throws {
        let json = #"{"id":2,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":28,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":61,"windowDurationMins":10080,"resetsAt":1800100000}}}}"#
        let snapshot = try SnapshotParser.codex(from: Data(json.utf8))
        #expect(snapshot.provider == .codex)
        #expect(snapshot.windows.map(\.name) == ["5 小時", "7 天"])
        #expect(snapshot.windows[0].remainingPercent == 72)
        #expect(snapshot.mostConstrainedWindow?.usedPercent == 61)
    }

    @Test func parsesClaudeStatusLinePayload() throws {
        let json = #"{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":83,"resets_at":1800000000},"seven_day":{"used_percentage":40,"resets_at":1800100000}}}"#
        let snapshot = try SnapshotParser.claude(from: Data(json.utf8))
        #expect(snapshot.provider == .claude)
        #expect(snapshot.windows.map(\.usedPercent) == [83, 40])
        #expect(snapshot.detail == "Opus")
    }

    @Test func parsesClaudeLiveUsageResponse() throws {
        let json = #"{"type":"control_response","response":{"subtype":"success","request_id":"quota-bar","response":{"subscription_type":"max","rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":13,"resets_at":1800000000},"seven_day":{"utilization":42,"resets_at":1800100000}}}}}"#
        let snapshot = try SnapshotParser.claudeControlResponse(from: Data(json.utf8))
        #expect(snapshot.windows.map(\.usedPercent) == [13, 42])
        #expect(snapshot.detail == "max")
    }

    @Test func clampsPercentages() throws {
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":130,"resets_at":1800000000}}}"#
        let snapshot = try SnapshotParser.claude(from: Data(json.utf8))
        #expect(snapshot.windows[0].usedPercent == 100)
        #expect(snapshot.windows[0].remainingPercent == 0)
    }

    @Test func menuBarAlwaysShowsBothProviders() throws {
        let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":28,"windowDurationMins":300,"resetsAt":1800000000}}}}"#
        let codex = try SnapshotParser.codex(from: Data(json.utf8))

        let codexValue = MenuBarFormatter.value(
            for: .codex,
            snapshots: [.codex: codex],
            mode: .remaining,
            showPercentages: true
        )

        #expect(codexValue == "72%")
        #expect(MenuBarFormatter.value(
            for: .claude,
            snapshots: [.codex: codex],
            mode: .remaining,
            showPercentages: true
        ) == "--")
        #expect(MenuBarFormatter.value(
            for: .codex,
            snapshots: [:],
            mode: .remaining,
            showPercentages: false
        ).isEmpty)
    }

    @Test func brandIconsLoadAsImages() {
        #expect(BrandAssets.image(for: .codex) != nil)
        #expect(BrandAssets.image(for: .claude) != nil)
    }

    @Test func rendersBothMenuBarIconsAndValuesIntoOneImage() {
        let image = MenuBarRenderer.image(
            codexValue: "68%",
            claudeValue: "83%",
            showPercentages: true,
            codexIcon: .brand,
            claudeIcon: .sparkles
        )
        #expect(image.size.width > 70)
        #expect(image.size.height == 18)
        #expect(image.tiffRepresentation != nil)
        #expect(image.isTemplate)
    }

    @Test func sanitizesClaudeStatusPayloadBeforeWriting() throws {
        let input = #"{"cwd":"/private/work","transcript_path":"/private/transcript.jsonl","account":{"email":"private@example.com"},"model":{"id":"claude-secret","display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":17,"resets_at":1800000000,"internal":"remove-me"},"seven_day":{"used_percentage":34,"resets_at":1800100000},"model_scoped":{"secret":"remove-me"}}}"#
        let data = try LocalSecurity.sanitizedClaudeSnapshot(from: Data(input.utf8))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("used_percentage"))
        #expect(text.contains("Opus"))
        #expect(!text.contains("cwd"))
        #expect(!text.contains("transcript"))
        #expect(!text.contains("private@example.com"))
        #expect(!text.contains("claude-secret"))
        #expect(!text.contains("internal"))
        #expect(!text.contains("model_scoped"))
    }

    @Test func storesLocalDataWithOwnerOnlyPermissions() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotabar-security-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        try LocalSecurity.ensureOwnerOnlyDirectory(base)
        let file = base.appendingPathComponent("snapshot.json")
        try LocalSecurity.writeOwnerOnly(Data("{}".utf8), to: file)

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: base.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
