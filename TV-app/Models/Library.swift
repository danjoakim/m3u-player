import Foundation
import Observation

enum LibraryError: LocalizedError {
    case notPlaylist
    case empty

    var errorDescription: String? {
        switch self {
        case .notPlaylist: String(localized: "The file doesn't look like an M3U playlist.")
        case .empty: String(localized: "The playlist contains no channels, movies or series.")
        }
    }
}

/// Appens tilstand: innholdet fra listen, favoritter, hva man har sett og hva som spilles nå.
@Observable
final class Library {
    private(set) var catalog = Catalog()
    private(set) var isLoading = false
    private(set) var isSample = false
    /// True mens lagret liste leses inn ved oppstart.
    private(set) var isRestoring = true
    private(set) var lastUpdated: Date?
    private(set) var favorites: Set<String>
    private(set) var watch: [String: WatchState]
    var errorMessage: String?
    var playlistURL: String
    var nowPlaying: MediaItem?

    // TV-guide
    private(set) var epg: EPGData? {
        didSet { refreshSports() }
    }
    private(set) var isLoadingEPG = false
    var epgError: String?
    var epgURL: String

    /// Navnet som vises på forsiden, f.eks. «Fortsett å se for Dan».
    var profileName: String {
        didSet { UserDefaults.standard.set(profileName, forKey: Keys.profileName) }
    }

    /// Starter neste episode automatisk når en episode er ferdig. På som standard.
    var autoplayNext: Bool {
        didSet { UserDefaults.standard.set(autoplayNext, forKey: Keys.autoplayNext) }
    }

    // Antall per kategori
    private(set) var liveCategoryCounts: [String: Int] = [:]
    private(set) var movieCategoryCounts: [String: Int] = [:]
    private(set) var seriesCategoryCounts: [String: Int] = [:]

    // Voksent innhold
    /// Skjuler kategorier som XXX, Adult og 18+ overalt i appen. På som standard.
    private(set) var hideAdult: Bool
    private(set) var visibleMovies: [MediaItem] = []
    private(set) var visibleSeries: [SeriesShow] = []
    private(set) var visibleMovieGroups: [String] = []
    private(set) var visibleSeriesGroups: [String] = []
    /// Antall kategorier med voksent innhold i listen.
    private(set) var adultCategoryCount = 0
    @ObservationIgnored private var adultGroups = Set<String>()

    // Kanalrekkefølge
    /// Alle direktekategorier i valgt rekkefølge (også skjulte).
    private(set) var orderedLiveGroups: [String] = []
    /// Synlige direktekanaler i valgt rekkefølge.
    private(set) var orderedLive: [MediaItem] = []
    private(set) var orderedSports: [MediaItem] = []
    /// Brukerens egen rekkefølge. Tom betyr automatisk (eget land først).
    private(set) var liveGroupOrder: [String]
    private(set) var hiddenLiveGroups: Set<String>

    /// Kanaler og filmer som trenger VLC. Huskes så de starter rett i VLC neste gang.
    private(set) var vlcItems: Set<String>

    var visibleLiveGroups: [String] {
        orderedLiveGroups.filter { !hiddenLiveGroups.contains($0) }
    }

    // Fremdrift
    private(set) var playlistProgress: LoadProgress?
    private(set) var epgProgress: LoadProgress?

    // Kilde: M3U-lenke eller Xtream Codes
    var sourceKind: SourceKind
    var xtreamServer: String
    var xtreamUsername: String
    var xtreamPassword: String
    private(set) var xtreamExpiry: Date?

    private var didBootstrap = false

    private enum Keys {
        static let url = "playlistURL"
        static let favorites = "favorites"
        static let watch = "watchState"
        static let epg = "epgURL"
        static let source = "sourceKind"
        static let groupOrder = "liveGroupOrder"
        static let hiddenGroups = "hiddenLiveGroups"
        static let vlcItems = "vlcItems"
        static let hideAdult = "hideAdult"
        static let autoplayNext = "autoplayNext"
        static let profileName = "profileName"
        static let xtreamServer = "xtreamServer"
        static let xtreamUsername = "xtreamUsername"
        static let xtreamPassword = "xtreamPassword"
        static let xtreamExpiry = "xtreamExpiry"
    }

