import SwiftUI

struct SeriesView: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var group: String?
    @State private var query = ""

    private var shows: [SeriesShow] {
        library.visibleSeries.filter { show in
            (group == nil || show.group == group)
                && (query.isEmpty || show.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let shows = self.shows
        let minWidth: CGFloat = sizeClass == .compact ? 105 : 150
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CategoryPicker(options: library.visibleSeriesGroups, counts: library.seriesCategoryCounts, selection: $group, scope: "series")
                    .padding(.vertical, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 14)], spacing: 20) {
                    ForEach(shows) { show in
                        NavigationLink(value: show) {
                            PosterCard(title: show.title,
                                       subtitle: show.episodesText,
                                       artwork: show.logo)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .navigationTitle("Series")
        .searchable(text: $query, prompt: "Search series")
        .overlay {
            if library.isRestoring {
                RestoringView()
            } else if shows.isEmpty {
                ContentUnavailableView("No Series", systemImage: "rectangle.stack",
                                       description: Text("Your playlist has no series in this selection."))
            }
        }
    }
}

struct SeriesDetailView: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    let show: SeriesShow
    @State private var season: Int?
    @State private var info: SeriesInfo?
    @State private var isLoadingEpisodes = true

    private var next: MediaItem? { library.nextEpisode(in: show) }
    /// Serien med episoder, også de som hentes når siden åpnes.
    private var current: SeriesShow { library.resolvedShow(show) }
    private var currentSeason: Int { season ?? next?.season ?? current.seasons.first ?? 1 }
    private var episodes: [MediaItem] { current.episodes.filter { ($0.season ?? 1) == currentSeason } }

    var body: some View {
        let favorite = library.isFavorite(show.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailHeader(title: show.title,
                             meta: metaLine,
                             backdrop: info?.backdrop ?? info?.poster ?? show.logo,
                             poster: info?.poster ?? show.logo)

                HStack(spacing: 10) {
                    Button {
                        if let next {
                            library.play(next)
                        } else {
                            Task { await library.playNextEpisode(of: show) }
                        }
                    } label: {
                        Label(library.playLabel(for: next), systemImage: "play.fill")
                            .frame(maxWidth: sizeClass == .compact ? .infinity : nil)
                    }
                    .buttonStyle(AccentButtonStyle())

                    Button {
                        library.toggleFavorite(show.id)
                    } label: {
                        Image(systemName: favorite ? "checkmark" : "plus")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .accessibilityLabel(favorite ? String(localized: "Remove from My List") : String(localized: "Add to My List"))
                }
                .padding(.horizontal, 20)

                if let plot = info?.plot {
                    Text(plot)
                        .font(.body)
                        .foregroundStyle(Theme.soft)
                        .lineLimit(6)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: 760, alignment: .leading)
                }

                DetailFacts(facts: [("Cast", info?.cast), ("Genre", info?.genre)])
                    .padding(.horizontal, 20)

                HStack {
                    if current.seasons.count > 1 {
                        Menu {
                            ForEach(current.seasons, id: \.self) { s in
                                Button("Season \(s)") { season = s }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Season \(currentSeason)")
                                Image(systemName: "chevron.down").font(.caption.weight(.bold))
                            }
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Theme.surface, in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                        }
                    } else {
                        Text("Season \(currentSeason)")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Text("\(episodes.count) episodes")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 20)

                if isLoadingEpisodes && episodes.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                LazyVStack(spacing: 4) {
                    ForEach(episodes) { episode in
                        EpisodeRow(episode: episode,
                                   detail: library.episodeInfo(for: episode, in: info),
                                   progress: library.progress(for: episode.id),
                                   isCurrent: episode.id == next?.id) {
                            library.play(episode)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await library.loadEpisodes(for: show)
            info = await library.seriesInfo(for: show)
            isLoadingEpisodes = false
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = info?.year { parts.append(year) }
        if !current.seasons.isEmpty {
            parts.append(String(localized: "\(current.seasons.count) seasons"))
        }
        if let genre = info?.genre?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) {
            parts.append(genre)
        }
        if let rating = info?.rating { parts.append("★ " + rating) }
        return parts.joined(separator: " · ")
    }
}

struct EpisodeRow: View {
    let episode: MediaItem
    var detail: EpisodeInfo? = nil
    let progress: Double?
    let isCurrent: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                Theme.tint(for: episode.name)
                    .frame(width: 124, height: 70)
                    .overlay {
                        if let image = detail?.image {
                            AsyncImage(url: image) { phase in
                                if let picture = phase.image {
                                    picture.resizable().scaledToFill()
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .foregroundStyle(Theme.text.opacity(0.85))
                    }
                    .overlay(alignment: .bottom) {
                        if let progress, progress > 0.01 {
                            ProgressBar(value: progress)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    if let title = detail?.title {
                        Text("\(episode.episode ?? 0). \(title)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                    } else {
                        Text("Episode \(episode.episode ?? 0)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                    if let plot = detail?.plot {
                        Text(plot)
                            .font(.caption)
                            .foregroundStyle(Theme.soft)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(isCurrent ? Theme.surface : Color.clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        let fallback = detail?.durationText ?? episode.name
        guard let progress else { return fallback }
        if progress >= 0.95 { return String(localized: "Watched") }
        if progress > 0.01 { return String(localized: "In progress · \(progress.formatted(.percent.precision(.fractionLength(0))))") }
        return fallback
    }
}
