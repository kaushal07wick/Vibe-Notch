import Foundation

/// Persists "Always Allow" decisions as permission rules in the agent's
/// settings.json (`permissions.allow`) — the same place Claude Code stores
/// rules it writes itself.
public enum PermissionRules {
    /// Rule string for a tool call. Bash gets a first-token prefix rule
    /// (`Bash(npm:*)`); other tools are allowed wholesale (`WebFetch`).
    public static func rule(tool: String, detail: String?) -> String {
        guard tool == "Bash", let first = detail?
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first, !first.isEmpty else { return tool }
        return "Bash(\(first):*)"
    }

    /// Allow-rules currently in the agent's settings.json.
    public static func listAllow(source: String) -> [String] {
        guard let spec = Agents.byID(source), case .jsonHooks = spec.mechanism,
              let settings = ConfigJSON.read(spec.configFileURL) else { return [] }
        return (settings["permissions"] as? [String: Any])?["allow"] as? [String] ?? []
    }

    /// Remove one allow-rule (the rules-manager menu action).
    public static func removeAllowRule(source: String, rule: String) {
        guard let spec = Agents.byID(source), case .jsonHooks = spec.mechanism,
              var settings = ConfigJSON.read(spec.configFileURL),
              var permissions = settings["permissions"] as? [String: Any],
              var allow = permissions["allow"] as? [String] else { return }
        allow.removeAll { $0 == rule }
        if allow.isEmpty { permissions.removeValue(forKey: "allow") } else { permissions["allow"] = allow }
        if permissions.isEmpty { settings.removeValue(forKey: "permissions") } else { settings["permissions"] = permissions }
        try? ConfigJSON.write(settings, to: spec.configFileURL)
    }

    /// Append the rule to the source agent's settings.json. Claude-schema
    /// agents only; no-op for others. Idempotent.
    public static func addAllowRule(source: String, tool: String, detail: String?) {
        guard let spec = Agents.byID(source), case .jsonHooks = spec.mechanism else { return }
        let url = spec.configFileURL
        guard var settings = ConfigJSON.read(url) else { return }

        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []
        let newRule = rule(tool: tool, detail: detail)
        guard !allow.contains(newRule) else { return }
        allow.append(newRule)
        permissions["allow"] = allow
        settings["permissions"] = permissions

        try? ConfigJSON.write(settings, to: url)
    }
}
