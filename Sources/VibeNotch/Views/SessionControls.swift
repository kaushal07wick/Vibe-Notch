import SwiftUI
import VibeNotchCore

/// Controls share one result line and preserve drafts as session events arrive.
struct SessionControls: View {
    @ObservedObject var store: EventStore
    let session: SessionActivity
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false
    @State private var activeTab = false
    @State private var confirmInterrupt = false
    @State private var confirmResume = false
    @State private var showModel = false
    @State private var model = ""
    @FocusState private var editing: Bool

    private var exact: Bool { TerminalControl.hasExactTarget(session) }
    private var canSend: Bool { TerminalControl.canReply(to: session) && (exact || activeTab) }
    private var supportsModel: Bool { ["claude", "codex"].contains(session.source) }
    private var draft: Binding<String> {
        Binding(get: { store.replyDrafts[session.id] ?? "" },
                set: { store.replyDrafts[session.id] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                toolbar.fixedSize(horizontal: true, vertical: false)
                toolbar.labelStyle(.iconOnly)
            }

            if let model = session.model {
                Text("Current model · \(model)").foregroundStyle(VNColor.muted).lineLimit(1)
            }
            if session.host != nil {
                Text("Remote session · use its terminal for input.").foregroundStyle(VNColor.muted)
            } else if !TerminalControl.canReply(to: session) {
                Text("Terminal input unavailable. Resume opens this conversation in Terminal.")
                    .foregroundStyle(VNColor.muted)
            } else {
                if !exact {
                    Toggle("Send to the active tab in \(session.terminal ?? "the terminal")", isOn: $activeTab)
                        .toggleStyle(.checkbox).foregroundStyle(VNColor.amber)
                        .help("Select this agent’s tab first. This terminal does not expose an exact pane target.")
                        .disabled(busy)
                }
                if showModel {
                    HStack(spacing: 8) {
                        if session.source == "claude" {
                            TextField("Model name (blank opens agent picker)", text: $model)
                                .textFieldStyle(.roundedBorder).focused($editing).onSubmit(switchModel)
                        }
                        Button(model.isEmpty ? "Open picker" : "Apply", action: switchModel)
                            .disabled(busy || !canSend)
                    }
                    Text("Sends /model to the agent. Choose in its terminal picker, then continue here.")
                        .foregroundStyle(VNColor.muted).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    TextField("Reply to \(agentName(session.source))…", text: draft, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1...3).focused($editing)
                        .onSubmit(send)
                        .disabled(busy)
                    Button(action: send) {
                        Label(busy ? "Sending…" : "Send", systemImage: "arrow.up")
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent).tint(VNColor.go)
                    .disabled(busy || !canSend || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(editing ? 0.18 : 0.07)))
            }
            if let message {
                Label(message, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(failed ? VNColor.amber : VNColor.go)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(message)
            }
        }
        .font(VNFont.ui(11))
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(VNColor.hair).frame(height: 1) }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
                control("Jump", icon: "arrow.up.forward") {
                    perform(success: exact ? "Opened session terminal." : "Opened terminal app. Select this session’s tab.") {
                        await TerminalJumper.focus(terminal: session.terminal, tty: session.tty,
                                                   meta: session.termMeta ?? [:])
                    }
                }
                .disabled(session.host != nil || session.terminal == nil)
                control("Interrupt", icon: "stop.circle") { confirmInterrupt = true }
                    .disabled(session.host != nil || session.tty == nil)
                    .confirmationDialog("Interrupt this session’s foreground command?", isPresented: $confirmInterrupt) {
                        Button("Send Ctrl-C", role: .destructive) {
                            perform(success: "Interrupt sent.") { TerminalControl.interrupt(session) }
                        }
                    } message: { Text("This sends the same signal as Ctrl-C in its terminal.") }
                control("Resume", icon: "play") { confirmResume = true }
                    .disabled(session.host != nil || !supportsModel)
                    .confirmationDialog("Resume this conversation in a new Terminal tab?", isPresented: $confirmResume) {
                        Button("Resume in Terminal") { resume() }
                    } message: { Text("Use this after stopping the original agent to avoid two agents editing the same project.") }
                control("Model", icon: "cpu") { showModel.toggle() }
                    .disabled(!supportsModel || !TerminalControl.canReply(to: session))
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.console.isEmpty ? (session.detail ?? "") : session.console.joined(separator: "\n"), forType: .string)
                    failed = false; message = "Activity copied."
                } label: { Image(systemName: "doc.on.doc").frame(width: 28, height: 28) }
                .buttonStyle(.plain).help("Copy recent activity").accessibilityLabel("Copy recent activity")
                Button { store.controlSessionID = nil } label: {
                    Image(systemName: "xmark").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).help("Close controls").accessibilityLabel("Close controls")
            }
            .disabled(busy)

    }

    private func control(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(label, systemImage: icon).frame(minHeight: 26) }
            .buttonStyle(.bordered).controlSize(.small).help(label).accessibilityLabel(label)
    }

    private func perform(success: String, action: @escaping @MainActor () async -> Bool) {
        guard !busy else { return }
        busy = true; message = nil
        Task { @MainActor in
            let ok = await action()
            failed = !ok
            message = ok ? success : "Couldn’t complete the action. Check the terminal and Automation or Accessibility permissions."
            busy = false
        }
    }

    private func send() {
        guard canSend, !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = draft.wrappedValue
        perform(success: "Input sent to terminal.") {
            let ok = await TerminalControl.send(text, to: session, allowActiveTab: activeTab)
            if ok, draft.wrappedValue == text { draft.wrappedValue = "" }
            return ok
        }
    }

    private func switchModel() {
        guard canSend else { return }
        perform(success: model.isEmpty ? "Model picker requested in terminal." : "Model change requested. Waiting for agent confirmation.") {
            await TerminalControl.switchModel(model, in: session, allowActiveTab: activeTab)
        }
    }

    private func resume() {
        perform(success: "Resume command opened in Terminal.") {
            let entry: ResumeEntry?
            if let cwd = session.cwd {
                entry = ResumeEntry(id: session.id, source: session.source, cwd: cwd,
                                    task: session.task ?? "", date: session.updatedAt)
            } else {
                entry = await Task.detached {
                    SessionHistory.load().first { $0.id == session.id && $0.source == session.source }
                }.value
            }
            guard let entry else { return false }
            return SessionHistory.resume(entry)
        }
    }
}
