import Foundation

/// A remote server running agents whose events tunnel back to this Mac.
public struct SSHServer: Codable, Sendable, Identifiable, Equatable {
    public var host: String        // "user@server" (key-based auth required)
    public var remoteHome: String  // resolved $HOME on the server, set at deploy
    public var enabled: Bool
    public var id: String { host }

    public init(host: String, remoteHome: String, enabled: Bool = true) {
        self.host = host
        self.remoteHome = remoteHome
        self.enabled = enabled
    }

    public var remoteSocketPath: String { "\(remoteHome)/.vibenotch/vibenotch.sock" }
}

/// Server list persistence + ssh/scp command builders. The app owns the
/// long-lived tunnel processes; everything here is pure and testable.
public enum SSHRemote {
    static var configURL: URL { VNPaths.data.appendingPathComponent("ssh-servers.json") }

    public static func load() -> [SSHServer] {
        guard let data = try? Data(contentsOf: configURL),
              let servers = try? JSONDecoder().decode([SSHServer].self, from: data) else { return [] }
        return servers
    }

    public static func save(_ servers: [SSHServer]) {
        if let data = try? JSONEncoder().encode(servers) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    /// Baseline ssh options: key auth only, fast dead-peer detection.
    static let sshOptions: [String] = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "ServerAliveInterval=15",
        "-o", "ServerAliveCountMax=2",
    ]

    /// Long-lived reverse tunnel: remote unix socket → our local socket.
    /// `StreamLocalBindUnlink` lets sshd replace a stale socket on reconnect.
    public static func tunnelArguments(for server: SSHServer, localSocket: String) -> [String] {
        sshOptions + [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StreamLocalBindUnlink=yes",
            "-R", "\(server.remoteSocketPath):\(localSocket)",
            server.host,
        ]
    }

    /// One-time deploy steps: resolve $HOME, push the client, install hooks.
    /// Returned as (executable, arguments) pairs run in order.
    public static func deploySteps(host: String, clientSource: URL) -> [(String, [String])] {
        [
            ("/usr/bin/ssh", sshOptions + [host, "mkdir -p ~/.vibenotch && echo $HOME"]),
            ("/usr/bin/scp", sshOptions + [clientSource.path, "\(host):.vibenotch/vibenotch-hook.py"]),
            ("/usr/bin/ssh", sshOptions + [host, "python3 ~/.vibenotch/vibenotch-hook.py --install claude"]),
        ]
    }
}
