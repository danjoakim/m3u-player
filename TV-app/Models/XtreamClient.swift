import Foundation

nonisolated struct XtreamCredentials: Sendable {
    let server: String
    let username: String
    let password: String

    /// Brukernavn og passord trygt kodet for bruk i adresser (…/live/bruker/passord/123.m3u8).
    var pathUsername: String { Self.pathEncode(username) }
    var pathPassword: String { Self.pathEncode(password) }

    private static func pathEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func streamURL(_ kind: String, id: String, ext: String) -> URL? {
        URL(string: "\(server)/\(kind)/\(pathUsername)/\(pathPassword)/\(id).\(ext)")
    }

    func apiURL(_ action: String, _ extra: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: server + "/player_api.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: action)
        ] + extra
        return components.url
    }
}

/// Info om en film.
nonisolated struct VODInfo: Sendable {
    var plot: String?
    var genre: String?
    var director: String?
    var cast: String?
    var year: String?
    var durationText: String?
    var rating: String?
    var poster: URL?
    var backdrop: URL?
    var trailer: URL?
}

/// Info om en episode.
nonisolated struct EpisodeInfo: Sendable {
    var season: Int?
    var number: Int?
    var ext: String?
    var title: String?
    var plot: String?
    var image: URL?
    var durationText: String?
}

/// Info om en serie, med episodeinfo per episode-ID.
nonisolated struct SeriesInfo: Sendable {
    var plot: String?
    var genre: String?
    var director: String?
    var cast: String?
    var year: String?
    var rating: String?
    var poster: URL?
    var backdrop: URL?
    var episodes: [String: EpisodeInfo] = [:]
}

