import Foundation

/// Names you give sessions inside the agents. Neither agent sends a rename through its hooks, so the
/// notch reads them from where each one records them:
///  - Claude: a `custom-title` line appended to the session transcript by /rename
///  - Codex:  `thread_name` entries in ~/.codex/session_index.jsonl (latest per id wins)
enum SessionTitles {
    private static let lock = NSLock()
    /// Claude transcripts grow constantly, so only the bytes added since the last look are scanned.
    nonisolated(unsafe) private static var claudeProgress: [String: (offset: UInt64, title: String?)] = [:]
    nonisolated(unsafe) private static var claudePaths: [String: String] = [:]

    static func titles(for sessions: [(id: String, source: String)]) -> [String: String] {
        var out: [String: String] = [:]
        let codexIDs = sessions.filter { $0.source == "codex" }.map(\.id)
        if !codexIDs.isEmpty {
            let index = codexIndex()
            for id in codexIDs { if let t = index[id] { out[id] = t } }
        }
        for s in sessions where s.source == "claude" { if let t = claudeTitle(s.id) { out[s.id] = t } }
        return out
    }

    private static func codexIndex() -> [String: String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/session_index.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = obj["id"] as? String, let name = obj["thread_name"] as? String, !name.isEmpty else { continue }
            map[id] = name
        }
        return map
    }

    private static func claudeTitle(_ sessionID: String) -> String? {
        let fm = FileManager.default
        lock.lock(); var path = claudePaths[sessionID]; lock.unlock()
        if path == nil {
            let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
            for dir in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
                let candidate = root.appendingPathComponent(dir).appendingPathComponent("\(sessionID).jsonl").path
                if fm.fileExists(atPath: candidate) { path = candidate; break }
            }
            guard let found = path else { return nil }
            lock.lock(); claudePaths[sessionID] = found; lock.unlock()
        }
        guard let path, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        lock.lock(); var state = claudeProgress[path] ?? (0, nil); lock.unlock()
        if size < state.offset { state = (0, nil) }          // file was rewritten
        guard size > state.offset else { return state.title }
        try? handle.seek(toOffset: state.offset)
        let marker = Data("\"custom-title\"".utf8)
        var buffer = Data(), read = state.offset
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            buffer.append(chunk); read += UInt64(chunk.count)
            var start = buffer.startIndex
            while let nl = buffer[start...].firstIndex(of: 0x0A) {
                let line = buffer[start..<nl]
                if line.range(of: marker) != nil,
                   let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                   obj["type"] as? String == "custom-title", let t = obj["customTitle"] as? String {
                    state.title = t.isEmpty ? nil : t
                }
                start = buffer.index(after: nl)
            }
            buffer = Data(buffer[start...])
        }
        state.offset = read - UInt64(buffer.count)           // an unfinished last line is re-read next time
        lock.lock(); claudeProgress[path] = state; lock.unlock()
        return state.title
    }
}
