import SwiftUI
import VibeNotchCore

// ⌘K command palette — one field that finds and does everything:
// jump to an active session, resume a past one, approve what's pending,
// open settings. Click the ⌘ header icon (or ⌘K while the panel is key).

struct PaletteView: View {
    @ObservedObject var store: EventStore
    let close: () -> Void

    @State private var query = ""
    @State private var history: [ResumeEntry] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").font(.system(size: 11)).foregroundStyle(VNColor.faint)
                TextField("Jump, resume, approve…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { hits.first?.run() }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(VNColor.muted)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.055)).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(hits) { hit in PaletteRow(hit: hit) }
                    if hits.isEmpty {
                        Text("Nothing matches.").font(.system(size: 11))
                            .foregroundStyle(VNColor.faint).padding(.vertical, 10)
                    }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
        }
        .padding(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
        .frame(width: 620, alignment: .leading)
        .onAppear {
            history = SessionHistory.load(limit: 10)
            focused = true
        }
    }

    private struct Hit: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String?
        let tint: Color
        let run: () -> Void
    }

    private var hits: [Hit] {
        var all: [Hit] = []

        // actions first when they matter
        if !store.pending.isEmpty {
            all.append(Hit(id: "act-approve", icon: "checkmark.circle.fill",
                           title: "Approve all \(store.pending.count) pending",
                           subtitle: nil, tint: VNColor.go) { store.approveAll(); close() })
        }
        for s in store.activeSessions {
            all.append(Hit(id: "jump-\(s.sessionId)", icon: "arrow.up.forward.square",
                           title: sessionTitle(folder: s.folder, task: s.task),
                           subtitle: "jump · \(agentName(s.source))", tint: VNColor.running) {
                TerminalJumper.jump(terminal: s.terminal, tty: s.tty); close()
            })
        }
        for e in history {
            all.append(Hit(id: "res-\(e.id)", icon: "clock.arrow.circlepath",
                           title: "\(e.folder) · \(e.task)",
                           subtitle: "resume", tint: VNColor.muted) {
                SessionHistory.resume(e); close()
            })
        }
        all.append(Hit(id: "act-settings", icon: "gearshape.fill", title: "Settings",
                       subtitle: nil, tint: VNColor.muted) { SettingsWindow.show(); close() })

        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.title.lowercased().contains(q) || ($0.subtitle?.lowercased().contains(q) ?? false) }
    }

    private struct PaletteRow: View {
        let hit: Hit
        @State private var hovering = false

        var body: some View {
            Button(action: hit.run) {
                HStack(spacing: 9) {
                    Image(systemName: hit.icon).font(.system(size: 11))
                        .foregroundStyle(hit.tint).frame(width: 16)
                    Text(hit.title).font(.system(size: 11.8, weight: .medium))
                        .foregroundStyle(VNColor.text).lineLimit(1).truncationMode(.tail)
                    if let sub = hit.subtitle {
                        Text(sub).font(VNFont.sysMono(9.5, .medium)).foregroundStyle(VNColor.faint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(hovering ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        }
    }
}