/// Henter info om filmer og serier fra Xtream Codes sitt API.
nonisolated enum XtreamClient {
    /// ID-en i en Xtream-adresse, f.eks. 12345 i …/movie/bruker/passord/12345.mkv.
    static func streamID(from url: URL, kind: String) -> String? {
        guard url.path.split(separator: "/").contains(Substring(kind)) else { return nil }
        let id = (url.lastPathComponent as NSString).deletingPathExtension
        return id.isEmpty ? nil : id
    }

    static func vodInfo(_ credentials: XtreamCredentials, id: String) async -> VODInfo? {
        guard let url = credentials.apiURL("get_vod_info", [URLQueryItem(name: "vod_id", value: id)]),
              let root = await json(url) as? [String: Any],
              let info = root["info"] as? [String: Any] else { return nil }
        var result = VODInfo()
        result.plot = text(info["plot"]) ?? text(info["description"])
        result.genre = text(info["genre"])
        result.director = text(info["director"])
        result.cast = text(info["cast"]) ?? text(info["actors"])
        result.year = year(text(info["releasedate"]) ?? text(info["release_date"]) ?? text(info["year"]))
        result.durationText = duration(info)
        result.rating = rating(info["rating"])
        result.poster = link(info["movie_image"]) ?? link(info["cover_big"])
        result.backdrop = backdrop(info["backdrop_path"])
        if let trailer = text(info["youtube_trailer"]) {
            result.trailer = trailer.hasPrefix("http") ? URL(string: trailer) : URL(string: "https://www.youtube.com/watch?v=" + trailer)
        }
        return result
    }

    static func seriesInfo(_ credentials: XtreamCredentials, id: String) async -> SeriesInfo? {
        guard let url = credentials.apiURL("get_series_info", [URLQueryItem(name: "series_id", value: id)]),
              let root = await json(url) as? [String: Any] else { return nil }
        var result = SeriesInfo()
        if let info = root["info"] as? [String: Any] {
            result.plot = text(info["plot"])
            result.genre = text(info["genre"])
            result.director = text(info["director"])
            result.cast = text(info["cast"])
            result.year = year(text(info["releaseDate"]) ?? text(info["release_date"]))
            result.rating = rating(info["rating"])
            result.poster = link(info["cover"])
            result.backdrop = backdrop(info["backdrop_path"])
        }
        var seasons: [(Int?, [[String: Any]])] = []
        if let dict = root["episodes"] as? [String: Any] {
            seasons = dict.compactMap { key, value in (value as? [[String: Any]]).map { (Int(key), $0) } }
        } else if let array = root["episodes"] as? [[[String: Any]]] {
            seasons = array.enumerated().map { (Optional($0.offset + 1), $0.element) }
        }
        for (seasonNumber, season) in seasons {
            for episode in season {
                guard let episodeID = text(episode["id"]) else { continue }
                let info = episode["info"] as? [String: Any]
                var item = EpisodeInfo()
                item.season = number(episode["season"]).map { Int($0) } ?? seasonNumber
                item.number = number(episode["episode_num"]).map { Int($0) }
                item.ext = text(episode["container_extension"])
                item.title = cleanEpisodeTitle(text(episode["title"]))
                item.plot = text(info?["plot"])
                item.image = link(info?["movie_image"])
                item.durationText = info.flatMap(duration)
                result.episodes[episodeID] = item
            }
        }
        return result
    }

    /// Navn → serie-ID for alle serier hos leverandøren.
    static func seriesIndex(_ credentials: XtreamCredentials) async -> [String: String] {
        guard let url = credentials.apiURL("get_series"),
              let list = await json(url, timeout: 90) as? [[String: Any]] else { return [:] }
        var index: [String: String] = [:]
        for entry in list {
            guard let name = text(entry["name"]), let id = text(entry["series_id"]) else { continue }
            for key in keys(for: name) where index[key] == nil {
                index[key] = id
            }
        }
        return index
    }

    static func lookup(_ title: String, in index: [String: String]) -> String? {
        for key in keys(for: title) {
            if let id = index[key] { return id }
        }
        return nil
    }

    /// «Breaking Bad (2008)» gir både «breakingbad2008» og «breakingbad».
    private static let yearPattern = try! NSRegularExpression(pattern: #"[\(\[]\s*\d{4}\s*[\)\]]"#)

    static func keys(for name: String) -> [String] {
        let cleaned = normalize(TitleCleaner.clean(name))
        let full = normalize(name)
        var result: [String] = []
        if !cleaned.isEmpty { result.append(cleaned) }
        if name.contains("(") || name.contains("[") {
            let stripped = yearPattern.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name),
                                                                withTemplate: "")
            let withoutYear = normalize(stripped)
            if !withoutYear.isEmpty, !result.contains(withoutYear) { result.append(withoutYear) }
        }
        if !full.isEmpty, !result.contains(full) { result.append(full) }
        return result
    }

    static func normalizedKey(_ value: String) -> String { normalize(value) }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Hjelpere

    static func json(_ url: URL, timeout: TimeInterval = 30) async -> Any? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func text(_ value: Any?) -> String? {
        let raw: String?
        if let string = value as? String {
            raw = string
        } else if let number = value as? NSNumber {
            raw = number.stringValue
        } else {
            raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              !["0", "null", "n/a", "none"].contains(trimmed.lowercased()) else { return nil }
        return trimmed
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    static func link(_ value: Any?) -> URL? {
        guard let string = text(value), string.lowercased().hasPrefix("http") else { return nil }
        return URL(string: string)
    }

    static func backdrop(_ value: Any?) -> URL? {
        if let array = value as? [Any] {
            return array.lazy.compactMap { link($0) }.first
        }
        return link(value)
    }

    static func rating(_ value: Any?) -> String? {
        guard let number = number(value), number > 0 else { return nil }
        return number.formatted(.number.precision(.fractionLength(1)))
    }

    static func year(_ date: String?) -> String? {
        guard let date, date.count >= 4 else { return nil }
        let prefix = String(date.prefix(4))
        return Int(prefix) != nil ? prefix : nil
    }

    private static func duration(_ info: [String: Any]) -> String? {
        if let seconds = number(info["duration_secs"]), seconds > 0 {
            return EPGProgramme.format(minutes: Int(seconds / 60))
        }
        return text(info["duration"])
    }

    /// «Serie - S01E02 - Tittel» → «Tittel».
    private static func cleanEpisodeTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let parts = title.components(separatedBy: " - ")
        if parts.count >= 3, let last = parts.last?.trimmingCharacters(in: .whitespaces), !last.isEmpty {
            return last
        }
        return title
    }
}

