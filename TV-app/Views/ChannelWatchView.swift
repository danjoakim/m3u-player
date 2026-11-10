import SwiftUI
import AVKit
import AVFoundation

/// Kanal i vindusmodus: video, hva som går nå og hva som kommer senere.
struct ChannelWatchView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var channel: MediaItem
    @State private var model = PlayerModel()
    @State private var isFullscreen = false

    init(channel: MediaItem) {
        _channel = State(initialValue: channel)
    }

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        Group {
            if isFullscreen {
                ZStack {
                    Color.black.ignoresSafeArea()
                    video
                }
            } else {
                normalLayout
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .statusBarHidden(isFullscreen)
        .task(id: channel.id) {
            model.load(channel, startAt: nil, library: library)
        }
    }

    private var normalLayout: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            if compact {
                VStack(spacing: 0) {
                    video
                        .aspectRatio(16 / 9, contentMode: .fit)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            channelHeader
                            nowSection(now)
                            favoriteButton
                            laterSection(now, limit: 6)
                        }
                        .padding(20)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 28) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            video
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .clipShape(.rect(cornerRadius: 18))
                            channelHeader
                            nowSection(now)
                            favoriteButton
                        }
                    }
                    .frame(maxWidth: .infinity)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            laterSection(now, limit: 8)
                                .padding(18)
                                .background(Theme.sidebar, in: .rect(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
                            otherChannels(now)
                        }
                    }
                    .frame(width: 360)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
    }

    private func close() {
        model.stop()
        dismiss()
    }

    // MARK: - Deler

    private var video: some View {
        StreamPlayerView(
            model: model,
            title: isFullscreen ? channel.name : nil,
            isFullscreen: isFullscreen,
            onToggleFullscreen: {
                withAnimation(.easeInOut(duration: 0.25)) { isFullscreen.toggle() }
            }
        )
    }

    private var channelHeader: some View {
        HStack(spacing: 12) {
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            LogoTile(name: channel.name, logo: channel.logo, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(channel.group)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { switchChannel(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(GhostButtonStyle())
                .accessibilityLabel("Previous channel")
            Button { switchChannel(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(GhostButtonStyle())
                .accessibilityLabel("Next channel")
        }
    }

    @ViewBuilder
    private func nowSection(_ now: Date) -> some View {
        if let programme = library.currentProgramme(for: channel, at: now) {
            VStack(alignment: .leading, spacing: 10) {
                Text("NOW · \(programme.timeRange)")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Text(programme.title)
                    .font(.system(size: compact ? 24 : 30, weight: .bold))
                    .tracking(-0.5)
                if let subtitle = programme.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.soft)
                }
                HStack(spacing: 10) {
                    ProgressBar(value: programme.progress(at: now))
                        .clipShape(Capsule())
                    Text(programme.remainingText(at: now))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
                if let desc = programme.desc {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(Theme.soft)
                        .lineLimit(compact ? 5 : 8)
                }
                if !programme.categories.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(programme.categories.prefix(3), id: \.self) { category in
                            Text(category)
                                .font(.caption)
                                .foregroundStyle(Theme.soft)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: 0x1C222D), in: Capsule())
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No program info")
                    .font(.headline)
                Text(library.epg == nil
                     ? String(localized: "Add a TV guide (EPG) in Settings to see what's on.")
                     : String(localized: "The TV guide has no information about this channel right now."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var favoriteButton: some View {
        let favorite = library.isFavorite(channel.id)
        return Button {
            library.toggleFavorite(channel.id)
        } label: {
            Label(favorite ? String(localized: "In favorites") : String(localized: "Add to favorites"), systemImage: favorite ? "star.fill" : "star")
                .padding(.horizontal, 16)
        }
        .buttonStyle(GhostButtonStyle())
    }

    @ViewBuilder
    private func laterSection(_ now: Date, limit: Int) -> some View {
        let later = library.upcoming(for: channel, after: now, limit: limit)
        if !later.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(compact ? String(localized: "Later on \(channel.name)") : String(localized: "Later tonight"))
                    .font(.headline)
                    .padding(.bottom, 8)
                ForEach(later) { programme in
                    HStack(spacing: 14) {
                        Text(programme.start.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.soft)
                            .frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(programme.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(([programme.categories.first].compactMap { $0 } + [programme.durationText]).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func otherChannels(_ now: Date) -> some View {
        let others = library.catalog.live
            .filter { $0.group == channel.group && $0.id != channel.id }
            .prefix(12)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Other channels now")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach(Array(others)) { other in
                    let programme = library.currentProgramme(for: other, at: now)
                    Button {
                        channel = other
                    } label: {
                        HStack(spacing: 12) {
                            LogoTile(name: other.name, logo: other.logo, size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(other.name)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                                Text(programme?.title ?? other.group)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if let programme {
                                    ProgressBar(value: programme.progress(at: now))
                                        .clipShape(Capsule())
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Avspilling

    private func switchChannel(_ step: Int) {
        let list = library.catalog.live.filter { $0.group == channel.group }
        guard !list.isEmpty, let index = list.firstIndex(of: channel) else { return }
        channel = list[(index + step + list.count) % list.count]
    }
}
