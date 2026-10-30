import AppKit
import SwiftUI
import VibeNotchCore

// Session history — past Claude sessions read straight from
// ~/.claude/projects/<dir>/<sessionId>.jsonl. Click one → a terminal opens at
// its cwd running `claude --resume <id>`. No hunting for the command.

struct ResumeEntry: Identifiable {
    let id: String       // session UUID
    let source: String   // "claude" | "codex"
    let cwd: String
    let task: String     // first real user message
    let date: Date
    var folder: String { (cwd as NSString).lastPathComponent }
}

enum SessionHistory {
    /// Newest-first past sessions across Claude AND Codex — every session you've
    /// paused and could resume. Reads only the head of each transcript.
    static func load(limit: Int = 30) -> [ResumeEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Claude: ~/.claude/projects/<dir>/<uuid>.jsonl
        var claude: [(URL, Date)] = []
        let claudeRoot = home.appendingPathComponent(".claude/projects")
        for dir in (try? FileManager.default.contentsOfDirectory(at: claudeRoot, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where f.pathExtension == "jsonl" {
                claude.append((f, mtime(f)))
            }
        }

        // Codex: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (recurse)
        var codex: [(URL, Date)] = []
        let codexRoot = home.appendingPathComponent(".codex/sessions")
        if let en = FileManager.default.enumerator(at: codexRoot, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let f as URL in en where f.lastPathComponent.hasPrefix("rollout-") && f.pathExtension == "jsonl" {
                codex.append((f, mtime(f)))
            }
        }

        // Parse the most-recent `limit` from EACH source, then merge — otherwise
        // a flood of Claude sessions buries an older (but wanted) Codex one.
        func recent(_ files: [(URL, Date)], _ source: String) -> [ResumeEntry] {
            files.sorted { $0.1 > $1.1 }.prefix(limit)
                .compactMap { parse($0.0, date: $0.1, source: source) }
        }
        return (recent(claude, "claude") + recent(codex, "codex"))
            .sorted { $0.date > $1.date }
    }

    private static func mtime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Codex embeds the UUID after the timestamp in the filename:
    /// rollout-2026-03-17T20-27-29-<uuid>.jsonl
    private static func codexUUID(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        // last 5 dash-groups form the UUID
        let parts = name.split(separator: "-")
        return parts.count >= 5 ? parts.suffix(5).joined(separator: "-") : name
    }

    /// cwd + first user message from the head of a transcript (both schemas).
    private static func parse(_ url: URL, date: Date, source: String) -> ResumeEntry? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Codex buries the real user prompt after a huge system/agent preamble;
        // Claude's is near the top. Read enough to reach it either way.
        let head = handle.readData(ofLength: source == "codex" ? 512_000 : 32_768)
        guard let text = String(data: head, encoding: .utf8) else { return nil }

        var cwd: String?
        var task: String?
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if cwd == nil { cwd = obj["cwd"] as? String ?? (obj["payload"] as? [String: Any])?["cwd"] as? String }
            if task == nil {
                let msg = (obj["message"] as? [String: Any]) ?? (obj["payload"] as? [String: Any]) ?? obj
                let role = (msg["role"] as? String) ?? (obj["type"] as? String)
                // Claude: content is a String; Codex: content can be an array of parts
                var textContent: String?
                if let c = msg["content"] as? String { textContent = c }
                else if let parts = msg["content"] as? [[String: Any]] {
                    textContent = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
                }
                if role == "user", let content = textContent {
                    let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty && !clean.hasPrefix("<") { task = String(clean.prefix(90)) }
                }
            }
            if cwd != nil && task != nil { break }
        }
        guard let task else { return nil }
        let id = source == "codex" ? codexUUID(url) : url.deletingPathExtension().lastPathComponent
        return ResumeEntry(id: id, source: source, cwd: cwd ?? NSHomeDirectory(), task: task, date: date)
    }

    /// Terminal accepts the resume command; agent startup remains visible there.
    @MainActor @discardableResult
    static func resume(_ entry: ResumeEntry) -> Bool {
        guard let cmd = TerminalCommand.resume(source: entry.source, id: entry.id, cwd: entry.cwd) else { return false }
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        return VNAppleScript.run("""
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        return "ok"
        """, purpose: "resuming the session in Terminal") == "ok"
    }

}

/// The history panel — replaces the card area while open.
struct HistoryList: View {
    let entries: [ResumeEntry]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("HISTORY").font(VNFont.sysMono(10, .semibold)).tracking(1.4)
                    .foregroundStyle(VNColor.paper.opacity(0.55))
                Text("click to resume").font(VNFont.ui(10))
                    .foregroundStyle(VNColor.faint)
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(VNFont.ui(9, .semibold))
                        .foregroundStyle(VNColor.muted)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close history")
            }
            .padding(.horizontal, 20).padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1) }

            // today's recap + lifetime mascot level
            recap.padding(.horizontal, 20)

            if entries.isEmpty {
                Text("No past sessions found.")
                    .font(VNFont.ui(11)).foregroundStyle(VNColor.faint)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { HistoryRow(entry: $0, close: close) }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            }
        }
        .padding(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
        .frame(width: CGFloat(VNSettings.panelWidth), alignment: .leading)
    }
}

