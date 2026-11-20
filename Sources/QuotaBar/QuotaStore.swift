import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshots: [ProviderKind: ProviderSnapshot] = [:]
    @Published private(set) var errors: [ProviderKind: String] = [:]
    @Published private(set) var isRefreshing = false
    @Published var claudeConnected = ClaudeConnectionManager.isConnected()

    @Published var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }
    @Published var showPercentages: Bool {
        didSet { defaults.set(showPercentages, forKey: Keys.showPercentages) }
    }

    private let defaults = UserDefaults.standard
    private let codexProvider = CodexProvider()
    private let claudeProvider = ClaudeProvider()
    private var timer: Timer?

    init() {
        displayMode = DisplayMode(rawValue: defaults.string(forKey: Keys.displayMode) ?? "") ?? .remaining
        showPercentages = defaults.object(forKey: Keys.showPercentages) as? Bool ?? true
    }

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            snapshots[.codex] = try await codexProvider.fetch()
            errors.removeValue(forKey: .codex)
        } catch {
            errors[.codex] = error.localizedDescription
        }

        do {
            snapshots[.claude] = try claudeProvider.fetch()
            errors.removeValue(forKey: .claude)
        } catch {
            errors[.claude] = error.localizedDescription
        }
        claudeConnected = ClaudeConnectionManager.isConnected()
    }

    func connectClaude() throws {
        try ClaudeConnectionManager.connect()
        claudeConnected = true
    }

    func disconnectClaude() throws {
        try ClaudeConnectionManager.disconnect()
        claudeConnected = false
        snapshots.removeValue(forKey: .claude)
    }

    var menuBarTitle: String {
        guard showPercentages else { return "◔" }
        let parts = ProviderKind.allCases.compactMap { provider -> String? in
            guard let window = snapshots[provider]?.mostConstrainedWindow else { return nil }
            return "\(provider.shortName) \(Int(window.value(for: displayMode).rounded()))%"
        }
        return parts.isEmpty ? "額度 --" : parts.joined(separator: " · ")
    }

    private enum Keys {
        static let displayMode = "displayMode"
        static let showPercentages = "showPercentages"
    }
}
