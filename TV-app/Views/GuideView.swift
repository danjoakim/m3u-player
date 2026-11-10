import SwiftUI

/// TV-guide som rutenett: kanaler nedover, tid bortover.
struct GuideView: View {
    @Environment(Library.self) private var library
    let channels: [MediaItem]

    private let minuteWidth: CGFloat = 4
    private let rowHeight: CGFloat = 68
    private let rulerHeight: CGFloat = 28
    private let logoColumn: CGFloat = 76

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 1800).rounded(.down) * 1800 - 1800)
            let end = start.addingTimeInterval(8 * 3600)
            let width = CGFloat(end.timeIntervalSince(start) / 60) * minuteWidth
            let nowX = CGFloat(now.timeIntervalSince(start) / 60) * minuteWidth

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: rulerHeight)
                        ForEach(channels) { channel in
                            Button {
                                library.play(channel)
                            } label: {
                                LogoTile(name: channel.name, logo: channel.logo, size: 44)
                                    .frame(width: logoColumn, height: rowHeight)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(channel.name)
                        }
                    }
                    .frame(width: logoColumn)
                    .background(Theme.bg)

                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ruler(start: start, end: end)
                                .frame(width: width, height: rulerHeight, alignment: .leading)
                            ForEach(channels) { channel in
                                GuideRow(programmes: library.programmes(for: channel),
                                         start: start, end: end, now: now, minuteWidth: minuteWidth) {
                                    library.play(channel)
                                }
                                .frame(width: width, height: rowHeight, alignment: .leading)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            Rectangle()
                                .fill(Theme.live)
                                .frame(width: 2)
                                .offset(x: nowX)
                                .allowsHitTesting(false)
                        }
                    }
                    .defaultScrollAnchor(.leading)
                }
            }
        }
    }

    private func ruler(start: Date, end: Date) -> some View {
        let marks = Array(stride(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970, by: 1800))
        return ZStack(alignment: .leading) {
            ForEach(marks, id: \.self) { mark in
                Text(Date(timeIntervalSince1970: mark).formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .offset(x: CGFloat((mark - start.timeIntervalSince1970) / 60) * minuteWidth + 4)
            }
        }
    }
}

private struct GuideRow: View {
    let programmes: [EPGProgramme]
    let start: Date
    let end: Date
    let now: Date
    let minuteWidth: CGFloat
    let onTap: () -> Void

    var body: some View {
        let visible = programmes.filter { $0.stop > start && $0.start < end }
        ZStack(alignment: .leading) {
            Color.clear
            if visible.isEmpty {
                Text("No program info")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 10)
            }
            ForEach(visible) { programme in
                let from = max(programme.start, start)
                let to = min(programme.stop, end)
                let x = CGFloat(from.timeIntervalSince(start) / 60) * minuteWidth
                let w = max(CGFloat(to.timeIntervalSince(from) / 60) * minuteWidth - 4, 0)
                let live = programme.isOn(at: now)
                Button(action: onTap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(programme.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(programme.timeRange)
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: w, height: 52, alignment: .leading)
                    .background(live ? Color(hex: 0x1C2B30) : Theme.surface, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(live ? Theme.accent : Theme.border))
                    .clipShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .offset(x: x)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: 0x1C222D)).frame(height: 1)
        }
    }
}
