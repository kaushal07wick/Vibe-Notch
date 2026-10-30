import Foundation
import Network

/// Localhost-only web dashboard: GET / renders a tiny auto-refreshing page,
/// GET /state.json returns the same JSON the CLI's `list` gives. Off by
/// default; never binds beyond 127.0.0.1 (local-first stays true).
@MainActor
final class DashboardServer {
    private var listener: NWListener?
    var stateProvider: @MainActor () async -> String = { "{}" }
    /// Handles /approve /deny /approve_all (phone taps via ntfy actions).
    var actionHandler: @MainActor (String) async -> String = { _ in #"{"ok":false}"# }

    func start(port: UInt16) {
        stop()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1",
                                                           port: NWEndpoint.Port(rawValue: port)!)
        guard let listener = try? NWListener(using: params) else {
            NSLog("VibeNotch: dashboard failed to bind :\(port)")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                Task { @MainActor in await self?.respond(connection, request: request) }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        // The token only exists in this process — log it so `curl` scripting
        // against /approve is possible without digging it out of memory.
        NSLog("VibeNotch: dashboard on \(authorizedURL)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Per-launch secret. Binding to loopback is not access control: any page in
    /// any browser on this Mac can fire `<img src="http://127.0.0.1:4141/approve">`
    /// and approve whatever an agent is asking for. State-changing paths need the
    /// token; the read-only page and /state.json stay open so the dashboard works
    /// by just typing the address.
    private let token = UUID().uuidString

    /// The dashboard URL to hand a human — carries the token so its buttons work.
    var authorizedURL: String { "http://127.0.0.1:\(VNSettings.dashboardPort)/?t=\(token)" }

    private func query(_ path: String, _ key: String) -> String? {
        guard let q = path.split(separator: "?").dropFirst().first else { return nil }
        for pair in q.split(separator: "&") where pair.hasPrefix("\(key)=") {
            return String(pair.dropFirst(key.count + 1))
        }
        return nil
    }

    private func respond(_ connection: NWConnection, request: String) async {
        let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let route = path.split(separator: "?").first.map(String.init) ?? "/"
        var status = "200 OK"
        let (body, type): (String, String)
        if route.hasPrefix("/state") {
            (body, type) = (await stateProvider(), "application/json")
        } else if ["/approve", "/deny", "/approve_all", "/undo"].contains(route) {
            if query(path, "t") == token {
                (body, type) = (await actionHandler(String(route.dropFirst())), "application/json")
            } else {
                status = "403 Forbidden"
                (body, type) = (#"{"ok":false,"error":"bad or missing token"}"#, "application/json")
            }
        } else {
            (body, type) = (Self.page, "text/html; charset=utf-8")
        }
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(type)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// One self-contained page; polls /state.json every 2s. Read-only — the
    /// state-changing routes are token-gated and reached from the ntfy actions.
    static let page = """
    <!doctype html><meta charset="utf-8"><title>Vibe Notch</title>
    <style>
      body{font:14px -apple-system,sans-serif;background:#0d0d0f;color:#f1ead9;margin:2rem auto;max-width:640px;padding:0 1rem}
      h1{font-size:18px} .row{padding:.6rem .8rem;border-radius:10px;background:#ffffff10;margin:.5rem 0}
      .pend{background:#f4a4a422;border:1px solid #f4a4a455} small{opacity:.55}
      .tag{font:11px ui-monospace;background:#ffffff14;border-radius:999px;padding:.1rem .5rem;margin-left:.4rem}
    </style>
    <h1>Vibe Notch <small id="n"></small></h1><div id="out">loading…</div>
    <script>
    async function tick(){try{
      const s = await (await fetch('/state.json')).json();
      const pend=(s.pending||[]).map(p=>`<div class="row pend"><b>${p.tool}</b> awaiting approval<br><code>${p.detail}</code></div>`).join('');
      const sess=(s.sessions||[]).map(x=>`<div class="row"><b>${x.folder||x.sessionId}</b><span class="tag">${x.source}</span><span class="tag">${x.event}</span><br><small>${x.task||''}</small></div>`).join('');
      document.getElementById('out').innerHTML=(pend+sess)||'<div class="row">no active sessions</div>';
      document.getElementById('n').textContent=new Date().toLocaleTimeString();
    }catch(e){document.getElementById('out').textContent='app not reachable'}}
    tick();setInterval(tick,2000);
    </script>
    """
}
