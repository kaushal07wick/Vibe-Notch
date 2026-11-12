import Foundation

/// The optional browser dashboard is read-only and requires a per-launch key.
/// Host/origin checks reject browser requests made through unrelated domains.
public enum DashboardAccess {
    public enum Route: Equatable, Sendable { case page, state, rejected(Int) }

    public static func route(request: String, token: String, port: UInt16) -> Route {
        let lines = request.components(separatedBy: "\r\n")
        guard let line = lines.first else { return .rejected(400) }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .rejected(400) }
        guard parts[0] == "GET" else { return .rejected(405) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .rejected(400) }
            let key = line[..<colon].lowercased()
            guard headers[key] == nil else { return .rejected(400) }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let hosts = ["127.0.0.1:\(port)", "localhost:\(port)"]
        guard let host = headers["host"], hosts.contains(host) else { return .rejected(403) }
        if let origin = headers["origin"], !hosts.map({ "http://" + $0 }).contains(origin) { return .rejected(403) }
        guard let components = URLComponents(string: String(parts[1])), components.host == nil,
              components.scheme == nil, !token.isEmpty else { return .rejected(403) }
        let keys = components.queryItems?.filter { $0.name == "t" } ?? []
        guard keys.count == 1, keys[0].value == token else { return .rejected(403) }
        switch components.path {
        case "/": return .page
        case "/state.json": return .state
        default: return .rejected(404)
        }
    }
}
