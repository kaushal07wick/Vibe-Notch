import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A file shelf in the notch: drop files on it (or on the closed notch), drag them back
/// out into any app. Holds references, not copies.
@MainActor
final class TrayStore: ObservableObject {
    static let shared = TrayStore()
    private static let key = "trayPaths"
    @Published private(set) var items: [URL]

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !items.contains(url) { items.append(url) }
        save()
    }

    func remove(_ url: URL) { items.removeAll { $0 == url }; save() }
    func clear() { items.removeAll(); save() }

    private func save() { UserDefaults.standard.set(items.map(\.path), forKey: Self.key) }

    /// Accepts dropped file URLs; returns whether anything was taken.
    nonisolated static func handleDrop(_ providers: [NSItemProvider], then done: @escaping @MainActor () -> Void = {}) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in TrayStore.shared.add([url]); done() }
            }
        }
        return !files.isEmpty
    }
}

struct TrayView: View {
    @ObservedObject private var tray = TrayStore.shared
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("TRAY").font(VNFont.sysMono(10, .semibold)).tracking(1.4)
                    .foregroundStyle(VNColor.paper.opacity(0.55))
                Text(tray.items.isEmpty ? "drop files here" : "drag out to any app")
                    .font(VNFont.ui(10)).foregroundStyle(VNColor.faint)
                Spacer(minLength: 8)
                if !tray.items.isEmpty {
                    Button("Clear") { tray.clear() }
                        .buttonStyle(.plain).font(VNFont.ui(10.5, .medium)).foregroundStyle(VNColor.muted)
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(tray.items, id: \.self) { TrayTile(url: $0) }
                    if tray.items.isEmpty {
                        Text("Drag files onto the notch — they stay here until you remove them.")
                            .font(VNFont.ui(11)).foregroundStyle(VNColor.faint)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(targeted ? 0.45 : 0.14),
                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { TrayStore.handleDrop($0) }
        }
        .padding(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
        .frame(width: CGFloat(VNSettings.panelWidth), alignment: .leading)
    }
}

private struct TrayTile: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: preview)
                .resizable().scaledToFit().frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(url.lastPathComponent).font(VNFont.ui(10)).foregroundStyle(VNColor.paper.opacity(0.75))
                .lineLimit(2).multilineTextAlignment(.center).frame(width: 66)
        }
        .padding(6)
        .background(Color.white.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { TrayStore.shared.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                        .foregroundStyle(VNColor.paper.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(url.path)
    }

    /// Real thumbnail for images, the Finder icon for everything else.
    private var preview: NSImage {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
           let image = NSImage(contentsOf: url) { return image }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
