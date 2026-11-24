import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshots: [ProviderKind: ProviderSnapshot] = [:]
    @Published private(set) var errors: [ProviderKind: String] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var codexConnected = false
    @Published private(set) var claudeConnected = false
    @Published private(set) var claudeBridgeInstalled = ClaudeConnectionManager.isConnected()

    @Published var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }
    @Published var windowSelection: QuotaWindowSelection {
        didSet { defaults.set(windowSelection.rawValue, forKey: Keys.windowSelection) }
    }
    @Published var showPercentages: Bool {
        didSet { defaults.set(showPercentages, forKey: Keys.showPercentages) }
    }
    @Published var codexIconChoice: IconChoice {
        didSet { defaults.set(codexIconChoice.rawValue, forKey: Keys.codexIconChoice) }
    }
    @Published var claudeIconChoice: IconChoice {
        didSet { defaults.set(claudeIconChoice.rawValue, forKey: Keys.claudeIconChoice) }
    }

    private let defaults = UserDefaults.standard
    private let codexProvider = CodexProvider()
    private let claudeProvider = ClaudeProvider()
    private var timer: Timer?

    init() {
        displayMode = DisplayMode(rawValue: defaults.string(forKey: Keys.displayMode) ?? "") ?? .remaining
        windowSelection = QuotaWindowSelection(rawValue: defaults.string(forKey: Keys.windowSelection) ?? "") ?? .current
        showPercentages = defaults.object(forKey: Keys.showPercentages) as? Bool ?? true
        codexIconChoice = IconChoice(rawValue: defaults.string(forKey: Keys.codexIconChoice) ?? "") ?? .brand
        claudeIconChoice = IconChoice(rawValue: defaults.string(forKey: Keys.claudeIconChoice) ?? "") ?? .brand
        ClaudeConnectionManager.hardenExistingFiles()
    }

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
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
            codexConnected = true
        } catch {
            errors[.codex] = error.localizedDescription
            codexConnected = false
        }

        do {
            snapshots[.claude] = try await claudeProvider.fetchLatest()
            errors.removeValue(forKey: .claude)
            claudeConnected = true
        } catch {
            errors[.claude] = error.localizedDescription
            claudeConnected = false
        }
        claudeBridgeInstalled = ClaudeConnectionManager.isConnected()
    }

    func connectClaude() throws {
        try ClaudeConnectionManager.connect()
        claudeBridgeInstalled = true
    }

    func disconnectClaude() throws {
        try ClaudeConnectionManager.disconnect()
        claudeBridgeInstalled = false
        claudeConnected = false
        snapshots.removeValue(forKey: .claude)
    }

    func menuBarValue(for provider: ProviderKind) -> String {
        MenuBarFormatter.value(
            for: provider,
            snapshots: snapshots,
            mode: displayMode,
            showPercentages: showPercentages,
            windowSelection: windowSelection
        )
    }

    func iconChoice(for provider: ProviderKind) -> IconChoice {
        provider == .codex ? codexIconChoice : claudeIconChoice
    }

    private enum Keys {
        static let displayMode = "displayMode"
        static let windowSelection = "windowSelection"
        static let showPercentages = "showPercentages"
        static let codexIconChoice = "codexIconChoice"
        static let claudeIconChoice = "claudeIconChoice"
    }
}
