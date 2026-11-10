import Foundation

/// Innholdet i listen, sortert i kanaler, filmer og serier.
nonisolated struct Catalog: Sendable {
    var live: [MediaItem] = []
    var movies: [MediaItem] = []
    var series: [SeriesShow] = []
    var sports: [MediaItem] = []
    var liveGroups: [String] = []
    var movieGroups: [String] = []
    var seriesGroups: [String] = []
    var byID: [String: MediaItem] = [:]
    /// Lenke til TV-guide oppgitt i listen, hvis noen.
    var epgURL: String?

    var isEmpty: Bool { live.isEmpty && movies.isEmpty && series.isEmpty }

    static let sportKeywords = [
        "sport", "fotball", "football", "soccer", "hockey", "ishockey", "tennis", "golf",
        "f1", "formula", "racing", "nba", "nhl", "nfl", "mlb", "ufc", "boxing", "boksing",
        "handball", "håndball", "eurosport", "espn", "dazn", "liga", "league",
        "deporte", "esporte", "desporto", "urheilu", "calcio", "fútbol", "futbol", "futebol", "voetbal",
        "jalkapallo", "spor ", "体育"
    ]

    static func isSport(_ item: MediaItem) -> Bool {
        let text = (item.name + " " + item.group).lowercased()
        return sportKeywords.contains { text.contains($0) }
    }

    static func build(from text: String) -> Catalog {
        let items = M3UParser.parse(text)
        var catalog = Catalog()
        catalog.epgURL = M3UParser.headerEPGURL(text)
        var liveSeen = Set<String>()
        var movieSeen = Set<String>()
        var seriesSeen = Set<String>()
        var showIndex: [String: Int] = [:]

        for item in items {
            catalog.byID[item.id] = item
            switch item.kind {
            case .live:
                catalog.live.append(item)
                if liveSeen.insert(item.group).inserted { catalog.liveGroups.append(item.group) }
                if isSport(item) { catalog.sports.append(item) }
            case .movie:
                catalog.movies.append(item)
                if movieSeen.insert(item.group).inserted { catalog.movieGroups.append(item.group) }
            case .series:
                let title = item.seriesTitle ?? item.name
                let key = title.lowercased() + "|" + item.group
                if let index = showIndex[key] {
                    catalog.series[index].episodes.append(item)
                } else {
                    showIndex[key] = catalog.series.count
                    catalog.series.append(SeriesShow(id: key, title: title, group: item.group, logo: item.logo, episodes: [item]))
                }
                if seriesSeen.insert(item.group).inserted { catalog.seriesGroups.append(item.group) }
            }
        }

        for i in catalog.series.indices {
            catalog.series[i].episodes.sort {
                ($0.season ?? 1, $0.episode ?? 0) < ($1.season ?? 1, $1.episode ?? 0)
            }
            catalog.series[i].seasons = Array(Set(catalog.series[i].episodes.map { $0.season ?? 1 })).sorted()
            if catalog.series[i].logo == nil {
                catalog.series[i].logo = catalog.series[i].episodes.first(where: { $0.logo != nil })?.logo
            }
        }
        return catalog
    }
}
