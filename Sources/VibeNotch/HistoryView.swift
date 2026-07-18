import AppKit
import SwiftUI

// Session history — past Claude sessions read straight from
// ~/.claude/projects/<dir>/<sessionId>.jsonl. Click one → a terminal opens at
// its cwd running `claude --resume <id>`. No hunting for the command.

struct ResumeEntry: Identifiable {
    let id: String       // session UUID (filename)
    let cwd: String
    let task: String     // first real user message
    let date: Date
    var folder: String { (cwd as NSString).lastPathComponent }
}

enum SessionHistory {
    /// Newest-first past sessions across all Claude projects. Reads only the
    /// head of each transcript, so a big history stays cheap.
    static func load(limit: Int = 15) -> [ResumeEntry] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil) else { return [] }

        var files: [(url: URL, date: Date)] = []
        for dir in dirs {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for f in items where f.pathExtension == "jsonl" {
                let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                files.append((f, date))
            }
        }
        files.sort { $0.date > $1.date }

        var out: [ResumeEntry] = []
        for (url, date) in files.prefix(limit * 2) { // slack for empty transcripts
            guard let entry = parse(url, date: date) else { continue }
            out.append(entry)
            if out.count == limit { break }
        }
        return out
    }

    /// cwd + first user message from the head of a transcript.
    private static func parse(_ url: URL, date: Date) -> ResumeEntry? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 32_768)
        guard let text = String(data: head, encoding: .utf8) else { return nil }

        var cwd: String?
        var task: String?
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if cwd == nil { cwd = obj["cwd"] as? String }
            if task == nil {
                let msg = (obj["message"] as? [String: Any]) ?? obj
                let role = (msg["role"] as? String) ?? (obj["type"] as? String)
                if role == "user", let content = msg["content"] as? String {
                    let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty && !clean.hasPrefix("<") { task = String(clean.prefix(90)) }
                }
            }
            if cwd != nil && task != nil { break }
        }
        guard let cwd, let task else { return nil }
        return ResumeEntry(id: url.deletingPathExtension().lastPathComponent,
                            cwd: cwd, task: task, date: date)
    }

    /// Open a terminal at the session's cwd and resume it.
    /// ponytail: Terminal.app via AppleScript — works everywhere; routing to the
    /// user's preferred terminal (Ghostty/iTerm) via TerminalControl is backend's
    /// promotion path.
    static func resume(_ entry: ResumeEntry) {
        let cmd = "cd \(shellQuote(entry.cwd)) && claude --resume \(entry.id)"
        let script = """
        tell application "Terminal"
            activate
            do script "\(cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            try? p.run()
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
                Text("click to resume").font(.system(size: 10))
                    .foregroundStyle(VNColor.faint)
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(VNColor.muted)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1) }

            if entries.isEmpty {
                Text("No past sessions found.")
                    .font(.system(size: 11)).foregroundStyle(VNColor.faint)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { HistoryRow(entry: $0, close: close) }
                    }
                }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            }
        }
        .padding(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
        .frame(width: 620, alignment: .leading)
    }
}

private struct HistoryRow: View {
    let entry: ResumeEntry
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            SessionHistory.resume(entry)
            close()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11)).foregroundStyle(VNColor.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(entry.folder) · \(entry.task)")
                        .font(.system(size: 11.8, weight: .semibold))
                        .foregroundStyle(VNColor.text)
                        .lineLimit(1).truncationMode(.tail)
                    Text(entry.cwd).font(VNFont.sysMono(9.5, .regular))
                        .foregroundStyle(VNColor.faint).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(ageString(entry.date)).font(VNFont.sysMono(10, .medium))
                    .foregroundStyle(VNColor.paper.opacity(0.45))
                if hovering {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(VNColor.go)
                }
            }
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(hovering ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help("Resume: claude --resume \(entry.id)")
    }
}
