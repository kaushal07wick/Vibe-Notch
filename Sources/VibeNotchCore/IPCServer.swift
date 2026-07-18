import Foundation

public enum VNError: Error { case socket(String) }

/// A minimal AF_UNIX/SOCK_STREAM server speaking line-delimited JSON.
/// One thread per connection (volume is tiny). A `request` connection blocks
/// until the app supplies a decision via the handler's completion.
public final class IPCServer: @unchecked Sendable {
    public typealias NotifyHandler = @Sendable (VNInbound) -> Void
    public typealias RequestHandler = @Sendable (UUID, VNInbound, @escaping @Sendable (VNReply) -> Void) -> Void
    public typealias CancelHandler = @Sendable (UUID) -> Void

    private let socketPath: String
    private var listenFD: Int32 = -1
    private let onNotify: NotifyHandler
    private let onRequest: RequestHandler
    private let onCancel: CancelHandler
    private let queue = DispatchQueue(label: "vibenotch.ipc", attributes: .concurrent)

    public init(socketPath: String = VNPaths.socket.path,
                onNotify: @escaping NotifyHandler,
                onRequest: @escaping RequestHandler,
                onCancel: @escaping CancelHandler = { _ in }) {
        self.socketPath = socketPath
        self.onNotify = onNotify
        self.onRequest = onRequest
        self.onCancel = onCancel
    }

    public func start() throws {
        unlink(socketPath)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw VNError.socket("socket() failed") }

        var (addr, len) = makeUnixAddr(socketPath)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0 else { throw VNError.socket("bind() failed errno=\(errno)") }
        guard listen(listenFD, 16) == 0 else { throw VNError.socket("listen() failed errno=\(errno)") }

        queue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                break
            }
            queue.async { [weak self] in self?.handle(fd) }
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        guard let line = readLine(fd),
              let data = line.data(using: .utf8),
              let msg = try? JSONDecoder().decode(VNInbound.self, from: data) else { return }

        switch msg.type {
        case .notify:
            onNotify(msg)
        case .request:
            let id = UUID()
            let sem = DispatchSemaphore(value: 0)
            let box = DecisionBox()
            onRequest(id, msg) { reply in box.decide(reply); sem.signal() }
            // Watch the connection: if the hook dies/times out before a decision,
            // read() returns EOF/error → cancel so the card doesn't linger.
            queue.async {
                var byte: UInt8 = 0
                if read(fd, &byte, 1) <= 0 { box.cancel(); sem.signal() }
            }
            sem.wait()
            if box.isCancelled { onCancel(id); return }
            guard var out = try? JSONEncoder().encode(box.reply) else { return }
            out.append(0x0A)
            _ = out.withUnsafeBytes { write(fd, $0.baseAddress, out.count) }
        }
    }

    /// Read one newline-delimited line (bounded).
    private func readLine(_ fd: Int32) -> String? {
        var buf = [UInt8]()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { break }
            buf.append(byte)
            if buf.count > 1_000_000 { break }
        }
        return buf.isEmpty ? nil : String(decoding: buf, as: UTF8.self)
    }

    /// Thread-safe: whichever of decide()/cancel() wins first sticks.
    private final class DecisionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _reply: VNReply?
        private var _cancelled = false
        func decide(_ r: VNReply) { lock.lock(); if _reply == nil && !_cancelled { _reply = r }; lock.unlock() }
        func cancel() { lock.lock(); if _reply == nil { _cancelled = true }; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
        var reply: VNReply { lock.lock(); defer { lock.unlock() }; return _reply ?? VNReply(decision: .ask) }
    }
}
