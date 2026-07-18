import Foundation

/// Connects to the app's Unix socket and sends one line-delimited JSON message.
/// Fail-open by contract: any failure returns nil so callers never block agents.
public enum IPCClient {
    /// Send `msg`. For `.request`, block for the reply and return it.
    /// Returns nil for notify, or on any failure.
    public static func send(_ msg: VNInbound,
                            socketPath: String = VNPaths.socket.path,
                            timeout: TimeInterval = 86_400) -> VNReply? {
        let expectReply = msg.type == .request
        guard let data = sendRaw(msg, socketPath: socketPath,
                                 timeout: timeout, expectReply: expectReply),
              expectReply else { return nil }
        return try? JSONDecoder().decode(VNReply.self, from: data)
    }

    /// Send a control command; returns the server's one-line JSON reply.
    public static func sendControl(_ msg: VNInbound,
                                   socketPath: String = VNPaths.socket.path,
                                   timeout: TimeInterval = 30) -> String? {
        guard let data = sendRaw(msg, socketPath: socketPath,
                                 timeout: timeout, expectReply: true) else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: shared transport

    /// Write one JSON line; optionally read one line back (bounded).
    private static func sendRaw(_ msg: VNInbound, socketPath: String,
                                timeout: TimeInterval, expectReply: Bool) -> Data? {
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
        guard expectReply else { return Data() }

        // Bound the wait so a dead/stuck app can't hang the caller forever.
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buf = [UInt8]()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buf.append(byte)
            if buf.count > 1_000_000 { break }
        }
        return buf.isEmpty ? nil : Data(buf)
    }
}
