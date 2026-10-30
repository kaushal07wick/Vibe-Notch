import SwiftUI

/// The notch's "now playing + calendar" page, in the spirit of a Nook widget row.
struct WidgetsView: View {
    @ObservedObject private var music = NowPlaying.shared
    @ObservedObject private var calendar = CalendarModel.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            player.frame(maxWidth: .infinity)
            self.calendarCard.frame(maxWidth: .infinity)
        }
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
                    ZStack { Color.white.opacity(0.07); Image(systemName: "music.note").foregroundStyle(VNColor.faint) }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                if music.app == nil {
                    Text("Nothing playing").font(VNFont.ui(12.5, .semibold))
                    Text("Open Music or Spotify").font(VNFont.ui(11)).foregroundStyle(VNColor.muted)
                } else {
                    Text(music.title).font(VNFont.ui(12.5, .semibold)).lineLimit(1)
                    Text(music.artist).font(VNFont.ui(11)).foregroundStyle(VNColor.muted).lineLimit(1)
                    HStack(spacing: 14) {
                        control("backward.fill") { music.send(.previous) }
                        control(music.playing ? "pause.fill" : "play.fill", size: 14) { music.send(.playpause) }
                        control("forward.fill") { music.send(.next) }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Text(Date.now.formatted(.dateTime.month(.abbreviated))).font(VNFont.ui(20, .semibold))
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
                Text("Nothing more today").font(VNFont.ui(11)).foregroundStyle(VNColor.faint)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
