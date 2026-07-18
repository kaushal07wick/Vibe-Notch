import Foundation

/// Build a filled `sockaddr_un` for `path` plus its length, for bind()/connect().
/// Capacity is hoisted to a local so we don't read `sun_path` while mutating it.
func makeUnixAddr(_ path: String) -> (sockaddr_un, socklen_t) {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    path.withCString { src in
        withUnsafeMutablePointer(to: &addr.sun_path) { dst in
            dst.withMemoryRebound(to: CChar.self, capacity: cap) { p in
                _ = strncpy(p, src, cap - 1)
            }
        }
    }
    return (addr, socklen_t(MemoryLayout<sockaddr_un>.size))
}
