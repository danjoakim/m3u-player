import Foundation

nonisolated enum ContentKind: String, Codable, Sendable {
    case live, movie, series

    var label: String {
        switch self {
        case .live: String(localized: "Live")
        case .movie: String(localized: "Movie")
        case .series: String(localized: "Series")
        }
    }
}

/// Én oppføring fra M3U-listen: en kanal, en film eller en episode.
nonisolated struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let url: URL
    let logo: URL?
    let group: String
    let tvgID: String?
    let kind: ContentKind
    let seriesTitle: String?
    let season: Int?
    let episode: Int?
    /// Når leverandøren la den til (bare Xtream).
    var added: Date? = nil

    var episodeCode: String? {
        guard let season, let episode else { return nil }
        return "S\(season):E\(episode)"
    }
}

/// En serie satt sammen av episoder med samme tittel.
nonisolated struct SeriesShow: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let group: String
    var logo: URL?
    var episodes: [MediaItem]
    var seasons: [Int] = []
    /// Xtream-ID; episodene hentes da først når serien åpnes.
    var seriesID: String? = nil
    var genre: String? = nil
    var rating: Double? = nil
    /// Når serien ble lagt til eller fikk nye episoder (bare Xtream).
    var added: Date? = nil

    static func == (lhs: SeriesShow, rhs: SeriesShow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Hvor langt man har sett i en film eller episode.
nonisolated struct WatchState: Codable, Sendable {
    var position: Double
    var duration: Double
    var date: Date
    /// Selve episoden/filmen, så «Fortsett å se» virker også for episoder som hentes ved behov.
    var item: MediaItem? = nil

    var fraction: Double { duration > 0 ? position / duration : 0 }
}
