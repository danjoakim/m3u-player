import SwiftUI

/// Kanallogo med reserve: initialer på en farget flate.
struct LogoTile: View {
    let name: String
    let logo: URL?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Theme.tint(for: name)
            if let logo {
                AsyncImage(url: logo) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.12)
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24))
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Text(Theme.initials(name))
            .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.text)
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.45))
                Rectangle().fill(Theme.accent)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

/// Plakat for filmer og serier (2:3). Uten bilde vises tittelen på en farget flate.
struct PosterCard: View {
    let title: String
    var subtitle: String? = nil
    let artwork: URL?
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Theme.tint(for: title)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Color.white.opacity(0.06))
                        .frame(width: 160, height: 160)
                        .offset(x: 60, y: -60)
                }
                .overlay {
                    if let artwork {
                        AsyncImage(url: artwork) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if artwork == nil {
                        Text(title)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(3)
                            .padding(10)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress, progress > 0.01 {
                        ProgressBar(value: progress)
                    }
                }
                .clipShape(.rect(cornerRadius: 12))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
    }
}

/// Kort for kanaler på forsiden.
struct ChannelCard: View {
    @Environment(Library.self) private var library
    let item: MediaItem

    var body: some View {
        let programme = library.currentProgramme(for: item)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LogoTile(name: item.name, logo: item.logo, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(programme == nil ? item.group : item.name)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Text(programme?.title ?? item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
            }
            if let programme {
                ProgressBar(value: programme.progress(at: .now))
                    .clipShape(Capsule())
                Text(programme.timeRange)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            } else {
                HStack(spacing: 6) {
                    Circle().fill(item.kind == .live ? Theme.live : Theme.accent)
                        .frame(width: 6, height: 6)
                    Text(item.kind.label)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}

/// Kort for en sportssending i dag.
struct SportCard: View {
    let listing: SportListing
    var now: Date = .now

    var body: some View {
        let live = listing.programme.isOn(at: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(listing.programme.categories.first ?? String(localized: "Sports"))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer()
                Text(live ? String(localized: "LIVE") : listing.programme.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(live ? Color(hex: 0x14070A) : Theme.soft)
                    .background(live ? Theme.live : Color(hex: 0x1F2633), in: .rect(cornerRadius: 6))
            }
            Text(listing.programme.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(listing.item.name)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 220, height: 120, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}

/// Rad i kanallister, med stjerne for favoritt.
struct ChannelRow: View {
    @Environment(Library.self) private var library
    let item: MediaItem

    var body: some View {
        let favorite = library.isFavorite(item.id)
        let programme = library.currentProgramme(for: item)
        HStack(spacing: 8) {
            Button {
                library.play(item)
            } label: {
                HStack(spacing: 14) {
                    LogoTile(name: item.name, logo: item.logo, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if let programme {
                            Text(programme.title)
                                .font(.caption)
                                .foregroundStyle(Theme.soft)
                                .lineLimit(1)
                            ProgressBar(value: programme.progress(at: .now))
                                .clipShape(Capsule())
                                .frame(maxWidth: 160)
                        } else {
                            Text(item.group)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                library.toggleFavorite(item.id)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? Theme.accent : Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorite ? String(localized: "Remove from favorites") : String(localized: "Add to favorites"))
        }
        .padding(.vertical, 6)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var live = false
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 10) {
            if live {
                Circle().fill(Theme.live).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal, sizeClass == .compact ? 20 : 32)
    }
}

/// Horisontal rad med kort.
struct Shelf<Content: View>: View {
    private let content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                content
            }
            .padding(.horizontal, sizeClass == .compact ? 20 : 32)
        }
    }
}

/// Filterknapper øverst i listene.
struct ChipBar: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(String(localized: "All"), selected: selection == nil) { selection = nil }
                ForEach(options, id: \.self) { option in
                    chip(option, selected: selection == option) { selection = option }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Theme.bg : Theme.soft)
                .background(selected ? Theme.text : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.text : Theme.border))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Navigasjonsmål som trengs i alle faner.
    func appDestinations() -> some View {
        navigationDestination(for: SeriesShow.self) { show in
            SeriesDetailView(show: show)
        }
        .navigationDestination(for: MediaItem.self) { movie in
            MovieDetailView(movie: movie)
        }
    }
}

/// Vises mens den lagrede listen leses inn ved oppstart.
struct RestoringView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your channels…")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

extension SeriesShow {
    /// «3 sesonger», eller kategorien hvis episodene ikke er hentet ennå.
    var seasonsText: String {
        seasons.isEmpty ? group : String(localized: "\(seasons.count) seasons")
    }

    /// Første sjanger, f.eks. «Drama».
    var genreText: String? {
        guard let first = genre?.split(whereSeparator: { ",/|".contains($0) }).first else { return nil }
        let value = first.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// «12 episoder», eller kategorien hvis episodene ikke er hentet ennå.
    var episodesText: String {
        episodes.isEmpty ? group : String(localized: "\(episodes.count) episodes")
    }
}

extension NewArrival {
    /// «Serie · i går», «Film · for 3 dager siden».
    var subtitle: String {
        let kind: String
        switch self {
        case .movie: kind = String(localized: "Movie")
        case .series: kind = String(localized: "Series")
        }
        return kind + " · " + added.formatted(.relative(presentation: .named))
    }
}

/// Høy plakat uten tekst under. Tittelen vises bare mens bildet mangler.
struct PosterTile: View {
    let title: String
    let artwork: URL?
    var progress: Double? = nil
    var width: CGFloat = 118
    @State private var loaded = false

    var body: some View {
        Theme.tint(for: title)
            .overlay(alignment: .topLeading) {
                Circle().fill(Color.white.opacity(0.06))
                    .frame(width: width, height: width)
                    .offset(x: -width * 0.25, y: width * 0.25)
            }
            .overlay {
                if let artwork {
                    AsyncImage(url: artwork) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .onAppear { loaded = true }
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !loaded {
                    Text(title)
                        .font(.system(size: width > 100 ? 15 : 12, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(3)
                        .padding(EdgeInsets(top: 30, leading: 9, bottom: 9, trailing: 9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)],
                                                   startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(alignment: .bottom) {
                if let progress, progress > 0.01 {
                    ProgressBar(value: progress)
                }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }
}

/// Stort tall med bare omriss, som i «Topp 10».
struct OutlinedNumber: View {
    let text: String
    let size: CGFloat

    private static let offsets: [CGSize] = [
        CGSize(width: -1.5, height: 0), CGSize(width: 1.5, height: 0),
        CGSize(width: 0, height: -1.5), CGSize(width: 0, height: 1.5),
        CGSize(width: -1.1, height: -1.1), CGSize(width: 1.1, height: -1.1),
        CGSize(width: -1.1, height: 1.1), CGSize(width: 1.1, height: 1.1)
    ]

    var body: some View {
        let font = Font.system(size: size, weight: .heavy)
        ZStack {
            ForEach(Self.offsets.indices, id: \.self) { i in
                Text(verbatim: text)
                    .font(font)
                    .kerning(-size * 0.05)
                    .foregroundStyle(Color(hex: 0x4A5568))
                    .offset(Self.offsets[i])
            }
            Text(verbatim: text)
                .font(font)
                .kerning(-size * 0.05)
                .foregroundStyle(Theme.bg)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Plassering i «Topp 10»: stort tall med plakaten oppå.
struct Top10Card: View {
    let rank: Int
    let show: SeriesShow
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let compact = sizeClass == .compact
        let posterWidth: CGFloat = compact ? 80 : 110
        HStack(alignment: .bottom, spacing: compact ? -14 : -22) {
            OutlinedNumber(text: "\(rank)", size: compact ? 112 : 168)
                .frame(height: posterWidth * 1.5, alignment: .bottom)
                .offset(y: compact ? 14 : 20)
            PosterTile(title: show.title, artwork: show.logo, width: posterWidth)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(rank). \(show.title)"))
    }
}
