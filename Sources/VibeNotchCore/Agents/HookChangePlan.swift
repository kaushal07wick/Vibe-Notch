import Foundation

/// A concrete, reviewed set of local file changes. Preparing a plan never writes.
public struct HookChangePlan: Sendable {
    public struct FileChange: Sendable {
        public let url: URL
        public let before: Data?
        public let after: Data?
        public let executable: Bool
        public let isText: Bool

        public init(url: URL, before: Data?, after: Data?, executable: Bool = false, isText: Bool = true) {
            self.url = url; self.before = before; self.after = after
            self.executable = executable; self.isText = isText
        }
    }
    public let agentName: String
    public let connecting: Bool
    public let events: [String]
    public let changes: [FileChange]

    public init(agentName: String, connecting: Bool, events: [String], changes: [FileChange]) {
        self.agentName = agentName; self.connecting = connecting; self.events = events
        self.changes = changes.filter { $0.before != $0.after || ($0.executable && !FileManager.default.isExecutableFile(atPath: $0.url.path)) }
    }

    public var reviewText: String {
        var sections = ["\(connecting ? "Configure" : "Remove") Vibe Notch hooks for \(agentName).",
                        "Events: " + events.joined(separator: ", "),
                        "Existing files are backed up before any change. Other integrations are preserved."]
        for change in changes {
            var lines = [change.url.path]
            if change.isText {
                let old = String(decoding: change.before ?? Data(), as: UTF8.self).components(separatedBy: "\n")
                let new = String(decoding: change.after ?? Data(), as: UTF8.self).components(separatedBy: "\n")
                for difference in new.difference(from: old) {
                    switch difference {
                    case .remove(_, let line, _): lines.append("− " + line)
                    case .insert(_, let line, _): lines.append("+ " + line)
                    }
                }
            } else { lines.append(change.after == nil ? "Remove helper" : "Install bundled helper") }
            sections.append(lines.joined(separator: "\n"))
        }
        if changes.isEmpty { sections.append("No file changes are needed.") }
        return sections.joined(separator: "\n\n")
    }

    /// Check every reviewed input first, then make all backups before the first
    /// write. A changed config or failed backup leaves all target files alone.
    @discardableResult public func apply() throws -> [URL] {
        let fm = FileManager.default
        for change in changes {
            let current = fm.fileExists(atPath: change.url.path) ? try Data(contentsOf: change.url) : nil
            guard current == change.before else { throw ChangeError.changedSinceReview(change.url.path) }
        }
        let suffix = ".vibenotch-\(UUID().uuidString).bak"
        var backups: [URL] = []
        for change in changes where change.before != nil {
            let backup = URL(fileURLWithPath: change.url.path + suffix)
            try fm.copyItem(at: change.url, to: backup)
            backups.append(backup)
        }
        var applied: [FileChange] = []
        do {
            for change in changes {
                applied.append(change)
                try fm.createDirectory(at: change.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let data = change.after {
                    try data.write(to: change.url, options: .atomic)
                    if change.executable { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: change.url.path) }
                } else if fm.fileExists(atPath: change.url.path) { try fm.removeItem(at: change.url) }
            }
        } catch {
            // Restore only files this plan wrote, leaving the backups available.
            for change in applied.reversed() {
                if let before = change.before { try? before.write(to: change.url, options: .atomic) }
                else { try? fm.removeItem(at: change.url) }
            }
            throw error
        }
        return backups
    }

    public enum ChangeError: LocalizedError {
        case changedSinceReview(String)
        case invalidConfiguration(String)
        case missingResource(String)
        public var errorDescription: String? {
            switch self {
            case .changedSinceReview(let path): return "\(path) changed since the preview. Review a fresh plan before applying."
            case .invalidConfiguration(let path): return "\(path) is not a valid configuration. It has been left unchanged."
            case .missingResource(let path): return "The bundled helper is missing: \(path). Rebuild or reinstall Vibe Notch."
            }
        }
    }
}

public struct HookConnectionHealth: Sendable {
    public enum State: String, Sendable { case notConnected, needsRepair, configured }
    public let state: State
    public let issues: [String]
    public let installedEvents: [String]
    public var summary: String {
        switch state {
        case .notConnected: return "Not connected"
        case .needsRepair: return "Needs repair"
        case .configured: return "Configured"
        }
    }
}
