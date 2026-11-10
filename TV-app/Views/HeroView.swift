import SwiftUI

/// Hva «Mer info» i toppfeltet åpner.
enum HeroTarget {
    case movie(MediaItem)
    case series(SeriesShow)
}

/// Toppfelt helt ut i kanten. På iPad ligger bildet til høyre og glir over i bakgrunnen,
/// så teksten alltid står på mørk bakgrunn. På iPhone ligger bildet øverst.
struct HeroBanner: View {
    let label: LocalizedStringKey
    let title: String
    let facts: [String]
    var rating: String? = nil
    var plot: String? = nil
    let artwork: URL?
    let playLabel: String
    let isFavorite: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void
    var info: HeroTarget? = nil

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }

    static func height(compact: Bool) -> CGFloat { compact ? 560 : 460 }

    var body: some View {
        Group {
            if compact { compactLayout } else { regularLayout }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height(compact: compact))
        .clipped()
    }

    // MARK: - Oppsett

    private var regularLayout: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                artworkView
                    .frame(width: geo.size.width * 0.7, height: geo.size.height)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                LinearGradient(stops: [
                    .init(color: Theme.bg, location: 0),
                    .init(color: Theme.bg, location: 0.3),
                    .init(color: Theme.bg.opacity(0.8), location: 0.46),
                    .init(color: Theme.bg.opacity(0), location: 0.72)
                ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg],
                               startPoint: UnitPoint(x: 0.5, y: 0.72), endPoint: .bottom)
                details(titleSize: 60)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.leading, 32)
                    .padding(.top, 20)
            }
        }
    }

    private var compactLayout: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                artworkView.frame(height: 400)
                Spacer(minLength: 0)
            }
            LinearGradient(stops: [
                .init(color: Theme.bg.opacity(0.65), location: 0),
                .init(color: Theme.bg.opacity(0), location: 0.18),
                .init(color: Theme.bg.opacity(0), location: 0.36),
                .init(color: Theme.bg, location: 0.72)
            ], startPoint: .top, endPoint: .bottom)
            details(titleSize: 40)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
    }

    private var artworkView: some View {
        Theme.tint(for: title)
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color.white.opacity(0.05))
                    .frame(width: 520, height: 520)
                    .offset(x: 140, y: -180)
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
            .clipped()
            .accessibilityHidden(true)
    }

    // MARK: - Tekst og knapper

    private func details(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            Text(label)
                .font(.caption.weight(.semibold))
                .tracking(1.8)
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            infoLine
            if let plot {
                Text(plot)
                    .font(compact ? .subheadline : .body)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.soft)
                    .lineLimit(3)
            }
            buttons
                .padding(.top, 4)
        }
    }

    private var infoLine: some View {
        HStack(spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { entry in
                if entry.offset > 0 {
                    Circle().fill(Theme.muted.opacity(0.7)).frame(width: 4, height: 4)
                }
                Text(entry.element)
            }
            if let rating {
                Text("★ " + rating)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
            }
        }
        .font(compact ? .footnote : .subheadline)
        .foregroundStyle(Theme.soft)
        .lineLimit(1)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                Label(playLabel, systemImage: "play.fill")
                    .frame(maxWidth: compact ? .infinity : nil)
            }
            .buttonStyle(AccentButtonStyle())

            switch info {
            case .movie(let movie):
                NavigationLink(value: movie) { infoLabel }
                    .buttonStyle(GhostButtonStyle())
            case .series(let show):
                NavigationLink(value: show) { infoLabel }
                    .buttonStyle(GhostButtonStyle())
            case nil:
                EmptyView()
            }

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "checkmark" : "plus")
            }
            .buttonStyle(GhostButtonStyle())
            .accessibilityLabel(isFavorite ? String(localized: "Remove from My List") : String(localized: "Add to My List"))
        }
    }

    @ViewBuilder
    private var infoLabel: some View {
        if compact {
            Image(systemName: "info.circle")
                .accessibilityLabel("More Info")
        } else {
            Label("More Info", systemImage: "info.circle")
                .padding(.horizontal, 14)
        }
    }
}

/// Roterende toppfelt med nye, godt vurderte filmer og serier.
struct FeaturedCarousel: View {
    struct Entry: Identifiable {
        let item: FeaturedItem
        let target: HeroTarget
        var id: String { item.id }
    }

    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    let entries: [Entry]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $index) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { pair in
                    banner(for: pair.element)
                        .tag(pair.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: HeroBanner.height(compact: sizeClass == .compact))

            if entries.count > 1 {
                PageDots(count: entries.count, index: index)
            }
        }
        .task(id: index) {
            guard entries.count > 1 else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.4)) { index = (index + 1) % entries.count }
            }
        }
    }

    @ViewBuilder
    private func banner(for entry: Entry) -> some View {
        let item = entry.item
        let genre = item.genre?.split(whereSeparator: { ",/|".contains($0) }).first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        switch entry.target {
        case .movie(let movie):
            let progress = library.progress(for: movie.id) ?? 0
            HeroBanner(
                label: "NEW",
                title: TitleCleaner.clean(item.title),
                facts: [String(localized: "Movie"), item.year, genre].compactMap { $0 },
                rating: item.rating,
                plot: item.plot,
                artwork: item.backdrop,
                playLabel: progress > 0.01 && progress < 0.95 ? String(localized: "Resume") : String(localized: "Play"),
                isFavorite: library.isFavorite(movie.id),
                onPlay: { library.play(movie) },
                onFavorite: { library.toggleFavorite(movie.id) },
                info: entry.target
            )
        case .series(let show):
            HeroBanner(
                label: "NEW",
                title: show.title,
                facts: [String(localized: "Series"), item.year, genre].compactMap { $0 },
                rating: item.rating,
                plot: item.plot,
                artwork: item.backdrop,
                playLabel: library.playLabel(for: library.nextEpisode(in: show)),
                isFavorite: library.isFavorite(show.id),
                onPlay: { Task { await library.playNextEpisode(of: show) } },
                onFavorite: { library.toggleFavorite(show.id) },
                info: entry.target
            )
        }
    }
}

/// Små streker som viser hvor i karusellen man er.
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : Theme.muted.opacity(0.4))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
