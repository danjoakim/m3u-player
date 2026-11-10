import Foundation

/// Et nytt element på forsiden: film eller serie.
nonisolated enum NewArrival: Identifiable, Hashable, Sendable {
    case movie(MediaItem)
    case series(SeriesShow)

    var id: String {
        switch self {
        case .movie(let movie): "movie:" + movie.id
        case .series(let show): "series:" + show.id
        }
    }

    var added: Date {
        switch self {
        case .movie(let movie): movie.added ?? .distantPast
        case .series(let show): show.added ?? .distantPast
        }
    }

    var title: String {
        switch self {
        case .movie(let movie): movie.name
        case .series(let show): show.title
        }
    }
}

/// Finner «Nylig lagt til» og «Anbefalt for deg».
nonisolated enum Discovery {
    /// Kategorier som aldri skal vises på forsiden.
    private static let adultWords = ["xxx", "adult", "18+", "+18", "18 +", "porn", "erotic", "erotik",
                                     "for adults", "voksen", "vuxen", "playboy", "hustler", "hentai"]

    static func isAdult(_ group: String) -> Bool {
        let lower = group.lowercased()
        return adultWords.contains { lower.contains($0) }
    }

    /// «Drama, Krim / Thriller» → ["drama", "krim", "thriller"].
    static func genres(_ text: String?) -> [String] {
        guard let text else { return [] }
        return text.split(whereSeparator: { ",/|&;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func titleKey(_ title: String) -> String {
        // Titlene er allerede ryddet i katalogen, så en enkel nøkkel holder (og er rask).
        XtreamClient.normalizedKey(title)
    }

    /// De nyeste filmene og seriene (også serier med nye episoder), uten duplikater.
    static func recentlyAdded(_ catalog: Catalog, limit: Int = 24) -> [NewArrival] {
        var items: [NewArrival] = []
        for movie in catalog.movies where movie.added != nil && movie.logo != nil && !isAdult(movie.group) {
            items.append(.movie(movie))
        }
        for show in catalog.series where show.added != nil && show.logo != nil && !isAdult(show.group) {
            items.append(.series(show))
        }
        items.sort { $0.added > $1.added }
        var seen = Set<String>()
        var result: [NewArrival] = []
        for item in items where seen.insert(titleKey(item.title)).inserted {
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }

    /// Topp 10: godt vurderte serier, helst lagt til eller oppdatert den siste måneden.
    static func topSeries(_ catalog: Catalog, limit: Int = 10, now: Date = .now) -> (shows: [SeriesShow], areNew: Bool) {
        let region = ChannelOrder.regionKeywords()
        let candidates = catalog.series.filter { $0.logo != nil && ($0.rating ?? 0) > 0 && !isAdult($0.group) }
        let recent = candidates.filter { show in
            guard let added = show.added else { return false }
            return now.timeIntervalSince(added) < 45 * 86400
        }
        let areNew = recent.count >= limit
        let pool = areNew ? recent : candidates

        func score(_ show: SeriesShow) -> Double {
            var value = (show.rating ?? 0) / 10
            if let added = show.added {
                let days = max(now.timeIntervalSince(added) / 86400, 0)
                if days < 45 { value += 0.3 * (1 - days / 45) }
            }
            if ChannelOrder.matchesRegion(show.group, short: region.short, long: region.long) { value += 0.1 }
            return value
        }
        let sorted = pool.map { ($0, score($0)) }.sorted { $0.1 > $1.1 }
        var seen = Set<String>()
        var result: [SeriesShow] = []
        for (show, _) in sorted where seen.insert(titleKey(show.title)).inserted {
            result.append(show)
            if result.count >= limit { break }
        }
        return (result, areNew)
    }

    /// Serier som ligner på det brukeren har sett og lagret. Uten historikk: godt vurderte serier.
    static func recommendations(catalog: Catalog, seeds: [(show: SeriesShow, weight: Double)],
                                limit: Int = 20, now: Date = .now) -> (shows: [SeriesShow], personal: Bool) {
        let region = ChannelOrder.regionKeywords()
        var genreWeights: [String: Double] = [:]
        var groupWeights: [String: Double] = [:]
        var excluded = Set<String>()
        for seed in seeds {
            for genre in genres(seed.show.genre) { genreWeights[genre, default: 0] += seed.weight }
            groupWeights[seed.show.group, default: 0] += seed.weight
            excluded.insert(titleKey(seed.show.title))
        }
        let genreTotal = genreWeights.values.reduce(0, +)
        let groupTotal = groupWeights.values.reduce(0, +)
        let personal = genreTotal > 0 || groupTotal > 0

        var scored: [(show: SeriesShow, score: Double)] = []
        for show in catalog.series where !isAdult(show.group) {
            if excluded.contains(titleKey(show.title)) { continue }
            let rating = show.rating ?? 0
            var score: Double
            if personal {
                var taste = 0.0
                if genreTotal > 0 {
                    for genre in genres(show.genre) { taste += (genreWeights[genre] ?? 0) / genreTotal }
                }
                if groupTotal > 0 {
                    taste += 0.5 * (groupWeights[show.group] ?? 0) / groupTotal
                }
                guard taste > 0 else { continue }
                score = taste + rating / 10 * 0.4
            } else {
                guard rating >= 7 else { continue }
                score = rating / 10
            }
            if let added = show.added {
                let days = now.timeIntervalSince(added) / 86400
                if days < 365 { score += 0.2 * (1 - max(days, 0) / 365) }
            }
            if ChannelOrder.matchesRegion(show.group, short: region.short, long: region.long) { score += 0.15 }
            if show.logo == nil { score -= 0.3 }
            scored.append((show, score))
        }
        scored.sort { $0.score > $1.score }

        var seen = Set<String>()
        var result: [SeriesShow] = []
        for entry in scored where seen.insert(titleKey(entry.show.title)).inserted {
            result.append(entry.show)
            if result.count >= limit { break }
        }
        // For lite å gå på: vis populære serier i stedet.
        if personal && result.count < 4 {
            return recommendations(catalog: catalog, seeds: [], limit: limit, now: now)
        }
        return (result, personal)
    }
}
