import AppKit
import VibeNotchCore

/// Keeps one reverse tunnel per enabled SSH server alive: remote unix socket →
/// our local IPC socket. Reconnects with backoff; stops cleanly on quit.
/// What a host's tunnel is actually doing right now. The Settings pane used to
/// print "Connected" from the stored `enabled` flag, which says nothing about
/// whether the link is up.
enum TunnelState: Equatable {
    case connecting
    case up(since: Date)
    case retrying(at: Date, reason: String)
    case stopped

    var isUp: Bool { if case .up = self { return true }; return false }
}

@MainActor
final class SSHTunnelManager: ObservableObject {
    @Published private(set) var state: [String: TunnelState] = [:]
    private var processes: [String: Process] = [:]   // host → ssh -N -R
    private var startedAt: [String: Date] = [:]
    private var backoff: [String: TimeInterval] = [:]
    private var stopped = false

    /// A tunnel that survives this long counts as a real connection — shorter
    /// than that and ssh is failing on connect, so the backoff must keep growing.
    private static let stableAfter: TimeInterval = 20

    func start() {
        for server in SSHRemote.load() where server.enabled { launchTunnel(server) }
    }

    func stop() {
        stopped = true
        for p in processes.values { p.terminate() }
        processes.removeAll()
        state = state.mapValues { _ in .stopped }
    }

    /// Deploy the remote client + hooks over SSH, save the server, open its tunnel.
    /// Returns nil on success, else a short error description.
    func addServer(host: String) async -> String? {
        guard let client = Bundle.main.resourceURL?.appendingPathComponent("vibenotch-remote-hook.py"),
              FileManager.default.fileExists(atPath: client.path) else { return "remote client missing from bundle" }

        var remoteHome = ""
        for (exe, args) in SSHRemote.deploySteps(host: host, clientSource: client) {
            let (status, output) = await Self.run(exe, args)
            guard status == 0 else { return "step failed: \(URL(fileURLWithPath: exe).lastPathComponent) — \(output.prefix(200))" }
            if remoteHome.isEmpty, output.contains("/") {
                remoteHome = output.split(separator: "\n").last(where: { $0.hasPrefix("/") }).map(String.init) ?? ""
            }
        }
        guard !remoteHome.isEmpty else { return "could not resolve remote $HOME" }

        var servers = SSHRemote.load().filter { $0.host != host }
        let server = SSHServer(host: host, remoteHome: remoteHome)
        servers.append(server)
        SSHRemote.save(servers)
        launchTunnel(server)
        return nil
    }

    func removeServer(host: String) {
        SSHRemote.save(SSHRemote.load().filter { $0.host != host })
        processes.removeValue(forKey: host)?.terminate()
    }

    // MARK: Tunnel lifecycle

    private func launchTunnel(_ server: SSHServer) {
        guard processes[server.host] == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = SSHRemote.tunnelArguments(for: server, localSocket: VNPaths.socket.path)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.tunnelDied(server) }
        }
        do {
            try p.run()
            processes[server.host] = p
            startedAt[server.host] = Date()
            state[server.host] = .connecting
            // ssh -N never says "the forward is up"; with ExitOnForwardFailure a
            // broken one exits within a second or two. Still alive = connected.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.processes[server.host]?.isRunning == true else { return }
                self.state[server.host] = .up(since: self.startedAt[server.host] ?? Date())
            }
        } catch {
            NSLog("VibeNotch: ssh tunnel launch failed for \(server.host): \(error)")
            state[server.host] = .retrying(at: Date().addingTimeInterval(5), reason: "\(error)")
        }
    }

    private func tunnelDied(_ server: SSHServer) {
        processes.removeValue(forKey: server.host)
        let lived = Date().timeIntervalSince(startedAt[server.host] ?? Date())
        guard !stopped, SSHRemote.load().first(where: { $0.host == server.host })?.enabled == true else {
            state[server.host] = .stopped
            return
        }
        // The reset used to live in launchTunnel, so every relaunch put the
        // delay back to 5s — an unreachable host got a new ssh process every
        // five seconds, forever, and the doubling never took effect.
        if lived >= Self.stableAfter { backoff[server.host] = 5 }
        let delay = min(backoff[server.host] ?? 5, 60)
        backoff[server.host] = min(60, delay * 2)
        state[server.host] = .retrying(at: Date().addingTimeInterval(delay),
                                       reason: lived >= Self.stableAfter ? "link dropped" : "could not connect")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !stopped else { return }
            launchTunnel(server)
        }
    }

    // MARK: Process helper

    private static func run(_ exe: String, _ args: [String]) async -> (Int32, String) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            p.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: (proc.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
            do { try p.run() } catch { cont.resume(returning: (1, "\(error)")) }
        }
    }
}
