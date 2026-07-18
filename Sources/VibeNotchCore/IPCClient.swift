import Foundation

/// Connects to the app's Unix socket and sends one line-delimited JSON message.
/// Fail-open by contract: any failure returns nil so the hook never blocks the agent.
public enum IPCClient {
    /// Send `msg`. For `.request`, block for the reply and return the decision.
    /// Returns nil for notify, or on any failure.
    public static func send(_ msg: VNInbound,
                            socketPath: String = VNPaths.socket.path,
                            timeout: TimeInterval = 86_400) -> VNDecision? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var (addr, len) = makeUnixAddr(socketPath)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard connected == 0 else { return nil }

        guard var payload = try? JSONEncoder().encode(msg) else { return nil }
        payload.append(0x0A)
        let wrote = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }
        guard wrote == payload.count else { return nil }

        guard msg.type == .request else { return nil }

        // Bound the wait so a dead/stuck app can't hang the agent forever.
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buf = [UInt8]()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buf.append(byte)
            if buf.count > 4096 { break }
        }
        guard let reply = try? JSONDecoder().decode(VNReply.self, from: Data(buf)) else { return nil }
        return reply.decision
    }
}
