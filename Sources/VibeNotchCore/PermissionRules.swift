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

    /// Append the rule to the source agent's settings.json. Claude-schema
    /// agents only; no-op for others. Idempotent.
    public static func addAllowRule(source: String, tool: String, detail: String?) {
        guard let spec = Agents.byID(source), case .jsonHooks = spec.mechanism else { return }
        let url = spec.configFileURL
        guard let data = try? Data(contentsOf: url),
              var settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []
        let newRule = rule(tool: tool, detail: detail)
        guard !allow.contains(newRule) else { return }
        allow.append(newRule)
        permissions["allow"] = allow
        settings["permissions"] = permissions

        if let out = try? JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? out.write(to: url, options: .atomic)
        }
    }
}
