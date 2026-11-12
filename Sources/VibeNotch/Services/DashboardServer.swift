import Foundation
import Network
import VibeNotchCore

/// Optional read-only, key-protected dashboard on the loopback interface.
@MainActor
final class DashboardServer {
    private var listener: NWListener?
    private var port: UInt16 = 0
    private let token = UUID().uuidString
    var stateProvider: @MainActor () async -> String = { "{}" }
    var authorizedURL: String { "http://127.0.0.1:\(port)/?t=\(token)" }

    func start(port: UInt16) {
        stop()
        guard port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        guard let listener = try? NWListener(using: params) else {
            NSLog("VibeNotch: dashboard failed to bind :%d", port)
            return
        }
        self.port = port
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            Task { @MainActor in self?.receive(connection, buffer: Data()) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        }
        listener.start(queue: .main)
        self.listener = listener
        NSLog("VibeNotch: read-only dashboard on 127.0.0.1:%d", port)
    }

    func stop() { listener?.cancel(); listener = nil; port = 0 }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - buffer.count) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var bytes = buffer
                if let data { bytes.append(data) }
                if bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                    await self.respond(connection, request: String(decoding: bytes, as: UTF8.self))
                } else if complete || error != nil || bytes.count >= 8192 { connection.cancel() }
                else { self.receive(connection, buffer: bytes) }
            }
        }
    }

    private func respond(_ connection: NWConnection, request: String) async {
        let status: Int, body: String, type: String
        switch DashboardAccess.route(request: request, token: token, port: port) {
        case .page: status = 200; body = Self.page; type = "text/html; charset=utf-8"
        case .state: status = 200; body = await stateProvider(); type = "application/json"
        case .rejected(let code): status = code; body = #"{"ok":false,"error":"request rejected"}"#; type = "application/json"
        }
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "Error"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    static let page = """
    <!doctype html><meta charset="utf-8"><title>Vibe Notch</title>
    <style>
      body{font:14px -apple-system,sans-serif;background:#0d0d0f;color:#f1ead9;margin:2rem auto;max-width:640px;padding:0 1rem}
      h1{font-size:18px}.row{padding:.8rem;border-radius:10px;background:#ffffff10;margin:.5rem 0;white-space:pre-wrap;overflow-wrap:anywhere}
      .pending{border:1px solid #e7a76266}small{opacity:.55}
    </style>
    <h1>Vibe Notch <small>Read-only</small></h1><div id="out">Loading…</div>
    <script>
    const out=document.getElementById('out');
    const key=new URLSearchParams(location.search).get('t')||'';
    async function tick(){try{
      const response=await fetch('/state.json?t='+encodeURIComponent(key),{cache:'no-store'});
      if(!response.ok)throw Error('Access expired. Reopen the dashboard from Vibe Notch.');
      const s=await response.json();const rows=[];
      for(const p of s.pending||[]){const e=document.createElement('div');e.className='row pending';e.textContent=(p.tool||'Request')+' · awaiting approval\\n'+(p.detail||'');rows.push(e)}
      for(const x of s.sessions||[]){const e=document.createElement('div');e.className='row';e.textContent=(x.folder||x.sessionId)+' · '+x.source+' · '+x.event+'\\n'+(x.task||'');rows.push(e)}
      if(!rows.length){const e=document.createElement('div');e.className='row';e.textContent='No recent sessions';rows.push(e)}
      out.replaceChildren(...rows);
    }catch(e){out.textContent=e.message||'App not reachable'}}
    tick();setInterval(tick,2000);
    </script>
    """
}
