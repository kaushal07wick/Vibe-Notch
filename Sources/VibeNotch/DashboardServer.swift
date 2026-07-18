import Foundation
import Network

/// Localhost-only web dashboard: GET / renders a tiny auto-refreshing page,
/// GET /state.json returns the same JSON the CLI's `list` gives. Off by
/// default; never binds beyond 127.0.0.1 (local-first stays true).
@MainActor
final class DashboardServer {
    private var listener: NWListener?
    var stateProvider: @MainActor () -> String = { "{}" }

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
                Task { @MainActor in self?.respond(connection, request: request) }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func respond(_ connection: NWConnection, request: String) {
        let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let (body, type): (String, String) = path.hasPrefix("/state")
            ? (stateProvider(), "application/json")
            : (Self.page, "text/html; charset=utf-8")
        let response = """
        HTTP/1.1 200 OK\r
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

    /// One self-contained page; polls /state.json every 2s.
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
