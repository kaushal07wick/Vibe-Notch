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

    public static func installIfNeeded() {
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        let existing = (settings["statusLine"] as? [String: Any])?["command"] as? String
        if existing?.contains(marker) == true {
            try? writeScript(wrapping: currentWrappedCommand()) // refresh script only
            return
        }
        do {
            try writeScript(wrapping: existing)
            settings["statusLine"] = ["type": "command", "command": scriptURL.path]
            let out = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try out.write(to: settingsURL, options: .atomic)
        } catch {
            NSLog("VibeNotch: status line install failed: \(error)")
        }
    }

    /// The original command we wrapped, recovered from the script itself.
    static func currentWrappedCommand() -> String? {
        guard let text = try? String(contentsOf: scriptURL, encoding: .utf8),
              let line = text.components(separatedBy: "\n").first(where: { $0.hasPrefix("ORIG=") })
        else { return nil }
        let raw = String(line.dropFirst("ORIG=".count))
        let unquoted = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        return unquoted.isEmpty ? nil : unquoted
    }

    static func writeScript(wrapping original: String?) throws {
        try VNPaths.ensure()
        let orig = (original ?? "").replacingOccurrences(of: "'", with: "'\\''")
        let script = """
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
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }
}
