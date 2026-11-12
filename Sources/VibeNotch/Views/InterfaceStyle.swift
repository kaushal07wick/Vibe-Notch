import SwiftUI
import VibeNotchCore

/// Presentation only: selecting a style never changes agent or approval behavior.
enum VNInterfaceStyle: String, CaseIterable, Identifiable, Sendable {
    case classic, focus, aurora, studio
    var id: String { rawValue }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "interfaceStyle") ?? "") ?? .classic }
    var title: String { rawValue.capitalized }
    var caption: String {
        switch self {
        case .classic: return "Warm, familiar, a little retro."
        case .focus: return "Quiet rows. Just what matters."
        case .aurora: return "Soft light and rounded surfaces."
        case .studio: return "Compact, precise, and structured."
        }
    }
    var accent: Color {
        switch self {
        case .classic: return Color(hex: 0x6EA7FF)
        case .focus: return Color(hex: 0xB9C8DC)
        case .aurora: return Color(hex: 0xB2A2FF)
        case .studio: return Color(hex: 0x7EDBCB)
        }
    }
    var text: Color { Color(hex: self == .classic ? 0xF1EAD9 : self == .aurora ? 0xEEF0FF : 0xEDF1F5) }
    var surface: Color { Color(hex: self == .aurora ? 0x10101B : self == .studio ? 0x0B1215 : 0x0D0D0F) }
    var radius: CGFloat { self == .aurora ? 15 : self == .studio ? 7 : 9 }
    var rowGap: CGFloat { self == .aurora ? 7 : self == .studio ? 5 : 0 }
    var contentAnimation: Animation {
        switch self {
        case .classic: return .spring(response: 0.36, dampingFraction: 0.8)
        case .focus: return .easeInOut(duration: 0.2)
        case .aurora: return .spring(response: 0.38, dampingFraction: 0.96)
        case .studio: return .easeOut(duration: 0.18)
        }
    }
    var openingAnimation: Animation {
        self == .classic ? .spring(response: 0.32, dampingFraction: 0.85) : contentAnimation
    }
    var closingAnimation: Animation {
        self == .classic ? .spring(response: 0.26, dampingFraction: 0.92) : .easeOut(duration: 0.2)
    }
}

private struct InterfaceStyleKey: EnvironmentKey { static let defaultValue = VNInterfaceStyle.classic }
extension EnvironmentValues {
    var vnInterfaceStyle: VNInterfaceStyle {
        get { self[InterfaceStyleKey.self] }
        set { self[InterfaceStyleKey.self] = newValue }
    }
}

