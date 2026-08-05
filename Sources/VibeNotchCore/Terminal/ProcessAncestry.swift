import Darwin
import Foundation

/// Who launched us, and on which tty — read straight from the kernel.
///
/// This runs on EVERY hook event, on the blocking approval path. The previous
/// version shelled out to `ps` once per ancestor (up to 14 spawns, ~215ms);
/// a single `ps -ax` snapshot was no better (~140ms on a 668-process machine).
/// `sysctl` + `proc_pidpath` are the same data in microseconds, no subprocess.
public enum ProcessAncestry {
    public struct Entry: Equatable, Sendable {
        public let pid: Int32
        public let ppid: Int32
        /// "ttys014", or nil when the process has no controlling terminal.
        public let tty: String?
        /// Full executable path, matching what `ps -o comm=` used to return.
        public let path: String

        public init(pid: Int32, ppid: Int32, tty: String?, path: String) {
            self.pid = pid; self.ppid = ppid; self.tty = tty; self.path = path
        }
    }

    /// The ancestor chain starting at `pid`, nearest first. Stops at init, at a
    /// pid that has gone away, or after `limit` steps.
    public static func walk(from pid: Int32, limit: Int = 8) -> [Entry] {
        var out: [Entry] = []
        var current = pid
        while out.count < limit, current > 1, let entry = info(for: current) {
            out.append(entry)
            current = entry.ppid
        }
        return out
    }

    /// One process's ppid + tty + executable path.
    static func info(for pid: Int32) -> Entry? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let ok = sysctl(&mib, UInt32(mib.count), &proc, &size, nil, 0) == 0 && size > 0
        guard ok else { return nil }

        // e_tdev is NODEV ((dev_t)-1) when there's no controlling terminal.
        let dev = proc.kp_eproc.e_tdev
        var tty: String?
        if dev != dev_t(bitPattern: ~0), let name = devname(dev, S_IFCHR) {
            tty = String(cString: name)
        }

        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let written = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        // proc_pidpath fails for processes we can't inspect; p_comm still names it.
        let path = written > 0
            ? buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            : withUnsafeBytes(of: proc.kp_proc.p_comm) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
        return Entry(pid: pid, ppid: proc.kp_eproc.e_ppid, tty: tty, path: path)
    }
}
