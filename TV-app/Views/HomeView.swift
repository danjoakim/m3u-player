import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var library
    @Binding var tab: AppTab
    @State private var showSettings = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                    .overlay(alignment: .top) {
                        if compact { topBar }
                    }

                if library.isRestoring {
                    RestoringView()
                }

                if library.isSample {
                    sampleBanner
                }

                let resume = library.continueWatching
                if !resume.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: continueTitle)
                        Shelf {
                            ForEach(resume) { item in
                                Button { library.play(item) } label: {
                                    PosterTile(title: item.seriesTitle ?? item.name,
                                               artwork: item.logo,
                                               progress: library.progress(for: item.id),
                                               width: compact ? 96 : 118)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !library.orderedLive.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Live TV", live: true, actionTitle: "See All") { tab = .live }
                        Shelf {
                            ForEach(library.orderedLive.prefix(15)) { item in
                                Button { library.play(item) } label: { ChannelCard(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let top = library.topSeries
                if top.count >= 3 {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: library.topSeriesAreNew ? "Top 10 New Series" : "Top 10 Series")
                        Shelf {
                            ForEach(Array(top.enumerated()), id: \.element.id) { entry in
                                NavigationLink(value: entry.element) {
                                    Top10Card(rank: entry.offset + 1, show: entry.element)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let recent = library.recentlyAdded
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Recently Added")
                        Shelf {
                            ForEach(recent) { arrival in
                                switch arrival {
                                case .movie(let movie):
                                    NavigationLink(value: movie) {
                                        PosterCard(title: movie.name, subtitle: arrival.subtitle, artwork: movie.logo,
                                                   progress: library.progress(for: movie.id))
                                            .frame(width: 130)
                                    }
                                    .buttonStyle(.plain)
                                case .series(let show):
                                    NavigationLink(value: show) {
                                        PosterCard(title: show.title, subtitle: arrival.subtitle, artwork: show.logo)
                                            .frame(width: 130)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                let recommended = library.recommendedShows
                if !recommended.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: LocalizedStringKey(library.recommendationsArePersonal
                                                                ? "Recommended for You" : "Popular Series"))
                        Shelf {
                            ForEach(recommended) { show in
                                NavigationLink(value: show) {
                                    PosterCard(title: show.title, subtitle: show.genreText ?? show.seasonsText,
                                               artwork: show.logo)
                                        .frame(width: 130)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let sports = library.todaysSports()
                if !sports.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Today's Sports", actionTitle: "See All") { tab = .sport }
                        Shelf {
                            ForEach(sports.prefix(15)) { listing in
                                Button { library.play(listing.item) } label: { SportCard(listing: listing) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                } else if !library.orderedSports.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Sports", actionTitle: "See All") { tab = .sport }
                        Shelf {
                            ForEach(library.orderedSports.prefix(15)) { item in
                                Button { library.play(item) } label: { ChannelCard(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let channels = library.favoriteChannels
                if !channels.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "My Channels")
                        Shelf {
                            ForEach(channels) { item in
                                Button { library.play(item) } label: { ChannelCard(item: item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let shows = library.favoriteShows
                let movies = library.favoriteMovies
                if !shows.isEmpty || !movies.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "My List")
                        Shelf {
                            ForEach(shows) { show in
                                NavigationLink(value: show) {
                                    PosterCard(title: show.title, subtitle: String(localized: "Series"), artwork: show.logo)
                                        .frame(width: 130)
                                }
                                .buttonStyle(.plain)
                            }
                            ForEach(movies) { movie in
                                NavigationLink(value: movie) {
                                    PosterCard(title: movie.name, subtitle: String(localized: "Movie"), artwork: movie.logo)
                                        .frame(width: 130)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !library.visibleMovies.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Movies", actionTitle: "See All") { tab = .movies }
                        Shelf {
                            ForEach(library.visibleMovies.prefix(20)) { movie in
                                NavigationLink(value: movie) {
                                    PosterCard(title: movie.name, subtitle: movie.group, artwork: movie.logo,
                                               progress: library.progress(for: movie.id))
                                        .frame(width: 130)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !library.visibleSeries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Series", actionTitle: "See All") { tab = .series }
                        Shelf {
                            ForEach(library.visibleSeries.prefix(20)) { show in
                                NavigationLink(value: show) {
                                    PosterCard(title: show.title,
                                               subtitle: show.seasonsText,
                                               artwork: show.logo)
                                        .frame(width: 130)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(library)
        }
    }

    /// «Fortsett å se for Dan», eller bare «Fortsett å se» uten navn.
    private var continueTitle: LocalizedStringKey {
        let name = library.profileName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Continue Watching" : LocalizedStringKey(String(localized: "Continue Watching for \(name)"))
    }

    /// Logo og innstillinger øverst på iPhone, oppå bildet.
    private var topBar: some View {
        HStack {
            Text(verbatim: "Strøm")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.text)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.top, 50)
    }

    /// Utvalgte elementer fra Xtream som finnes i listen.
    private var featuredEntries: [FeaturedCarousel.Entry] {
        library.featured.compactMap { item -> FeaturedCarousel.Entry? in
            switch item.kind {
            case .movie:
                guard let movie = library.movie(forStreamID: item.sourceID),
                      !Discovery.isAdult(movie.group) else { return nil }
                return .init(item: item, target: .movie(movie))
            case .series:
                guard let show = library.show(named: item.title),
                      !Discovery.isAdult(show.group) else { return nil }
                return .init(item: item, target: .series(show))
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        let entries = featuredEntries
        if !entries.isEmpty {
            FeaturedCarousel(entries: entries)
        } else if let show = library.topSeries.first ?? library.visibleSeries.first {
            HeroBanner(
                label: "FEATURED",
                title: show.title,
                facts: [String(localized: "Series"), show.genreText ?? show.seasonsText],
                rating: show.rating.map { $0.formatted(.number.precision(.fractionLength(1))) },
                artwork: show.logo,
                playLabel: library.playLabel(for: library.nextEpisode(in: show)),
                isFavorite: library.isFavorite(show.id),
                onPlay: { Task { await library.playNextEpisode(of: show) } },
                onFavorite: { library.toggleFavorite(show.id) },
                info: .series(show)
            )
        } else if let movie = library.visibleMovies.first {
            HeroBanner(
                label: "FEATURED",
                title: movie.name,
                facts: [String(localized: "Movie"), movie.group],
                artwork: movie.logo,
                playLabel: (library.progress(for: movie.id) ?? 0) > 0.01 ? String(localized: "Resume") : String(localized: "Play"),
                isFavorite: library.isFavorite(movie.id),
                onPlay: { library.play(movie) },
                onFavorite: { library.toggleFavorite(movie.id) },
                info: .movie(movie)
            )
        } else {
            Color.clear.frame(height: compact ? 100 : 40)
        }
    }

    private var sampleBanner: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your playlist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("Showing sample content.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Theme.surface, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, compact ? 20 : 32)
    }
}