/// Small native marks; no bitmap assets or perpetual decorative animation.
struct InterfaceStyleMark: View {
    let style: VNInterfaceStyle
    var size: CGFloat = 22
    var waiting = false
    var active = true
    private var tint: Color { waiting ? VNColor.amber : style.accent }
    var body: some View {
        Group {
            switch style {
            case .classic:
                PixelGhost(mood: waiting ? .waiting : active ? .working : .idle, px: size / 12)
            case .focus:
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<3) { index in
                        Capsule().fill(tint.opacity(active ? 0.9 : 0.35))
                            .frame(width: 3, height: size * (index == 1 ? 0.7 : 0.4))
                    }
                }
            case .aurora:
                Circle().fill(RadialGradient(colors: [.white, tint, tint.opacity(0.3)],
                    center: .init(x: 0.32, y: 0.25), startRadius: 0, endRadius: size * 0.8))
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                    .shadow(color: tint.opacity(active ? 0.28 : 0), radius: 6)
                    .frame(width: size * 0.8, height: size * 0.8)
            case .studio:
                Image(systemName: waiting ? "square.stack.3d.up.fill" : "square.grid.2x2.fill")
                    .font(.system(size: size * 0.65, weight: .medium))
                    .foregroundStyle(tint.opacity(active ? 1 : 0.4))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Alternate session layouts reuse the same rows, actions, and status model.
struct StyledSessionBoard: View {
    @ObservedObject var store: EventStore
    let sessions: [SessionActivity]
    let full: Bool
    let style: VNInterfaceStyle
    let now: Date
    let onDismiss: (String) -> Void

    private var working: Int { sessions.filter { store.phase(for: $0, now: now) == .working }.count }
    private var waiting: Int { sessions.filter { store.phase(for: $0, now: now) == .waiting }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .aurora ? 12 : 9) {
            if sessions.isEmpty { emptyState }
            else {
                summary
                ScrollView {
                    VStack(spacing: style.rowGap) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            HStack(spacing: 0) {
                                if style == .studio {
                                    Text(String(format: "%02d", index + 1))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(style.accent.opacity(0.5)).frame(width: 30)
                                }
                                SessionRow(store: store, s: session, phase: store.phase(for: session, now: now), onDismiss: onDismiss)
                            }
                            .background(rowBackground)
                            .clipShape(RoundedRectangle(cornerRadius: style.radius))
                            .overlay {
                                if style != .focus {
                                    RoundedRectangle(cornerRadius: style.radius)
                                        .strokeBorder(style.accent.opacity(style == .aurora ? 0.12 : 0.09), lineWidth: 0.5)
                                }
                            }
                            if style == .focus && index < sessions.count - 1 {
                                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5).padding(.leading, 44)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: min(full ? 300 : 150, CGFloat(sessions.count) * (style == .aurora ? 92 : 84)))
            }
        }
        .padding(.horizontal, style == .focus ? 8 : 12)
        .padding(.top, 5).padding(.bottom, 9)
        .frame(width: sessions.isEmpty ? min(420, VNSettings.effectivePanelWidth) : VNSettings.effectivePanelWidth)
    }

    @ViewBuilder private var summary: some View {
        HStack(spacing: 8) {
            if style == .aurora { InterfaceStyleMark(style: style, size: 24, waiting: waiting > 0, active: working > 0) }
            Text(style == .studio ? "SESSIONS" : style == .aurora ? "Your agents" : "Sessions")
                .font(.system(size: style == .studio ? 10 : 12, weight: .medium,
                              design: style == .studio ? .monospaced : .default))
                .tracking(style == .studio ? 1.4 : 0)
                .foregroundStyle(style == .focus ? style.text : style.accent)
            Spacer(minLength: 8)
            if waiting > 0 {
                Text("\(waiting) need you").foregroundStyle(VNColor.amber)
            }
            Text(working > 0 ? "\(working) working" : "\(sessions.count) recent")
                .foregroundStyle(style.text.opacity(0.45))
        }
        .font(.system(size: 10, design: style == .studio ? .monospaced : .default))
        .padding(.horizontal, 8)
    }

    private var rowBackground: some View {
        LinearGradient(colors: style == .aurora
            ? [style.accent.opacity(0.11), style.surface.opacity(0.6)]
            : [style == .studio ? style.surface : .clear, style == .studio ? style.surface : .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            InterfaceStyleMark(style: style, size: 30, active: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(style == .studio ? "WORKSPACE IDLE" : "All quiet")
                    .font(.system(size: style == .studio ? 11 : 14, weight: .medium,
                                  design: style == .studio ? .monospaced : .default))
                Text("Your next coding session will appear here.")
                    .font(.system(size: 11)).foregroundStyle(style.text.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
    }
}

/// Small, explicitly illustrative previews for choosing a style.
struct InterfaceStylePreview: View {
    let style: VNInterfaceStyle
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                InterfaceStyleMark(style: style, size: 13)
                Spacer()
                RoundedRectangle(cornerRadius: 3).fill(.black).frame(width: 65, height: 10)
                Spacer()
                Text("2").font(.system(size: 9, weight: .medium)).foregroundStyle(style.text.opacity(0.6))
            }
            .padding(.horizontal, 14).frame(height: 24)
            VStack(alignment: .leading, spacing: style == .aurora ? 7 : 0) {
                sample("Checkout flow", detail: "Running tests", active: true)
                if style != .focus { sample("Documentation", detail: "Finished", active: false) }
                else {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5).padding(.vertical, 7)
                    sample("Documentation", detail: "Finished", active: false)
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .frame(height: 126)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .environment(\.vnInterfaceStyle, style)
        .accessibilityLabel("\(style.title) preview with two sample sessions")
    }

    private func sample(_ title: String, detail: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            if style == .classic {
                RoundedRectangle(cornerRadius: 3).fill(style.accent.opacity(0.2)).frame(width: 17, height: 17)
                    .overlay(Image(systemName: "terminal").font(.system(size: 8)).foregroundStyle(style.accent))
            } else if style == .studio {
                Text(active ? "01" : "02").font(.system(size: 8, design: .monospaced)).foregroundStyle(style.accent.opacity(0.6))
            } else {
                Circle().fill(active ? style.accent : Color(hex: 0x6FB982)).frame(width: 5, height: 5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10, weight: .medium, design: style == .aurora ? .rounded : .default))
                    .foregroundStyle(style.text)
                Text(detail).font(.system(size: 8, design: style == .studio ? .monospaced : .default))
                    .foregroundStyle(style.text.opacity(0.42))
            }
            Spacer(minLength: 0)
            if active { Image(systemName: "ellipsis").font(.system(size: 9)).foregroundStyle(style.text.opacity(0.35)) }
        }
        .padding(style == .aurora || style == .studio ? 7 : 3)
        .background(style == .aurora ? style.accent.opacity(0.1) : style == .studio ? style.surface : .clear,
                    in: RoundedRectangle(cornerRadius: style.radius))
    }
}

struct InterfaceStylePicker: View {
    @AppStorage("interfaceStyle") private var selected = VNInterfaceStyle.classic.rawValue
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(VNInterfaceStyle.allCases) { style in
                Button { selected = style.rawValue } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        InterfaceStylePreview(style: style)
                        HStack {
                            Text(style.title).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Image(systemName: selected == style.rawValue ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected == style.rawValue ? style.accent : .white.opacity(0.2))
                        }
                        Text(style.caption).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(10)
                    .background(Color.white.opacity(selected == style.rawValue ? 0.07 : 0.025), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected == style.rawValue ? style.accent.opacity(0.5) : .white.opacity(0.07), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(style.title). \(style.caption)")
                .accessibilityAddTraits(selected == style.rawValue ? .isSelected : [])
            }
        }
    }
}
