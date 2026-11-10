import SwiftUI

extension SportKind {
    var title: LocalizedStringKey {
        switch self {
        case .football: "Football"
        case .hockey: "Ice Hockey"
        case .handball: "Handball"
        case .tennis: "Tennis"
        case .motorsport: "Motorsport"
        case .winter: "Winter Sports"
        case .golf: "Golf"
        case .basketball: "Basketball"
        case .combat: "Combat Sports"
        case .cycling: "Cycling"
        case .other: "Other"
        }
    }
}

/// Sportsside: direkte nå, senere i dag, i morgen og sportskanalene.
struct SportView: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var filter: SportKind?

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let all = library.sportListings.filter { $0.programme.stop > now }
            let kinds = SportKind.allCases.filter { kind in all.contains { $0.kind == kind } }
            let listings = filter.map { selected in all.filter { $0.kind == selected } } ?? all
            let live = listings.filter { $0.programme.isOn(at: now) }
            let later = listings.filter { $0.programme.start > now }
            let tonightEnd = Calendar.current.startOfDay(for: now).addingTimeInterval(27 * 3600)
            let today = later.filter { $0.programme.start < tonightEnd }
            let tomorrow = later.filter { $0.programme.start >= tonightEnd }

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if kinds.count > 1 {
                        SportFilterBar(kinds: kinds, selection: $filter)
                    }

                    if !live.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Live Now", live: true)
                            Shelf {
                                ForEach(live) { listing in
                                    Button { library.play(listing.item) } label: {
                                        LiveSportCard(listing: listing, now: now)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !today.isEmpty {
                        schedule("Later Today", today, now: now)
                    }
                    if !tomorrow.isEmpty {
                        schedule("Tomorrow", tomorrow, now: now)
                    }

                    if all.isEmpty {
                        guideHint
                    }

                    if !library.orderedSports.isEmpty, filter == nil {
                        channelGrid(now: now)
                    }
                }
                .padding(.vertical, 12)
            }
            .overlay {
                if library.isRestoring {
                    RestoringView()
                } else if all.isEmpty && library.orderedSports.isEmpty {
                    ContentUnavailableView("No Sports", systemImage: "sportscourt",
                                           description: Text("No sports channels or sports broadcasts found today."))
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle("Sports")
    }

    private var horizontalPadding: CGFloat { compact ? 20 : 32 }

    // MARK: - Deler

    private func schedule(_ title: LocalizedStringKey, _ items: [SportListing], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            LazyVStack(spacing: 8) {
                ForEach(items.prefix(60)) { listing in
                    Button { library.play(listing.item) } label: {
                        SportScheduleRow(listing: listing)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var guideHint: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            Text(library.epg == nil
                 ? "Add a TV guide (EPG) in Settings to see today's sports broadcasts."
                 : "The TV guide has no sports broadcasts right now.")
                .font(.subheadline)
                .foregroundStyle(Theme.soft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .padding(.horizontal, horizontalPadding)
    }

    private func channelGrid(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sports Channels")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 150 : 200), spacing: 12)], spacing: 12) {
                ForEach(library.orderedSports.prefix(120)) { channel in
                    Button { library.play(channel) } label: {
                        SportChannelTile(channel: channel, programme: library.currentProgramme(for: channel, at: now), now: now)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
}

/// Store knapper for sportsgren. Bare grener som faktisk sendes, vises.
private struct SportFilterBar: View {
    let kinds: [SportKind]
    @Binding var selection: SportKind?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                tile(icon: "square.grid.2x2", title: "All", selected: selection == nil) { selection = nil }
                ForEach(kinds, id: \.self) { kind in
                    tile(icon: kind.icon, title: kind.title, selected: selection == kind) {
                        selection = selection == kind ? nil : kind
                    }
                }
            }
            .padding(.horizontal, sizeClass == .compact ? 20 : 32)
        }
    }

    private func tile(icon: String, title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Theme.bg : Theme.text)
            .frame(width: 92, height: 80)
            .background(selected ? Theme.accent : Theme.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.accent : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Stort kort for en sending som går nå.
private struct LiveSportCard: View {
    let listing: SportListing
    let now: Date
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LogoTile(name: listing.item.name, logo: listing.item.logo, size: 40)
                Text(listing.item.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(Color(hex: 0x14070A))
                    .background(Theme.live, in: .rect(cornerRadius: 6))
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: listing.kind.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                Text(listing.programme.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            ProgressBar(value: listing.programme.progress(at: now))
                .clipShape(Capsule())
            Text(listing.programme.timeRange + " · " + listing.programme.remainingText(at: now))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
        .padding(16)
        .frame(width: sizeClass == .compact ? 280 : 320, height: 170, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
    }
}

/// Rad i oversikten: tid, sportsgren, tittel og kanal.
private struct SportScheduleRow: View {
    let listing: SportListing

    var body: some View {
        HStack(spacing: 14) {
            Text(listing.programme.start.formatted(date: .omitted, time: .shortened))
                .font(.headline)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .frame(width: 58, alignment: .leading)
            Image(systemName: listing.kind.icon)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.programme.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(listing.item.name + " · " + listing.programme.durationText)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            LogoTile(name: listing.item.name, logo: listing.item.logo, size: 36)
        }
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .contentShape(.rect)
    }
}

/// Rute for en sportskanal med det som går nå.
private struct SportChannelTile: View {
    let channel: MediaItem
    let programme: EPGProgramme?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LogoTile(name: channel.name, logo: channel.logo, size: 44)
                Text(channel.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if let programme {
                Text(programme.title)
                    .font(.caption)
                    .foregroundStyle(Theme.soft)
                    .lineLimit(1)
                ProgressBar(value: programme.progress(at: now))
                    .clipShape(Capsule())
            } else {
                Text(channel.group)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}