    private static var epgCacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "epg.json")
    }

    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "playlist.m3u")
    }

    /// Lagrede filer ligger i Application Support, som iOS ikke tømmer.
    /// Flytter filer fra den gamle plasseringen (Caches) første gang.
    private static func prepareStorage() {
        let fm = FileManager.default
        try? fm.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        for name in ["playlist.m3u", "epg.json"] {
            let old = URL.cachesDirectory.appending(path: name)
            let new = URL.applicationSupportDirectory.appending(path: name)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                try? fm.moveItem(at: old, to: new)
            }
        }
    }

    /// Stabil nøkkel for en guide-adresse, så passord ikke lagres i klartekst.
    private static func sourceKey(_ url: URL) -> String {
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 16)
    }

    private var canRefreshPlaylist: Bool {
        switch sourceKind {
        case .m3u: !playlistURL.isEmpty
        case .xtream: !xtreamServer.isEmpty && !xtreamUsername.isEmpty && !xtreamPassword.isEmpty
        }
    }

    init() {
        Self.prepareStorage()
        let defaults = UserDefaults.standard
        playlistURL = defaults.string(forKey: Keys.url) ?? ""
        epgURL = defaults.string(forKey: Keys.epg) ?? ""
        liveGroupOrder = defaults.stringArray(forKey: Keys.groupOrder) ?? []
        hiddenLiveGroups = Set(defaults.stringArray(forKey: Keys.hiddenGroups) ?? [])
        vlcItems = Set(defaults.stringArray(forKey: Keys.vlcItems) ?? [])
        hideAdult = defaults.object(forKey: Keys.hideAdult) as? Bool ?? true
        autoplayNext = defaults.object(forKey: Keys.autoplayNext) as? Bool ?? true
        profileName = defaults.string(forKey: Keys.profileName) ?? ""
        sourceKind = SourceKind(rawValue: defaults.string(forKey: Keys.source) ?? "") ?? .m3u
        xtreamServer = defaults.string(forKey: Keys.xtreamServer) ?? ""
        xtreamUsername = defaults.string(forKey: Keys.xtreamUsername) ?? ""
        xtreamPassword = Keychain.get(Keys.xtreamPassword) ?? ""
        xtreamExpiry = defaults.object(forKey: Keys.xtreamExpiry) as? Date
        favorites = Set(defaults.stringArray(forKey: Keys.favorites) ?? [])
        if let data = defaults.data(forKey: Keys.watch),
           let decoded = try? JSONDecoder().decode([String: WatchState].self, from: data) {
            watch = decoded
        } else {
            watch = [:]
        }
    }

    // MARK: - Lasting

    /// Leser sist lagrede liste fra enheten, ellers eksempelinnhold.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        defer { isRestoring = false }

        // Xtream: les lagrede API-data (rask).
        if sourceKind == .xtream, let credentials = makeXtreamCredentials(),
           let payload = await Self.readPayload() {
            let catalog = await Task.detached(priority: .userInitiated) {
                Catalog.build(xtream: payload, credentials: credentials)
            }.value
            if !catalog.isEmpty {
                restored(catalog, updated: XtreamPayload.modified(in: URL.applicationSupportDirectory))
                return
            }
        }

        // M3U (eller Xtream lagret på den gamle måten).
        if let data = try? Data(contentsOf: Self.cacheURL), let text = Self.decode(data) {
            let catalog = await Self.buildCatalog(text)
            if !catalog.isEmpty {
                let attributes = try? FileManager.default.attributesOfItem(atPath: Self.cacheURL.path)
                restored(catalog, updated: attributes?[.modificationDate] as? Date)
                // Xtream lagret som stor M3U-liste: hent på nytt via API-et i bakgrunnen.
                if sourceKind == .xtream, canRefreshPlaylist {
                    Task { await loadPlaylist() }
                }
                return
            }
        }
        catalog = await Self.buildCatalog(SampleData.m3u)
        rebuildChannelOrder()
        isSample = true
        epg = SampleData.epg()
    }

    private static func readPayload() async -> XtreamPayload? {
        let directory = URL.applicationSupportDirectory
        return await Task.detached(priority: .userInitiated) {
            XtreamPayload.read(from: directory)
        }.value
    }

    /// Viser en lagret katalog og starter bakgrunnsjobbene.
    private func restored(_ catalog: Catalog, updated: Date?) {
        self.catalog = catalog
        rebuildChannelOrder()
        isSample = false
        lastUpdated = updated
        // Kanalene vises med en gang; TV-guiden og toppkarusellen lastes i bakgrunnen.
        Task { await restoreEPG() }
        Task { await loadFeatured() }
        // Er listen eldre enn ett døgn, oppdateres den stille i bakgrunnen.
        let age = updated.map { Date.now.timeIntervalSince($0) } ?? .infinity
        if age > 24 * 3600, canRefreshPlaylist {
            Task { await loadPlaylist() }
        }
    }

    func loadFromURL() async {
        let trimmed = playlistURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            errorMessage = String(localized: "Invalid link. It must start with http:// or https://.")
            return
        }
        playlistURL = trimmed
        UserDefaults.standard.set(trimmed, forKey: Keys.url)

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            playlistProgress = nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            let (data, response) = try await download(request, target: .playlist)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                errorMessage = String(localized: "The server responded with error code \(http.statusCode).")
                return
            }
            try await importData(data)
        } catch {
            errorMessage = String(localized: "Couldn't load the playlist: \(error.localizedDescription)")
        }
    }

    func importFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            playlistProgress = nil
        }

        do {
            let data = try Data(contentsOf: url)
            try await importData(data)
        } catch {
            errorMessage = String(localized: "Couldn't read the file: \(error.localizedDescription)")
        }
    }

    func resetToSample() {
        try? FileManager.default.removeItem(at: Self.cacheURL)
        XtreamPayload.remove(from: URL.applicationSupportDirectory)
        playlistURL = ""
        UserDefaults.standard.removeObject(forKey: Keys.url)
        errorMessage = nil
        lastUpdated = nil
        try? FileManager.default.removeItem(at: Self.epgCacheURL)
        epgURL = ""
        UserDefaults.standard.removeObject(forKey: Keys.epg)
        epgError = nil
        Task {
            catalog = await Self.buildCatalog(SampleData.m3u)
            rebuildChannelOrder()
            featured = []
            isSample = true
            epg = SampleData.epg()
        }
    }

    private func importData(_ data: Data) async throws {
        guard let text = Self.decode(data), text.contains("#EXTINF") else {
            throw LibraryError.notPlaylist
        }
        playlistProgress = LoadProgress(phase: .processing)
        let catalog = await Self.buildCatalog(text)
        guard !catalog.isEmpty else { throw LibraryError.empty }
        try? data.write(to: Self.cacheURL, options: .atomic)
        XtreamPayload.remove(from: URL.applicationSupportDirectory)
        adopt(catalog)
    }

    /// Tar i bruk en ny katalog (etter innlasting fra nettet).
    private func adopt(_ catalog: Catalog) {
        self.catalog = catalog
        rebuildChannelOrder()
        clearMetadata()
        isSample = false
        lastUpdated = .now
        Task { await loadFeatured(force: true) }

        if sourceKind == .m3u, epgURL.isEmpty, let suggested = catalog.epgURL {
            epgURL = suggested
            UserDefaults.standard.set(suggested, forKey: Keys.epg)
        }
        // Behold guiden hvis den kommer fra samme kilde og er fersk, ellers hent ny.
        if epg?.sourceURL.isEmpty == true { epg = nil }   // eksempelguiden
        if let url = resolvedEPGURL() {
            let fresh = epg.map {
                $0.sourceURL == Self.sourceKey(url) && $0.updated > Date.now.addingTimeInterval(-12 * 3600)
            } ?? false
            if !fresh { Task { await loadEPG() } }
        } else {
            epg = nil
        }
    }

    // MARK: - TV-guide

    /// Leser lagret TV-guide, og henter ny i bakgrunnen hvis den er eldre enn 12 timer.
    private func restoreEPG() async {
        if let data = try? Data(contentsOf: Self.epgCacheURL) {
            epg = await Task.detached(priority: .userInitiated) {
                try? JSONDecoder().decode(EPGData.self, from: data)
            }.value
        }
        let key = resolvedEPGURL().map(Self.sourceKey)
        let stale = epg.map { $0.updated < Date.now.addingTimeInterval(-12 * 3600) || $0.sourceURL != key } ?? true
        if stale, resolvedEPGURL() != nil {
            Task { await loadEPG() }
        }
    }

    func loadEPG() async {
        let trimmed = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        epgURL = trimmed
        UserDefaults.standard.set(trimmed, forKey: Keys.epg)
        guard let url = resolvedEPGURL() else {
            epgError = String(localized: "Invalid TV guide link. It must start with http:// or https://.")
            return
        }
        guard !isLoadingEPG else { return }

        isLoadingEPG = true
        epgError = nil
        defer {
            isLoadingEPG = false
            epgProgress = nil
        }

        let key = Self.sourceKey(url)
        let wantedIDs = Set(catalog.live.compactMap { $0.tvgID?.lowercased() }.filter { !$0.isEmpty })
        let wantedNames = Set(catalog.live.map { $0.name.lowercased() })

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            let (data, response) = try await download(request, target: .epg)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                epgError = String(localized: "The TV guide server responded with error code \(http.statusCode).")
                return
            }
            epgProgress = LoadProgress(phase: .processing)
            let parsed = try await Task.detached(priority: .utility) {
                try EPGLoader.load(data: data, sourceURL: key, wantedIDs: wantedIDs, wantedNames: wantedNames)
            }.value
            guard !parsed.programmes.isEmpty else {
                epgError = String(localized: "No programs match the channels in your playlist.")
                return
            }
            epg = parsed
            let encoded = try? await Task.detached(priority: .utility) {
                try JSONEncoder().encode(parsed)
            }.value
            if let encoded { try? encoded.write(to: Self.epgCacheURL, options: .atomic) }
        } catch {
            epgError = String(localized: "Couldn't load the TV guide: \(error.localizedDescription)")
        }
    }

    /// TV-guiden som brukes: egen lenke hvis oppgitt, ellers Xtream-kontoens guide.
    func resolvedEPGURL() -> URL? {
        let trimmed = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return url
        }
        if sourceKind == .xtream, !isSample {
            return xtreamURL(path: "xmltv.php")
        }
        return nil
    }

    // MARK: - Xtream Codes

    func loadPlaylist() async {
        guard !isLoading else { return }
        UserDefaults.standard.set(sourceKind.rawValue, forKey: Keys.source)
        switch sourceKind {
        case .m3u: await loadFromURL()
        case .xtream: await loginXtream()
        }
    }

    var normalizedXtreamServer: String? {
        var server = xtreamServer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty else { return nil }
        let lower = server.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            server = "http://" + server
        }
        while server.hasSuffix("/") { server.removeLast() }
        return server
    }

    private func xtreamURL(path: String, extra: [URLQueryItem] = []) -> URL? {
        guard let server = normalizedXtreamServer,
              var components = URLComponents(string: server + "/" + path) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "username", value: xtreamUsername.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "password", value: xtreamPassword)
        ] + extra
        return components.url
    }

    func loginXtream() async {
        let username = xtreamUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        xtreamUsername = username
        guard normalizedXtreamServer != nil, !username.isEmpty, !xtreamPassword.isEmpty else {
            errorMessage = String(localized: "Fill in server, username and password.")
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(xtreamServer.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.xtreamServer)
        defaults.set(username, forKey: Keys.xtreamUsername)
        Keychain.set(xtreamPassword, for: Keys.xtreamPassword)

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            playlistProgress = nil
        }

        guard let apiURL = xtreamURL(path: "player_api.php"),
              let credentials = makeXtreamCredentials() else {
            errorMessage = String(localized: "Invalid link. It must start with http:// or https://.")
            return
        }

        do {
            playlistProgress = LoadProgress(phase: .connecting)
            var apiRequest = URLRequest(url: apiURL)
            apiRequest.timeoutInterval = 30
            let (apiData, _) = try await URLSession.shared.data(for: apiRequest)
            guard let account = XtreamAccount(json: apiData), account.authenticated else {
                errorMessage = String(localized: "Wrong username or password.")
                return
            }
            if let status = account.status, status.lowercased() != "active" {
                errorMessage = String(localized: "The account isn't active (\(status)).")
                return
            }
            xtreamExpiry = account.expiry
            defaults.set(account.expiry, forKey: Keys.xtreamExpiry)

            let payload = try await downloadXtreamPayload(credentials)
            playlistProgress = LoadProgress(phase: .processing)
            let catalog = await Task.detached(priority: .userInitiated) {
                Catalog.build(xtream: payload, credentials: credentials)
            }.value
            guard !catalog.isEmpty else { throw LibraryError.empty }
            let directory = URL.applicationSupportDirectory
            await Task.detached(priority: .utility) { payload.write(to: directory) }.value
            try? FileManager.default.removeItem(at: Self.cacheURL)
            adopt(catalog)
        } catch {
            errorMessage = String(localized: "Couldn't reach the server: \(error.localizedDescription)")
        }
    }

    // MARK: - Nedlasting med fremdrift

    private enum ProgressTarget: Sendable { case playlist, epg }

    private func download(_ request: URLRequest, target: ProgressTarget) async throws -> (Data, URLResponse) {
        setProgress(LoadProgress(phase: .connecting), for: target)
        // Library lever hele appens levetid, så en vanlig referanse er trygg her.
        return try await Downloader.fetch(request) { received, expected in
            Task { @MainActor in
                self.reportDownload(received: received, expected: expected, for: target)
            }
        }
    }

    private func reportDownload(received: Int64, expected: Int64, for target: ProgressTarget) {
        let current = target == .playlist ? playlistProgress : epgProgress
        // Ikke skriv over «Behandler …» eller en ferdig nedlasting med en sen melding.
        guard let current, current.phase != .processing else { return }
        setProgress(LoadProgress(phase: .downloading, received: received, expected: expected), for: target)
    }

    private func setProgress(_ progress: LoadProgress?, for target: ProgressTarget) {
        switch target {
        case .playlist: playlistProgress = progress
        case .epg: epgProgress = progress
        }
    }

    // MARK: - Info om filmer og serier (Xtream)

    @ObservationIgnored private var vodInfoCache: [String: VODInfo] = [:]
    @ObservationIgnored private var seriesInfoCache: [String: SeriesInfo] = [:]
    @ObservationIgnored private var seriesIndex: [String: String]?
    @ObservationIgnored private var seriesIndexTask: Task<[String: String], Never>?

    var xtreamCredentials: XtreamCredentials? {
        isSample ? nil : makeXtreamCredentials()
    }

    private func makeXtreamCredentials() -> XtreamCredentials? {
        guard sourceKind == .xtream, let server = normalizedXtreamServer,
              !xtreamUsername.isEmpty, !xtreamPassword.isEmpty else { return nil }
        return XtreamCredentials(server: server,
                                 username: xtreamUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                                 password: xtreamPassword)
    }

    @ObservationIgnored private var partBytes: [String: Int64] = [:]

    /// Henter kanaler, filmer, serier og kategorier samtidig, med samlet fremdrift.
    private func downloadXtreamPayload(_ credentials: XtreamCredentials) async throws -> XtreamPayload {
        partBytes = [:]
        playlistProgress = LoadProgress(phase: .downloading)
        return try await withThrowingTaskGroup(of: (String, Data).self) { group in
            for action in XtreamPayload.actions {
                guard let url = credentials.apiURL(action) else { continue }
                group.addTask {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 180
                    let (data, response) = try await Downloader.fetch(request) { received, _ in
                        Task { @MainActor in
                            self.reportPart(action, received: received)
                        }
                    }
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                    return (action, data)
                }
            }
            var result: [String: Data] = [:]
            for try await (action, data) in group {
                result[action] = data
            }
            return XtreamPayload(data: result)
        }
    }

    private func reportPart(_ action: String, received: Int64) {
        guard let current = playlistProgress, current.phase != .processing else { return }
        partBytes[action] = received
        playlistProgress = LoadProgress(phase: .downloading, received: partBytes.values.reduce(0, +), expected: 0)
    }

    func vodInfo(for movie: MediaItem) async -> VODInfo? {
        if let cached = vodInfoCache[movie.id] { return cached }
        guard let credentials = xtreamCredentials,
              let id = XtreamClient.streamID(from: movie.url, kind: "movie") else { return nil }
        let info = await XtreamClient.vodInfo(credentials, id: id)
        if let info { vodInfoCache[movie.id] = info }
        return info
    }

    func seriesInfo(for show: SeriesShow) async -> SeriesInfo? {
        if let cached = seriesInfoCache[show.id] { return cached }
        guard let credentials = xtreamCredentials else { return nil }
        let seriesID: String
        if let known = show.seriesID {
            seriesID = known
        } else {
            let index = await loadSeriesIndex(credentials)
            guard let found = XtreamClient.lookup(show.title, in: index) else { return nil }
            seriesID = found
        }
        let info = await XtreamClient.seriesInfo(credentials, id: seriesID)
        if let info { seriesInfoCache[show.id] = info }
        return info
    }

    /// Info om én episode, hvis serien er hentet.
    func episodeInfo(for episode: MediaItem, in info: SeriesInfo?) -> EpisodeInfo? {
        guard let info, let id = XtreamClient.streamID(from: episode.url, kind: "series") else { return nil }
        return info.episodes[id]
    }

    private static var seriesIndexURL: URL {
        URL.applicationSupportDirectory.appending(path: "series-index.json")
    }

    /// Oversikt over alle serier hos leverandøren (navn → ID). Lagres et døgn.
    private func loadSeriesIndex(_ credentials: XtreamCredentials) async -> [String: String] {
        if let seriesIndex { return seriesIndex }
        if let task = seriesIndexTask { return await task.value }
        let fileURL = Self.seriesIndexURL
        let task = Task.detached(priority: .userInitiated) { () -> [String: String] in
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let modified = attributes[.modificationDate] as? Date,
               modified > Date.now.addingTimeInterval(-24 * 3600),
               let data = try? Data(contentsOf: fileURL),
               let cached = try? JSONDecoder().decode([String: String].self, from: data) {
                return cached
            }
            let index = await XtreamClient.seriesIndex(credentials)
            if !index.isEmpty, let data = try? JSONEncoder().encode(index) {
                try? data.write(to: fileURL, options: .atomic)
            }
            return index
        }
        seriesIndexTask = task
        let index = await task.value
        seriesIndex = index
        seriesIndexTask = nil
        return index
    }

    // MARK: - Toppkarusell

    private(set) var featured: [FeaturedItem] = []
    @ObservationIgnored private var movieByStreamID: [String: MediaItem]?
    @ObservationIgnored private var showByKey: [String: SeriesShow]?

    private static var featuredURL: URL {
        URL.applicationSupportDirectory.appending(path: "featured.json")
    }

    /// Henter nye, godt vurderte filmer og serier fra Xtream. Lagres i 12 timer.
    func loadFeatured(force: Bool = false) async {
        guard let credentials = xtreamCredentials else {
            featured = []
            return
        }
        let fileURL = Self.featuredURL
        if !force,
           let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modified = attributes[.modificationDate] as? Date,
           modified > Date.now.addingTimeInterval(-12 * 3600),
           let data = try? Data(contentsOf: fileURL),
           let cached = try? JSONDecoder().decode([FeaturedItem].self, from: data),
           !cached.isEmpty {
            featured = cached
            return
        }
        let items = await Task.detached(priority: .utility) {
            await XtreamClient.featured(credentials)
        }.value
        guard !items.isEmpty else { return }
        featured = items
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func movie(forStreamID id: String) -> MediaItem? {
        if movieByStreamID == nil {
            var map: [String: MediaItem] = [:]
            for movie in catalog.movies {
                if let streamID = XtreamClient.streamID(from: movie.url, kind: "movie") { map[streamID] = movie }
            }
            movieByStreamID = map
        }
        return movieByStreamID?[id]
    }

    func show(named name: String) -> SeriesShow? {
        if showByKey == nil {
            var map: [String: SeriesShow] = [:]
            for show in catalog.series {
                for key in XtreamClient.keys(for: show.title) where map[key] == nil { map[key] = show }
            }
            showByKey = map
        }
        for key in XtreamClient.keys(for: name) {
            if let show = showByKey?[key] { return show }
        }
        return nil
    }

    // MARK: - Episoder ved behov (Xtream)

    /// Episoder hentet når serien åpnes, per serie-ID i appen.
    private(set) var loadedEpisodes: [String: [MediaItem]] = [:]
    @ObservationIgnored private var episodeByID: [String: MediaItem] = [:]

    /// Serien med episodene, også de som er hentet ved behov.
    func resolvedShow(_ show: SeriesShow) -> SeriesShow {
        guard show.episodes.isEmpty, let episodes = loadedEpisodes[show.id] else { return show }
        var copy = show
        copy.episodes = episodes
        copy.seasons = Array(Set(episodes.map { $0.season ?? 1 })).sorted()
        return copy
    }

    /// Henter episodene for en Xtream-serie hvis de ikke er hentet ennå.
    @discardableResult
    func loadEpisodes(for show: SeriesShow) async -> SeriesShow {
        if !show.episodes.isEmpty || loadedEpisodes[show.id] != nil { return resolvedShow(show) }
        guard let credentials = xtreamCredentials, let info = await seriesInfo(for: show) else { return show }
        var items: [MediaItem] = []
        for (episodeID, episode) in info.episodes {
            guard let url = credentials.streamURL("series", id: episodeID, ext: episode.ext ?? "mp4") else { continue }
            let season = episode.season ?? 1
            let number = episode.number ?? 0
            let code = "S\(season)E\(number)"
            items.append(MediaItem(
                id: url.absoluteString,
                name: episode.title.map { "\(show.title) \(code) – \($0)" } ?? "\(show.title) \(code)",
                url: url, logo: episode.image ?? show.logo, group: show.group, tvgID: nil, kind: .series,
                seriesTitle: show.title, season: season, episode: number))
        }
        items.sort { ($0.season ?? 1, $0.episode ?? 0) < ($1.season ?? 1, $1.episode ?? 0) }
        loadedEpisodes[show.id] = items
        for item in items { episodeByID[item.id] = item }
        return resolvedShow(show)
    }

    /// Episoden etter denne i samme serie, eller nil hvis det var den siste.
    func nextEpisode(after item: MediaItem) async -> MediaItem? {
        guard item.kind == .series, let title = item.seriesTitle else { return nil }
        // Samme serie i samme kategori først, så vi ikke hopper til en annen språkversjon.
        let key = XtreamClient.normalizedKey(title)
        guard let show = catalog.series.first(where: {
            $0.group == item.group && XtreamClient.normalizedKey($0.title) == key
        }) ?? show(named: title) else { return nil }
        let full = await loadEpisodes(for: show)
        let episodes = full.episodes
        if let index = episodes.firstIndex(where: { $0.id == item.id }) {
            let next = episodes.index(after: index)
            return next < episodes.endIndex ? episodes[next] : nil
        }
        let current = (item.season ?? 1, item.episode ?? 0)
        return episodes.first { ($0.season ?? 1, $0.episode ?? 0) > current }
    }

    /// Spiller neste episode, og henter episodene først om nødvendig.
    func playNextEpisode(of show: SeriesShow) async {
        let full = await loadEpisodes(for: show)
        if let next = nextEpisode(in: full) { play(next) }
    }

    private func clearMetadata() {
        loadedEpisodes = [:]
        movieByStreamID = nil
        showByKey = nil
        vodInfoCache = [:]
        seriesInfoCache = [:]
        seriesIndex = nil
        try? FileManager.default.removeItem(at: Self.seriesIndexURL)
    }

    // MARK: - Anbefalinger og nytt

    private(set) var recentlyAdded: [NewArrival] = []
    private(set) var topSeries: [SeriesShow] = []
    /// True når «Topp 10» bygger på nye serier (lagt til siste måned).
    private(set) var topSeriesAreNew = false
    private(set) var recommendedShows: [SeriesShow] = []
    /// True når anbefalingene bygger på det brukeren har sett; ellers er det populære serier.
    private(set) var recommendationsArePersonal = false

    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var recommendationsTask: Task<Void, Never>?

    /// «Nylig lagt til» og «Topp 10» beregnes i bakgrunnen.
    private func refreshDiscovery() {
        discoveryTask?.cancel()
        let catalog = self.catalog
        discoveryTask = Task {
            let (recent, top) = await Task.detached(priority: .utility) {
                (Discovery.recentlyAdded(catalog), Discovery.topSeries(catalog))
            }.value
            guard !Task.isCancelled else { return }
            recentlyAdded = recent
            topSeries = top.shows
            topSeriesAreNew = top.areNew
        }
        refreshRecommendations()
    }

    func refreshRecommendations() {
        guard !catalog.series.isEmpty else {
            recommendedShows = []
            recommendationsArePersonal = false
            return
        }
        var seeds: [(show: SeriesShow, weight: Double)] = []
        var seenIDs = Set<String>()
        // Serier man har sett på, nyeste først.
        for (key, state) in watch.sorted(by: { $0.value.date > $1.value.date }).prefix(60) {
            guard let item = catalog.byID[key] ?? episodeByID[key] ?? state.item,
                  item.kind == .series, let title = item.seriesTitle,
                  let show = show(named: title), seenIDs.insert(show.id).inserted else { continue }
            seeds.append((show, 2))
        }
        // Serier i Min liste.
        for show in favoriteShows where seenIDs.insert(show.id).inserted {
            seeds.append((show, 1.5))
        }
        recommendationsTask?.cancel()
        let catalog = self.catalog
        let chosen = seeds
        recommendationsTask = Task {
            let result = await Task.detached(priority: .utility) {
                Discovery.recommendations(catalog: catalog, seeds: chosen)
            }.value
            guard !Task.isCancelled else { return }
            recommendedShows = result.shows
            recommendationsArePersonal = result.personal
        }
    }

    // MARK: - Spillervalg

    func needsVLC(_ id: String) -> Bool {
        vlcItems.contains(id)
    }

    func markNeedsVLC(_ id: String) {
        guard vlcItems.insert(id).inserted else { return }
        UserDefaults.standard.set(Array(vlcItems), forKey: Keys.vlcItems)
    }

    // MARK: - Kanalrekkefølge

    func rebuildChannelOrder() {
        movieByStreamID = nil
        showByKey = nil
        let groups = catalog.liveGroups
        let automatic = ChannelOrder.automatic(groups)
        var order: [String]
        if liveGroupOrder.isEmpty {
            order = automatic
        } else {
            let known = Set(groups)
            order = liveGroupOrder.filter { known.contains($0) }
            let placed = Set(order)
            order += automatic.filter { !placed.contains($0) }
        }
        // Voksent innhold
        adultGroups = Set((groups + catalog.movieGroups + catalog.seriesGroups).filter(Discovery.isAdult))
        adultCategoryCount = adultGroups.count
        if hideAdult, !adultGroups.isEmpty {
            order = order.filter { !adultGroups.contains($0) }
            visibleMovies = catalog.movies.filter { !adultGroups.contains($0.group) }
            visibleSeries = catalog.series.filter { !adultGroups.contains($0.group) }
            visibleMovieGroups = catalog.movieGroups.filter { !adultGroups.contains($0) }
            visibleSeriesGroups = catalog.seriesGroups.filter { !adultGroups.contains($0) }
        } else {
            visibleMovies = catalog.movies
            visibleSeries = catalog.series
            visibleMovieGroups = catalog.movieGroups
            visibleSeriesGroups = catalog.seriesGroups
        }

        orderedLiveGroups = order

        let rank = Dictionary(uniqueKeysWithValues: order
            .filter { !hiddenLiveGroups.contains($0) }
            .enumerated()
            .map { ($0.element, $0.offset) })
        orderedLive = catalog.live.enumerated()
            .compactMap { entry -> (Int, Int, MediaItem)? in
                guard let r = rank[entry.element.group] else { return nil }
                return (r, entry.offset, entry.element)
            }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map { $0.2 }
        orderedSports = orderedLive.filter { Catalog.isSport($0) }
        refreshSports()

        // Antall per kategori, til kategorilisten.
        var live: [String: Int] = [:]
        for item in catalog.live { live[item.group, default: 0] += 1 }
        var movies: [String: Int] = [:]
        for item in catalog.movies { movies[item.group, default: 0] += 1 }
        var series: [String: Int] = [:]
        for show in catalog.series { series[show.group, default: 0] += 1 }
        liveCategoryCounts = live
        movieCategoryCounts = movies
        seriesCategoryCounts = series
        refreshDiscovery()
    }

    /// Lagrer brukerens rekkefølge og skjulte kategorier.
    func setLiveGroups(order: [String], hidden: Set<String>) {
        let automatic = ChannelOrder.automatic(catalog.liveGroups)
        liveGroupOrder = order == automatic ? [] : order
        hiddenLiveGroups = hidden
        UserDefaults.standard.set(liveGroupOrder, forKey: Keys.groupOrder)
        UserDefaults.standard.set(Array(hidden), forKey: Keys.hiddenGroups)
        rebuildChannelOrder()
    }

    func programmes(for item: MediaItem) -> [EPGProgramme] {
        guard let epg else { return [] }
        if let id = item.tvgID?.lowercased(), !id.isEmpty, let list = epg.programmes[id] {
            return list
        }
        if let id = epg.nameToID[item.name.lowercased()], let list = epg.programmes[id] {
            return list
        }
        return []
    }

    func currentProgramme(for item: MediaItem, at date: Date = .now) -> EPGProgramme? {
        programmes(for: item).first { $0.isOn(at: date) }
    }

    func upcoming(for item: MediaItem, after date: Date = .now, limit: Int = 6) -> [EPGProgramme] {
        Array(programmes(for: item).filter { $0.start > date }.prefix(limit))
    }

    /// Alle sportssendinger i TV-guiden (beregnes når guiden eller kanallisten endres).
    private(set) var sportListings: [SportListing] = []

    @ObservationIgnored private var sportsTask: Task<Void, Never>?

    /// Beregner sportsoversikten i bakgrunnen, så appen ikke fryser.
    func refreshSports() {
        sportsTask?.cancel()
        guard epg != nil else {
            sportListings = []
            return
        }
        let channels = orderedLive.compactMap { channel -> (channel: MediaItem, programmes: [EPGProgramme])? in
            let list = programmes(for: channel)
            return list.isEmpty ? nil : (channel, list)
        }
        sportsTask = Task {
            let result = await Task.detached(priority: .utility) {
                SportGuide.build(channels: channels)
            }.value
            if !Task.isCancelled { sportListings = result }
        }
    }

    /// Sportssendinger fra nå og ut kvelden (til kl. 03).
    func todaysSports(now: Date = .now) -> [SportListing] {
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(27 * 3600)
        return sportListings.filter { $0.programme.stop > now && $0.programme.start < end }
    }

    /// Store lister tolkes i bakgrunnen så appen ikke fryser.
    private static func buildCatalog(_ text: String) async -> Catalog {
        await Task.detached(priority: .userInitiated) {
            Catalog.build(from: text)
        }.value
    }

    private static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Avspilling

    func play(_ item: MediaItem) {
        nowPlaying = item
    }

    // MARK: - Favoritter

    func isFavorite(_ id: String) -> Bool {
        favorites.contains(id)
    }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        UserDefaults.standard.set(Array(favorites), forKey: Keys.favorites)
        refreshRecommendations()
    }

    var favoriteChannels: [MediaItem] {
        catalog.live.filter { favorites.contains($0.id) && !isHidden(group: $0.group) }
    }

    var favoriteMovies: [MediaItem] {
        visibleMovies.filter { favorites.contains($0.id) }
    }

    var favoriteShows: [SeriesShow] {
        visibleSeries.filter { favorites.contains($0.id) }
    }

    /// True når kategorien er voksent innhold og det er valgt å skjule det.
    func isHidden(group: String) -> Bool {
        hideAdult && adultGroups.contains(group)
    }

    func setHideAdult(_ value: Bool) {
        guard hideAdult != value else { return }
        hideAdult = value
        UserDefaults.standard.set(value, forKey: Keys.hideAdult)
        rebuildChannelOrder()
    }

    // MARK: - Fremdrift

    func progress(for id: String) -> Double? {
        watch[id]?.fraction
    }

    func resumePosition(for id: String) -> Double? {
        guard let state = watch[id], state.fraction < 0.95, state.position > 10 else { return nil }
        return state.position
    }

    func saveProgress(id: String, position: Double, duration: Double, item: MediaItem? = nil) {
        guard duration.isFinite, duration > 0, position.isFinite, position > 5 else { return }
        watch[id] = WatchState(position: min(position, duration), duration: duration, date: .now,
                               item: item ?? watch[id]?.item)
        if let data = try? JSONEncoder().encode(watch) {
            UserDefaults.standard.set(data, forKey: Keys.watch)
        }
        refreshRecommendations()
    }

    /// Filmer og episoder man har begynt på, nyeste først.
    var continueWatching: [MediaItem] {
        watch
            .filter { $0.value.fraction > 0.01 && $0.value.fraction < 0.95 }
            .sorted { $0.value.date > $1.value.date }
            .compactMap { catalog.byID[$0.key] ?? episodeByID[$0.key] ?? $0.value.item }
            .filter { !isHidden(group: $0.group) }
            .prefix(12)
            .map { $0 }
    }

    /// Episoden man skal fortsette på i en serie.
    func nextEpisode(in show: SeriesShow) -> MediaItem? {
        let show = resolvedShow(show)
        var latest: (index: Int, state: WatchState)?
        for (index, episode) in show.episodes.enumerated() {
            guard let state = watch[episode.id] else { continue }
            if latest == nil || state.date > latest!.state.date {
                latest = (index, state)
            }
        }
        guard let latest else { return show.episodes.first }
        if latest.state.fraction >= 0.95, latest.index + 1 < show.episodes.count {
            return show.episodes[latest.index + 1]
        }
        return show.episodes[latest.index]
    }

    func playLabel(for episode: MediaItem?) -> String {
        guard let episode else { return String(localized: "Play") }
        let started = (progress(for: episode.id) ?? 0) > 0.01
        if let code = episode.episodeCode {
            return started ? String(localized: "Resume \(code)") : String(localized: "Play \(code)")
        }
        return started ? String(localized: "Resume") : String(localized: "Play")
    }
}