/// Et utvalgt element til toppkarusellen på forsiden.
nonisolated struct FeaturedItem: Codable, Sendable, Identifiable, Hashable {
    enum Kind: String, Codable, Sendable { case movie, series }

    var kind: Kind
    /// stream_id for filmer, series_id for serier.
    var sourceID: String
    var title: String
    var backdrop: URL?
    var poster: URL?
    var plot: String?
    var year: String?
    var genre: String?
    var rating: String?
    var added: Date

    var id: String { kind.rawValue + ":" + sourceID }
}

nonisolated extension XtreamClient {
    /// Nylig lagt til, godt vurdert, og med bakgrunnsbilde i god kvalitet.
    static func featured(_ credentials: XtreamCredentials, limit: Int = 6) async -> [FeaturedItem] {
        guard let seriesURL = credentials.apiURL("get_series"),
              let vodURL = credentials.apiURL("get_vod_streams") else { return [] }
        async let seriesJSON = json(seriesURL, timeout: 90)
        async let vodJSON = json(vodURL, timeout: 90)
        let (seriesAny, vodAny) = await (seriesJSON, vodJSON)

        var series: [FeaturedItem] = []
        for entry in (seriesAny as? [[String: Any]]) ?? [] {
            guard let id = text(entry["series_id"]), let name = text(entry["name"]),
                  let backdrop = backdrop(entry["backdrop_path"]),
                  (number(entry["rating"]) ?? 0) >= 6.5 else { continue }
            series.append(FeaturedItem(
                kind: .series, sourceID: id, title: name, backdrop: backdrop,
                poster: link(entry["cover"]), plot: text(entry["plot"]),
                year: year(text(entry["releaseDate"]) ?? text(entry["release_date"])),
                genre: text(entry["genre"]), rating: rating(entry["rating"]),
                added: Date(timeIntervalSince1970: number(entry["last_modified"]) ?? 0)
            ))
        }
        series.sort { $0.added > $1.added }

        // Filmlisten har ikke bakgrunnsbilder, så vi henter info for de nyeste godt vurderte.
        var candidates: [(id: String, name: String, added: Double, poster: URL?)] = []
        for entry in (vodAny as? [[String: Any]]) ?? [] {
            guard let id = text(entry["stream_id"]), let name = text(entry["name"]) else { continue }
            let score = number(entry["rating"]) ?? (number(entry["rating_5based"]).map { $0 * 2 } ?? 0)
            guard score >= 6.5 else { continue }
            candidates.append((id, name, number(entry["added"]) ?? 0, link(entry["stream_icon"])))
        }
        candidates.sort { $0.added > $1.added }

        var movies: [FeaturedItem] = []
        for candidate in candidates.prefix(10) {
            guard let info = await vodInfo(credentials, id: candidate.id), let backdrop = info.backdrop else { continue }
            movies.append(FeaturedItem(
                kind: .movie, sourceID: candidate.id, title: candidate.name, backdrop: backdrop,
                poster: info.poster ?? candidate.poster, plot: info.plot, year: info.year,
                genre: info.genre, rating: info.rating,
                added: Date(timeIntervalSince1970: candidate.added)
            ))
            if movies.count >= (limit + 1) / 2 { break }
        }

        // Annenhver serie og film.
        var result: [FeaturedItem] = []
        var seriesIterator = series.prefix(limit).makeIterator()
        var movieIterator = movies.makeIterator()
        while result.count < limit {
            let nextSeries = seriesIterator.next()
            let nextMovie = movieIterator.next()
            if nextSeries == nil && nextMovie == nil { break }
            if let nextSeries { result.append(nextSeries) }
            if let nextMovie, result.count < limit { result.append(nextMovie) }
        }
        return result
    }
}
