import AppKit
import SwiftUI

// Links an agent surfaces (dev servers, artifacts, files it built) become
// clickable chips in the notch — click → opens in the browser.

enum LinkFinder {
    /// URLs + browser-viewable local files found in a block of agent text.
    /// Deduped, capped, order preserved.
    static func links(in text: String?, max: Int = 3) -> [URL] {
        guard let text, !text.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [URL] = []

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        for m in detector?.matches(in: text, range: range) ?? [] {
            guard let url = m.url, ["http", "https"].contains(url.scheme ?? "") else { continue }
            if seen.insert(url.absoluteString).inserted { out.append(url) }
            if out.count == max { return out }
        }
        // local files a browser can show (the agent "created it locally")
        for m in text.matching(#"(?<=^|[\s"'`(])(/[^\s"'`()]+\.(?:html?|pdf|png|jpe?g|gif|webp|svg))"#) {
            let url = URL(fileURLWithPath: m)
            if FileManager.default.fileExists(atPath: m),
               seen.insert(url.absoluteString).inserted { out.append(url) }
            if out.count == max { break }
        }
        return out
    }

    /// Short label: host for web ("localhost:3000"), filename for files.
    static func label(_ url: URL) -> String {
        if url.isFileURL { return url.lastPathComponent }
        let host = url.host ?? url.absoluteString
        if let port = url.port { return "\(host):\(port)" }
        return host
    }
}

private extension String {
    func matching(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return re.matches(in: self, range: range).compactMap {
            Range($0.range, in: self).map { String(self[$0]) }
        }
    }
}

/// A clickable "open in browser" chip with a gently pulsing pixel globe.
struct LinkChip: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 5) {
                globe
                Text(LinkFinder.label(url))
                    .font(VNFont.sysMono(9.5, .medium))
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "arrow.up.forward")
                    .font(VNFont.ui(7, .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(Color(hex: 0x8AC3F0))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(hex: 0x14283A).opacity(hovering ? 1 : 0.8),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(Color(hex: 0x8AC3F0).opacity(hovering ? 0.5 : 0.25)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressFeedback())
        .onHover { hovering = $0 }
        .help(url.absoluteString)
    }

    // two-frame pixel globe — meridian shifts, reads as a slow spin
    private var globe: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let alt = Int(ctx.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 1
            PixelGlyph(grid: alt ? Self.globeB : Self.globeA, color: Color(hex: 0x8AC3F0), px: 1.6)
        }
    }
    private static let globeA = [
        ".ooo.",
        "o.o.o",
        "ooooo",
        "o.o.o",
        ".ooo.",
    ]
    private static let globeB = [
        ".ooo.",
        "o..oo",
        "ooooo",
        "o..oo",
        ".ooo.",
    ]
}

/// Local images the agent mentions, shown right in the notch.
struct ImageThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 150, alignment: .leading)
                } else {
                    Color.white.opacity(0.05).frame(height: 60)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        }
        .buttonStyle(PressFeedback())
        .help(url.path)
        .task { image = NSImage(contentsOf: url) }
    }
}

/// Row of link chips (and inline image previews) for a session's latest output.
struct LinkChipRow: View {
    let text: String?
    var imagesOnly = false
    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]
    var body: some View {
        let all = LinkFinder.links(in: text)
        let images = all.filter { $0.isFileURL && Self.imageExts.contains($0.pathExtension.lowercased()) }
        let rest = imagesOnly ? [] : all.filter { !images.contains($0) }
        if !images.isEmpty || !rest.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(images.prefix(2), id: \.absoluteString) { ImageThumb(url: $0) }
                if !rest.isEmpty {
                    HStack(spacing: 6) { ForEach(rest, id: \.absoluteString) { LinkChip(url: $0) } }
                }
            }
        }
    }
}
