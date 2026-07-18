import Foundation

/// Per-project trust policy, matched by cwd prefix. Lets ~/work be strict
/// while ~/personal stays relaxed. Missing file = everything allowed.
public struct Policy: Codable, Sendable, Equatable {
    public var prefix: String        // "~/Desktop/workspace/work"
    public var safeList: Bool        // auto-approve safe-listed commands here?
    public var bypass: Bool          // allow session Bypass here?
    public var alwaysAllow: Bool     // allow persisting always-allow rules here?

    public init(prefix: String, safeList: Bool = true, bypass: Bool = true, alwaysAllow: Bool = true) {
        self.prefix = prefix
        self.safeList = safeList
        self.bypass = bypass
        self.alwaysAllow = alwaysAllow
    }
}

public enum Policies {
    public static var url: URL { VNPaths.data.appendingPathComponent("policies.json") }

    public static func load() -> [Policy] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Policy].self, from: data) else { return [] }
        return list
    }

    /// Longest-prefix match wins; no match = permissive default.
    public static func policy(for cwd: String?, in policies: [Policy]) -> Policy {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let cwd else { return Policy(prefix: "") }
        let matches = policies.filter { cwd.hasPrefix($0.prefix.replacingOccurrences(of: "~", with: home)) }
        return matches.max { $0.prefix.count < $1.prefix.count } ?? Policy(prefix: "")
    }
}
