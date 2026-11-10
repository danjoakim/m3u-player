import Foundation

/// Rådata fra Xtream sitt API. Lagres på enheten, så appen starter raskt neste gang.
/// Inneholder ikke brukernavn eller passord.
nonisolated struct XtreamPayload: Sendable {
    static let actions = ["get_live_categories", "get_live_streams",
                          "get_vod_categories", "get_vod_streams",
                          "get_series_categories", "get_series"]

    var data: [String: Data]

    private static func fileURL(_ action: String, in directory: URL) -> URL {
        directory.appending(path: "xtream-\(action).json")
    }

    func write(to directory: URL) {
        for (action, value) in data {
            try? value.write(to: Self.fileURL(action, in: directory), options: .atomic)
        }
    }

    static func read(from directory: URL) -> XtreamPayload? {
        var result: [String: Data] = [:]
        for action in actions {
            guard let value = try? Data(contentsOf: fileURL(action, in: directory)) else { return nil }
            result[action] = value
        }
        return XtreamPayload(data: result)
    }

    static func remove(from directory: URL) {
        for action in actions { try? FileManager.default.removeItem(at: fileURL(action, in: directory)) }
    }

    static func modified(in directory: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL("get_live_streams", in: directory).path)
        return attributes?[.modificationDate] as? Date
    }
}

nonisolated extension Catalog {
    /// Bygger katalogen fra Xtream-API-et: kanaler, filmer og serieoversikt (uten episoder).
    static func build(xtream payload: XtreamPayload, credentials: XtreamCredentials) -> Catalog {
        func list(_ action: String) -> [[String: Any]] {
            guard let data = payload.data[action],
                  let value = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return value
        }
        func categories(_ action: String) -> (names: [String: String], order: [String]) {
            var names: [String: String] = [:]
            var order: [String] = []
            for entry in list(action) {
                guard let id = XtreamClient.text(entry["category_id"]),
                      let name = XtreamClient.text(entry["category_name"]) else { continue }
                names[id] = name
                order.append(id)
            }
            return (names, order)
        }
        /// Legger elementene i kategorienes rekkefølge.
        func ordered<T>(_ buckets: [String: [T]], order: [String]) -> [(String, [T])] {
            var result: [(String, [T])] = []
            var seen = Set<String>()
            for id in order where buckets[id] != nil {
                result.append((id, buckets[id]!))
                seen.insert(id)
            }
            for (id, items) in buckets where !seen.contains(id) {
                result.append((id, items))
            }
            return result
        }
        func timestamp(_ value: Any?) -> Date? {
            guard let seconds = XtreamClient.number(value), seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        func score(_ entry: [String: Any]) -> Double? {
            if let value = XtreamClient.number(entry["rating"]), value > 0 { return value }
            if let value = XtreamClient.number(entry["rating_5based"]), value > 0 { return value * 2 }
            return nil
        }
        let uncategorized = String(localized: "Uncategorized")
        var catalog = Catalog()

        // Direktekanaler
        let liveCategories = categories("get_live_categories")
        var liveBuckets: [String: [MediaItem]] = [:]
        for entry in list("get_live_streams") {
            guard let id = XtreamClient.text(entry["stream_id"]),
                  let name = XtreamClient.text(entry["name"]),
                  let url = credentials.streamURL("live", id: id, ext: "m3u8") else { continue }
            let categoryID = XtreamClient.text(entry["category_id"]) ?? ""
            liveBuckets[categoryID, default: []].append(MediaItem(
                id: url.absoluteString, name: TitleCleaner.cleanChannel(name), url: url, logo: XtreamClient.link(entry["stream_icon"]),
                group: liveCategories.names[categoryID] ?? uncategorized,
                tvgID: XtreamClient.text(entry["epg_channel_id"]), kind: .live,
                seriesTitle: nil, season: nil, episode: nil))
        }
        for (categoryID, items) in ordered(liveBuckets, order: liveCategories.order) {
            catalog.liveGroups.append(liveCategories.names[categoryID] ?? uncategorized)
            catalog.live.append(contentsOf: items)
        }

        // Filmer
        let vodCategories = categories("get_vod_categories")
        var vodBuckets: [String: [MediaItem]] = [:]
        for entry in list("get_vod_streams") {
            guard let id = XtreamClient.text(entry["stream_id"]),
                  let name = XtreamClient.text(entry["name"]) else { continue }
            let ext = XtreamClient.text(entry["container_extension"]) ?? "mp4"
            guard let url = credentials.streamURL("movie", id: id, ext: ext) else { continue }
            let categoryID = XtreamClient.text(entry["category_id"]) ?? ""
            vodBuckets[categoryID, default: []].append(MediaItem(
                id: url.absoluteString, name: TitleCleaner.clean(name), url: url, logo: XtreamClient.link(entry["stream_icon"]),
                group: vodCategories.names[categoryID] ?? uncategorized,
                tvgID: nil, kind: .movie, seriesTitle: nil, season: nil, episode: nil,
                added: timestamp(entry["added"])))
        }
        for (categoryID, items) in ordered(vodBuckets, order: vodCategories.order) {
            catalog.movieGroups.append(vodCategories.names[categoryID] ?? uncategorized)
            catalog.movies.append(contentsOf: items)
        }

        // Serier (episodene hentes når serien åpnes)
        let seriesCategories = categories("get_series_categories")
        var seriesBuckets: [String: [SeriesShow]] = [:]
        var usedIDs = Set<String>()
        for entry in list("get_series") {
            guard let seriesID = XtreamClient.text(entry["series_id"]),
                  let name = XtreamClient.text(entry["name"]) else { continue }
            let categoryID = XtreamClient.text(entry["category_id"]) ?? ""
            let group = seriesCategories.names[categoryID] ?? uncategorized
            var key = name.lowercased() + "|" + group
            if !usedIDs.insert(key).inserted {
                key += "|" + seriesID
                usedIDs.insert(key)
            }
            seriesBuckets[categoryID, default: []].append(SeriesShow(
                id: key, title: TitleCleaner.clean(name), group: group, logo: XtreamClient.link(entry["cover"]),
                episodes: [], seasons: [], seriesID: seriesID,
                genre: XtreamClient.text(entry["genre"]), rating: score(entry),
                added: timestamp(entry["last_modified"])))
        }
        for (categoryID, shows) in ordered(seriesBuckets, order: seriesCategories.order) {
            catalog.seriesGroups.append(seriesCategories.names[categoryID] ?? uncategorized)
            catalog.series.append(contentsOf: shows)
        }

        catalog.byID.reserveCapacity(catalog.live.count + catalog.movies.count)
        for item in catalog.live { catalog.byID[item.id] = item }
        for item in catalog.movies { catalog.byID[item.id] = item }
        catalog.sports = catalog.live.filter { isSport($0) }
        return catalog
    }
}