extension HistoryList {
    var recap: some View {
        let today = StatsLog.today()
        let level = StatsLog.mascotLevel(totals: StatsLog.totals())
        let bits = [
            today["sessions"].map { "\($0) session\($0 == 1 ? "" : "s")" },
            today["approved"].map { "\($0) approved" },
            today["autoApproved"].map { "\($0) auto" },
            today["replies"].map { "\($0) repl\($0 == 1 ? "y" : "ies")" },
        ].compactMap { $0 }
        return HStack(spacing: 8) {
            PixelGhost(mood: .idle, px: 1.5)
            Text(bits.isEmpty ? "Quiet day so far." : "Today: " + bits.joined(separator: " · "))
                .font(VNFont.sysMono(10, .medium)).foregroundStyle(VNColor.muted)
            Spacer(minLength: 8)
            Text("Lv.\(level)").font(VNFont.sysMono(10, .semibold))
                .foregroundStyle(VNColor.paper.opacity(0.4))
        }
        .padding(.vertical, 6)
    }
}

private struct HistoryRow: View {
    let entry: ResumeEntry
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            if SessionHistory.resume(entry) { close() }
        } label: {
            HStack(alignment: .center, spacing: 11) {
                SessionGlyph(tint: SessionGlyph.tint(entry.folder))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.task)
                        .font(VNFont.ui(12))
                        .foregroundStyle(VNColor.text.opacity(0.92))
                        .lineLimit(1).truncationMode(.tail)
                    HStack(spacing: 5) {
                        AgentIcon(source: entry.source, size: 11)
                        Text(entry.folder)
                            .font(VNFont.sysMono(10, .semibold))
                            .foregroundStyle(SessionGlyph.tint(entry.folder).opacity(0.9))
                        Text("· \(ageString(entry.date))")
                            .font(VNFont.sysMono(10, .medium))
                            .foregroundStyle(VNColor.faint)
                    }
                }
                Spacer(minLength: 8)
                ResumeAffordance(active: hovering)
            }
            .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(hovering ? 0.055 : 0))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help("\(entry.cwd)\n\(entry.source == "codex" ? "codex resume" : "claude --resume") \(entry.id)")
    }
}

/// The resume control — pixel play triangle + mono label, house style.
/// Dim glyph at rest, an amber `resume ▶` pill on hover (like the ^G pill).
private struct ResumeAffordance: View {
    let active: Bool
    private static let amber = Color(hex: 0xF0B43C)

    var body: some View {
        if active {
            HStack(spacing: 5) {
                Text("resume").font(VNFont.sysMono(9.5, .semibold))
                Image(systemName: "play.fill").font(.system(size: 8))
            }
            .foregroundStyle(Self.amber)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Self.amber.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Self.amber.opacity(0.35)))
        } else {
            Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(VNColor.paper.opacity(0.28))
                .padding(.trailing, 3)
        }
    }
}

/// A pixel-art play/resume triangle, drawn to match the notch glyph language.
struct PixelPlay: View {
    var color: Color
    var px: CGFloat = 2

    private static let grid = [
        "o....",
        "ooo..",
        "ooooo",
        "ooo..",
        "o....",
    ]

    var body: some View {
        Canvas { c, _ in
            for (y, row) in Self.grid.enumerated() {
                for (x, ch) in row.enumerated() where ch == "o" {
                    c.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px,
                                       width: px, height: px)), with: .color(color))
                }
            }
        }
        .frame(width: 5 * px, height: 5 * px)
    }
}

/// A pixel chat bubble — one saved conversation with an agent. Tinted per
/// project from a muted, paper-friendly palette so repeats group at a glance.
struct SessionGlyph: View {
    let tint: Color

    private static let palette: [Color] = [
        Color(hex: 0xC77E52), Color(hex: 0x7FA36B), Color(hex: 0x7189B8),
        Color(hex: 0xBFA05A), Color(hex: 0x9B7FA8), Color(hex: 0x5F958D),
    ]

    static func tint(_ name: String) -> Color {
        var h: UInt32 = 5381
        for b in name.utf8 { h = (h << 5) &+ h &+ UInt32(b) }
        return palette[Int(h % UInt32(palette.count))]
    }

    var body: some View {
        Circle().fill(tint).frame(width: 8, height: 8).frame(width: 18)
    }
}
