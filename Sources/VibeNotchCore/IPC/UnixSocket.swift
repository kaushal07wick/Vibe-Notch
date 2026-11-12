import Foundation

func validUnixSocketPath(_ path: String) -> Bool {
    !path.utf8.contains(0) && path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path)
}

func suppressBrokenPipeSignal(_ fd: Int32) {
    var enabled: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))
}

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
