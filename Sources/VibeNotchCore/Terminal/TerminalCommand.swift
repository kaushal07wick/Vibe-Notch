import Foundation

/// Bounded CLI execution, off the UI thread. Steps stop at the first failure.
public enum TerminalCommand {
    public static func run(_ commands: [[String]], timeout: TimeInterval = 5, input: Data? = nil) async -> Bool {
        guard timeout.isFinite, timeout > 0, input == nil || commands.count == 1 else { return false }
        return await Task.detached {
            for argv in commands {
                guard let executable = argv.first else { return false }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = Array(argv.dropFirst())
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin"
                process.environment = env
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                let inputPipe = input.map { _ in Pipe() }
                if let inputPipe {
                    guard fcntl(inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { return false }
                    process.standardInput = inputPipe
                }
                let succeeded = await withCheckedContinuation { continuation in
                    let completion = Completion(continuation)
                    process.terminationHandler = { child in
                        completion.finish(child.terminationReason == .exit && child.terminationStatus == 0)
                    }
                    do { try process.run() } catch {
                        process.terminationHandler = nil
                        completion.finish(false)
                        return
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        guard completion.beginCancellation() else { return }
                        terminate(process) { completion.finish(false) }
                    }
                    if let input, let inputPipe {
                        DispatchQueue.global().async {
                            defer { try? inputPipe.fileHandleForWriting.close() }
                            do { try inputPipe.fileHandleForWriting.write(contentsOf: input) }
                            catch {
                                guard completion.beginCancellation() else { return }
                                terminate(process) { completion.finish(false) }
                            }
                        }
                    }
                }
                guard succeeded else { return false }
            }
            return !commands.isEmpty
        }.value
    }

    private static func terminate(_ process: Process, completion: @escaping @Sendable () -> Void) {
        guard process.isRunning else { completion(); return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            completion()
        }
    }

    /// Completion and timeout race; resume exactly once. Avoid waitUntilExit:
    /// its thread-bound run loop can strand a Swift concurrency task after a
    /// suspension resumes it on another worker thread.
    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?
        private var cancelling = false
        init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
        func beginCancellation() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard continuation != nil, !cancelling else { return false }
            cancelling = true
            return true
        }
        @discardableResult func finish(_ succeeded: Bool) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            let result = succeeded && !cancelling
            lock.unlock()
            pending?.resume(returning: result)
            return pending != nil
        }
    }

    public static func resume(source: String, id: String, cwd: String) -> String? {
        guard ["claude", "codex"].contains(source), !id.isEmpty, !id.hasPrefix("-"),
              cwd.hasPrefix("/"), !id.contains("\0"), !cwd.contains("\0") else { return nil }
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = source == "codex" ? "codex resume" : "claude --resume"
        return "cd \(quote(cwd)) && \(command) \(quote(id))"
    }

    public static func validTTY(_ tty: String) -> Bool {
        let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        return name.hasPrefix("tty") && name.count > 3 && name.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }
}
