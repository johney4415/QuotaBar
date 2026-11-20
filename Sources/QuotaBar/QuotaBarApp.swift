import SwiftUI

@main
struct QuotaBarApp: App {
    @StateObject private var store = QuotaStore()

    init() {
        if CommandLine.arguments.contains("--claude-statusline-bridge") {
            ClaudeBridge.run()
        }
        if CommandLine.arguments.contains("--check") {
            do {
                let snapshot = try CodexProvider().fetchSynchronously()
                for window in snapshot.windows {
                    print("Codex \(window.name): \(Int(window.usedPercent.rounded()))% used")
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("QuotaBar: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
                .task { store.start() }
        } label: {
            Text(store.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
