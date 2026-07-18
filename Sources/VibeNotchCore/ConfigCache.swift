import Foundation

/// mtime-keyed cache for small JSON config files that get read on hot paths
/// (safelist, policies). A stat per read instead of a read+parse per event.
public final class ConfigCache<T: Sendable>: @unchecked Sendable {
    private let url: URL
    private let parse: @Sendable (Data) -> T?
    private let fallback: T
    private let lock = NSLock()
    private var cached: T?
    private var mtime: Date?

    public init(url: URL, fallback: T, parse: @escaping @Sendable (Data) -> T?) {
        self.url = url
        self.fallback = fallback
        self.parse = parse
    }

    public func get() -> T {
        lock.lock(); defer { lock.unlock() }
        let current = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if let cached, current == mtime { return cached }
        mtime = current
        guard let data = try? Data(contentsOf: url), let parsed = parse(data) else {
            cached = fallback
            return fallback
        }
        cached = parsed
        return parsed
    }

    /// Call after writing the file so the next get() re-reads.
    public func invalidate() {
        lock.lock(); mtime = nil; cached = nil; lock.unlock()
    }
}
