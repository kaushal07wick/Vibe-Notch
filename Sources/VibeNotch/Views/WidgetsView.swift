import SwiftUI

/// The notch's "now playing + calendar" page, in the spirit of a Nook widget row.
struct WidgetsView: View {
    @ObservedObject private var music = NowPlaying.shared
    @ObservedObject private var calendar = CalendarModel.shared

    var body: some View {
        // both cards share one height: the row sizes to the taller card, each card fills it
        HStack(alignment: .top, spacing: 10) {
            player.frame(maxWidth: .infinity, maxHeight: .infinity)
            self.calendarCard.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
        .frame(width: CGFloat(VNSettings.panelWidth), alignment: .leading)
        .onAppear { music.start(); calendar.load() }
        .onDisappear { music.stop() }
    }

    // MARK: Now playing

    private var player: some View {
        HStack(spacing: 12) {
            Group {
                if let art = music.artwork {
                    Image(nsImage: art).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(hex: 0x3B3F6B), Color(hex: 0x1C1E36)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note").font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                if music.app == nil {
                    Text("Not playing").font(VNFont.ui(12.5, .semibold))
                    HStack(spacing: 6) {
                        launch("Music", bundle: "com.apple.Music")
                        launch("Spotify", bundle: "com.spotify.client")
                    }
                    .padding(.top, 4)
                } else {
                    Text(music.title).font(VNFont.ui(12.5, .semibold)).lineLimit(1)
                    Text(music.artist).font(VNFont.ui(11)).foregroundStyle(VNColor.muted).lineLimit(1)
                    HStack(spacing: 10) {
                        control("backward.fill") { music.send(.previous) }
                        Button { music.send(.playpause) } label: {
                            Image(systemName: music.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                                .frame(width: 28, height: 28).background(Color.white.opacity(0.92), in: Circle())
                        }
                        .buttonStyle(PressFeedback())
                        control("forward.fill") { music.send(.next) }
                    }
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(card)
    }

    private func launch(_ name: String, bundle: String) -> some View {
        Button {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        } label: {
            Text(name).font(VNFont.ui(10.5, .medium)).foregroundStyle(VNColor.paper.opacity(0.8))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(PressFeedback())
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.035)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    private func control(_ symbol: String, size: CGFloat = 11, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(VNColor.paper.opacity(0.85)).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(PressFeedback())
    }

    // MARK: Calendar

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Date.now.formatted(.dateTime.month(.wide))).font(VNFont.ui(14, .semibold))
                Text(Date.now.formatted(.dateTime.year())).font(VNFont.ui(11)).foregroundStyle(VNColor.faint)
                Spacer(minLength: 0)
            }
            weekStrip
            if calendar.denied {
                Button("Allow calendar access") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                .buttonStyle(.plain).font(VNFont.ui(11, .medium)).foregroundStyle(VNColor.running)
            } else if let next = calendar.events.first {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: next.calendar.color)).frame(width: 3, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(next.title ?? "Event").font(VNFont.ui(11.5, .semibold)).lineLimit(1)
                        Text(next.isAllDay ? "All day" : next.startDate.formatted(date: .omitted, time: .shortened))
                            .font(VNFont.ui(10.5)).foregroundStyle(VNColor.muted)
                    }
                }
            } else {
                Label("Clear for the rest of today", systemImage: "checkmark.circle")
                    .font(VNFont.ui(11)).foregroundStyle(VNColor.faint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(card)
    }

    private var weekStrip: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: start)!
                let today = cal.isDateInToday(day)
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(VNFont.ui(8.5)).foregroundStyle(VNColor.faint)
                    Text(day.formatted(.dateTime.day())).font(VNFont.ui(11.5, today ? .bold : .regular))
                        .foregroundStyle(today ? Color.black : VNColor.paper.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(today ? VNColor.running : .clear, in: Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
