import SwiftUI
import VibeNotchCore

/// Polls local usage sources and publishes them for the header chips.
@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var providers: [ProviderUsage] = []
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?

    func start() {
        refresh()
        // Instant updates when Claude's status line writes the cache…
        watchCacheDirectory()
        // …with a slow timer as the Codex-rollout / missed-event fallback.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    /// Watch ~/.vibenotch/cache for writes (covers file creation too — a
    /// direct file watch would miss the first write).
    private func watchCacheDirectory() {
        let fd = open(VNPaths.cache.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
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
        // VI header style: flat text, every window inline — `❋ 5h 35% 17m | 7d 21% 5d20h`
        HStack(spacing: 12) {
            ForEach(providers, id: \.provider) { p in
                HStack(spacing: 6) {
                    Text(providers.count > 1 ? p.provider : "❋")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VNColor.agent(p.provider.lowercased()))
                    ForEach(Array(p.windows.enumerated()), id: \.offset) { i, w in
                        if i > 0 {
                            Text("|").font(VNFont.sysMono(10.5, .regular))
                                .foregroundStyle(Color.white.opacity(0.18))
                        }
                        windowSegment(w)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .help(helpText)
    }

    private func windowSegment(_ w: ProviderUsage.Window) -> some View {
        HStack(spacing: 4) {
            Text(w.label).font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.88))
            Text("\(Int(w.usedPercentage.rounded()))%")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(usageColor(w.usedPercentage))
            if let resets = w.resetsAt {
                Text(shortRemaining(until: resets)).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.32))
            }
        }
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
