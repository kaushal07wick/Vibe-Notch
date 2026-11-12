import AppKit
import SwiftUI

/// A deterministic design comparison, exported without starting the app's
/// agent integrations or creating sample sessions in the real event store.
struct InterfaceStyleGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ONE NOTCH. FOUR MOODS.")
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Find your rhythm.").font(.system(size: 32, weight: .semibold)).tracking(-1)
                }
                Spacer()
                Text("Vibe Notch · Style studies")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
            LazyVGrid(columns: [GridItem(.fixed(330)), GridItem(.fixed(330))], spacing: 22) {
                ForEach(VNInterfaceStyle.allCases) { style in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(style.title).font(.system(size: 18, weight: .semibold))
                            Spacer()
                            Text(style == .classic ? "ORIGINAL" : "NEW")
                                .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                                .foregroundStyle(style.accent)
                        }
                        InterfaceStylePreview(style: style)
                            .frame(width: 300, height: 126)
                        Text(style.caption).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(15)
                    .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.07), lineWidth: 1))
                }
            }
            Text("Illustrative sample sessions · Switch live in Settings → Display → Interface style")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
        }
        .padding(32).frame(width: 746)
        .foregroundStyle(.white)
        .background(Color(hex: 0x08090C))
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
func exportInterfaceStyleGallery(to path: String) throws {
    let renderer = ImageRenderer(content: InterfaceStyleGallery())
    renderer.scale = 2
    guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}
