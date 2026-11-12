import Foundation

/// Installs a Claude Code status line that tees `.rate_limits` into our cache —
/// the local, no-API source for the usage header. Wraps any existing status
/// line so the user's own setup keeps working.
public enum StatusLineInstaller {
    static let marker = "vibenotch"
    static var scriptURL: URL { VNPaths.bin.appendingPathComponent("statusline.sh") }
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// True when Claude's status line already routes through our bridge.
    public static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let command = (settings["statusLine"] as? [String: Any])?["command"] as? String
        else { return false }
        return command.contains(scriptURL.path)
    }

    /// Preparing a plan is read-only; Settings reviews it before applying.
    public static func connectionPlan(connecting: Bool, settingsURL: URL? = nil,
                                      scriptURL: URL? = nil) throws -> HookChangePlan {
        let fm = FileManager.default
        let settingsURL = settingsURL ?? Self.settingsURL
        let scriptURL = scriptURL ?? Self.scriptURL
        let before = fm.fileExists(atPath: settingsURL.path) ? try Data(contentsOf: settingsURL) : nil
        var settings: [String: Any]
        if let before {
            guard let root = (try? JSONSerialization.jsonObject(with: before)) as? [String: Any] else {
                throw HookChangePlan.ChangeError.invalidConfiguration(settingsURL.path)
            }
            settings = root
        } else { settings = [:] }
        if let line = settings["statusLine"], !(line is [String: Any]) {
            throw HookChangePlan.ChangeError.invalidConfiguration(settingsURL.path)
        }
        let originalURL = scriptURL.deletingLastPathComponent().appendingPathComponent("statusline-original.json")
        let oldOriginal = fm.fileExists(atPath: originalURL.path) ? try Data(contentsOf: originalURL) : nil
        let oldScript = fm.fileExists(atPath: scriptURL.path) ? try Data(contentsOf: scriptURL) : nil
        let existing = settings["statusLine"] as? [String: Any]
        let ours = (existing?["command"] as? String)?.contains(scriptURL.path) == true
        var changes: [HookChangePlan.FileChange] = []
        if connecting {
            let original: [String: Any]?
            if ours {
                original = oldOriginal.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            } else {
                original = existing
                let saved = try JSONSerialization.data(withJSONObject: existing as Any? ?? NSNull(), options: [.fragmentsAllowed, .sortedKeys])
                changes.append(.init(url: originalURL, before: oldOriginal, after: saved))
            }
            let command = original?["command"] as? String ?? (ours ? currentWrappedCommand(scriptURL: scriptURL) : nil)
            changes.append(.init(url: scriptURL, before: oldScript, after: Data(script(wrapping: command).utf8), executable: true))
            settings["statusLine"] = ["type": "command", "command": scriptURL.path]
        } else if ours {
            if let oldOriginal, let original = try? JSONSerialization.jsonObject(with: oldOriginal, options: [.fragmentsAllowed]) {
                if original is NSNull { settings.removeValue(forKey: "statusLine") }
                else { settings["statusLine"] = original }
            } else if let command = currentWrappedCommand(scriptURL: scriptURL) {
                settings["statusLine"] = ["type": "command", "command": command]
            } else { settings.removeValue(forKey: "statusLine") }
        }
        let after = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if connecting || ours { changes.append(.init(url: settingsURL, before: before, after: after)) }
        return HookChangePlan(agentName: "Claude usage bridge", connecting: connecting, events: ["statusLine"], changes: changes)
    }

    /// The original command we wrapped, recovered from the script itself.
    static func currentWrappedCommand(scriptURL: URL = StatusLineInstaller.scriptURL) -> String? {
        guard let text = try? String(contentsOf: scriptURL, encoding: .utf8),
              let line = text.components(separatedBy: "\n").first(where: { $0.hasPrefix("ORIG=") })
        else { return nil }
        let raw = String(line.dropFirst("ORIG=".count))
        guard raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 else { return nil }
        let unquoted = String(raw.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        return unquoted.isEmpty ? nil : unquoted
    }

    private static func script(wrapping original: String?) -> String {
        let orig = (original ?? "").replacingOccurrences(of: "'", with: "'\\''")
        return """
        #!/bin/sh
        # vibenotch status line — tees Claude's rate limits to the usage cache,
        # then delegates to the user's original status line (or prints a default).
        ORIG='\(orig)'
        input=$(cat)
        printf '%s' "$input" | /usr/bin/python3 -c '
        import json, sys, os
        try:
            d = json.load(sys.stdin)
        except Exception:
            sys.exit(0)
        rl = d.get("rate_limits")
        if rl:
            path = os.path.expanduser("~/.vibenotch/cache/rl-claude.json")
            open(path, "w").write(json.dumps(rl))
        ' 2>/dev/null
        if [ -n "$ORIG" ]; then
            printf '%s' "$input" | /bin/sh -c "$ORIG"
        else
            printf '%s' "$input" | /usr/bin/python3 -c '
        import json, sys
        try:
            d = json.load(sys.stdin)
        except Exception:
            print("Claude"); sys.exit(0)
        model = (d.get("model") or {}).get("display_name") or "Claude"
        ctx = (d.get("context_window") or {}).get("used_percentage")
        print(f"{model} · {int(ctx)}% ctx" if ctx is not None else model)
        '
        fi
        """
    }
}
