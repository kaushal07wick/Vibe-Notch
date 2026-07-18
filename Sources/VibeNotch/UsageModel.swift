import SwiftUI
import VibeNotchCore

/// Polls local usage sources and publishes them for the header chips.
@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var providers: [ProviderUsage] = []
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        let loaded = UsageLoader.load()
        if loaded != providers { providers = loaded }
    }
}

/// Header chip row: `Claude 5h 26% · Codex 7d 42%`, colored by pressure.
struct UsageChips: View {
    let providers: [ProviderUsage]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(providers, id: \.provider) { p in
                if let peak = p.peak { chip(p.provider, peak) }
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ provider: String, _ w: ProviderUsage.Window) -> some View {
        HStack(spacing: 5) {
            Text(provider).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.74))
            Text(w.label).font(VNFont.sysMono(10.5, .semibold))
                .foregroundStyle(Color.white.opacity(0.42))
            Text("\(Int(w.usedPercentage.rounded()))%")
                .font(VNFont.sysMono(11.5, .bold))
                .foregroundStyle(usageColor(w.usedPercentage))
            if let resets = w.resetsAt {
                Text(shortRemaining(until: resets)).font(VNFont.sysMono(10.5, .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .help(helpText)
    }

    private var helpText: String {
        providers.flatMap { p in
            p.windows.map { w in
                let reset = w.resetsAt.map { " resets \(remaining(until: $0))" } ?? ""
                return "\(p.provider) \(w.label) \(Int(w.usedPercentage.rounded()))%\(reset)"
            }
        }.joined(separator: "\n")
    }

    private func usageColor(_ pct: Double) -> Color {
        if pct >= 90 { return Color.red.opacity(0.95) }
        if pct >= 70 { return Color.orange.opacity(0.95) }
        return Color.green.opacity(0.95)
    }

    /// Compact reset countdown shown inline: "20m", "5h20m", "5d20h".
    private func shortRemaining(until date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSinceNow))
        if s >= 86400 { return "\(s / 86400)d\((s % 86400) / 3600)h" }
        if s >= 3600 { return "\(s / 3600)h\((s % 3600) / 60)m" }
        return "\(s / 60)m"
    }

    private func remaining(until date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSinceNow))
        if s >= 86400 { return "in \(s / 86400)d \((s % 86400) / 3600)h" }
        if s >= 3600 { return "in \(s / 3600)h \((s % 3600) / 60)m" }
        return "in \(s / 60)m"
    }
}
