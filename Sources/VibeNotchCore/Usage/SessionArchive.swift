import Foundation

/// Append-only archive of finished sessions (durations + token totals across
/// ALL agents) — complements the UI's Claude-transcript history browser.
public struct ArchivedSession: Codable, Sendable {
    public var sessionId: String
    public var source: String
    public var folder: String?
    public var task: String?
    public var host: String?
    public var startedAt: Date
    public var endedAt: Date
    public var tokensIn: Int
    public var tokensOut: Int

    public init(sessionId: String, source: String, folder: String?, task: String?,
                host: String?, startedAt: Date, endedAt: Date, tokensIn: Int, tokensOut: Int) {
        self.sessionId = sessionId
        self.source = source
        self.folder = folder
        self.task = task
        self.host = host
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
    }
}

public enum SessionArchive {
    public static var url: URL { VNPaths.data.appendingPathComponent("history.jsonl") }

    public static func append(_ entry: ArchivedSession) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        let line = data + Data("\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    /// Newest-first, bounded.
    public static func load(limit: Int = 100) -> [ArchivedSession] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").suffix(limit).reversed().compactMap {
            decoder.decode(ArchivedSession.self, from: Data($0.utf8)) as ArchivedSession?
        }
    }
}

private extension JSONDecoder {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decode(type, from: data) as T
    }
}
