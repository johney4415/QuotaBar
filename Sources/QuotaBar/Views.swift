import AppKit
import SwiftUI

enum BrandAssets {
    static func image(for provider: ProviderKind) -> NSImage? {
        let name = provider == .codex ? "gpt" : "claude-code"
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }
}

struct ProviderBrandIcon: View {
    let provider: ProviderKind
    var size: CGFloat = 14

    var body: some View {
        if let image = BrandAssets.image(for: provider) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: provider == .codex ? "terminal" : "sparkles")
                .frame(width: size, height: size)
        }
    }

}

struct ProviderMenuBarLabel: View {
    @ObservedObject var store: QuotaStore
    let provider: ProviderKind

    var body: some View {
        HStack(spacing: 3) {
            ProviderBrandIcon(provider: provider, size: 11)
                .accessibilityLabel(provider.displayName)
            if store.showPercentages {
                Text(store.menuBarValue(for: provider))
                    .monospacedDigit()
            }
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var store: QuotaStore
    @State private var connectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("QuotaBar").font(.headline)
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("立即更新")
            }

            ForEach(ProviderKind.allCases) { provider in
                ProviderSection(
                    provider: provider,
                    snapshot: store.snapshots[provider],
                    error: store.errors[provider],
                    mode: store.displayMode,
                    showPercentages: store.showPercentages
                )
            }

            Divider()

            Toggle("顯示百分比", isOn: $store.showPercentages)
            Picker("顯示方式", selection: $store.displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button(store.claudeConnected ? "中斷 Claude" : "連接 Claude Code") {
                    do {
                        if store.claudeConnected {
                            try store.disconnectClaude()
                        } else {
                            try store.connectClaude()
                        }
                    } catch {
                        connectionError = error.localizedDescription
                    }
                }
                Spacer()
                Button("結束") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
        .alert("Claude 連線失敗", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(connectionError ?? "未知錯誤")
        }
    }
}

private struct ProviderSection: View {
    let provider: ProviderKind
    let snapshot: ProviderSnapshot?
    let error: String?
    let mode: DisplayMode
    let showPercentages: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                ProviderBrandIcon(provider: provider, size: 14)
                Text(provider.displayName).font(.headline)
                Spacer()
                if let updatedAt = snapshot?.updatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot {
                ForEach(snapshot.windows) { window in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(window.name)
                            Spacer()
                            if showPercentages {
                                Text("\(Int(window.value(for: mode).rounded()))% \(mode.label)")
                                    .monospacedDigit()
                                    .fontWeight(.medium)
                            }
                        }
                        ProgressView(value: mode == .used ? window.usedPercent : window.remainingPercent, total: 100)
                            .tint(color(for: window))
                        if let resetsAt = window.resetsAt {
                            Text("重置：\(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text(error ?? "正在讀取…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func color(for window: UsageWindow) -> Color {
        let remaining = window.remainingPercent
        if remaining < 15 { return .red }
        if remaining < 35 { return .orange }
        return .accentColor
    }
}
