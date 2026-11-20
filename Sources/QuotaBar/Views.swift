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

    static func menuBarImage(for provider: ProviderKind, choice: IconChoice) -> NSImage {
        let selected: NSImage?
        if let symbolName = choice.systemSymbolName {
            selected = NSImage(systemSymbolName: symbolName, accessibilityDescription: provider.displayName)
        } else {
            selected = image(for: provider)
        }
        let image = selected
            ?? NSImage(systemSymbolName: provider == .codex ? "terminal" : "sparkles", accessibilityDescription: provider.displayName)
            ?? NSImage()
        image.size = NSSize(width: 11, height: 11)
        image.isTemplate = true
        return image
    }
}

enum MenuBarRenderer {
    static func image(
        codexValue: String,
        claudeValue: String,
        showPercentages: Bool,
        codexIcon: IconChoice,
        claudeIcon: IconChoice
    ) -> NSImage {
        let iconSize: CGFloat = 11
        let height: CGFloat = 18
        let providerGap: CGFloat = 6
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let codexText = showPercentages ? " \(codexValue)" : ""
        let claudeText = showPercentages ? " \(claudeValue)" : ""
        let separator = "·"
        let codexTextSize = (codexText as NSString).size(withAttributes: attributes)
        let claudeTextSize = (claudeText as NSString).size(withAttributes: attributes)
        let separatorSize = (separator as NSString).size(withAttributes: attributes)
        let width = iconSize + codexTextSize.width
            + providerGap + separatorSize.width + providerGap
            + iconSize + claudeTextSize.width

        let result = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { rect in
            var x: CGFloat = 0
            let iconY = (rect.height - iconSize) / 2
            let textY = (rect.height - font.capHeight) / 2 - 1

            drawIcon(.codex, choice: codexIcon, in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize))
            x += iconSize
            if showPercentages {
                (codexText as NSString).draw(at: NSPoint(x: x, y: textY), withAttributes: attributes)
                x += codexTextSize.width
            }

            x += providerGap
            (separator as NSString).draw(at: NSPoint(x: x, y: textY), withAttributes: attributes)
            x += separatorSize.width + providerGap

            drawIcon(.claude, choice: claudeIcon, in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize))
            x += iconSize
            if showPercentages {
                (claudeText as NSString).draw(at: NSPoint(x: x, y: textY), withAttributes: attributes)
            }
            return true
        }
        result.isTemplate = true
        return result
    }

    private static func drawIcon(_ provider: ProviderKind, choice: IconChoice, in rect: NSRect) {
        let image = BrandAssets.menuBarImage(for: provider, choice: choice)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
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

struct CombinedMenuBarLabel: View {
    @ObservedObject var store: QuotaStore

    var body: some View {
        Image(nsImage: MenuBarRenderer.image(
            codexValue: store.menuBarValue(for: .codex),
            claudeValue: store.menuBarValue(for: .claude),
            showPercentages: store.showPercentages,
            codexIcon: store.codexIconChoice,
            claudeIcon: store.claudeIconChoice
        ))
        .renderingMode(.template)
        .accessibilityLabel(
            "Codex \(store.menuBarValue(for: .codex)), Claude Code \(store.menuBarValue(for: .claude))"
        )
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
                .help("同時更新 Codex 與 Claude Code")
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

            Picker("選單列額度", selection: $store.windowSelection) {
                ForEach(QuotaWindowSelection.allCases) { selection in
                    Text(selection.label).tag(selection)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text("選單列圖示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("Codex", selection: $store.codexIconChoice) {
                        ForEach(IconChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    Picker("Claude", selection: $store.claudeIconChoice) {
                        ForEach(IconChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                }
            }

            HStack {
                Label(
                    "Codex 自動連線",
                    systemImage: store.snapshots[.codex] == nil ? "circle.dashed" : "checkmark.circle.fill"
                )
                Spacer()
                Label(
                    store.claudeConnected ? "Claude 已連線" : "Claude 未連線",
                    systemImage: store.claudeConnected ? "checkmark.circle.fill" : "circle.dashed"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
