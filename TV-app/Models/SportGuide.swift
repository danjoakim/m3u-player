import Foundation

/// Sportsgren, gjenkjent fra programtittel og kategori i TV-guiden.
nonisolated enum SportKind: String, CaseIterable, Sendable {
    case football, hockey, handball, tennis, motorsport, winter, golf, basketball, combat, cycling, other

    var icon: String {
        switch self {
        case .football: "soccerball"
        case .hockey: "hockey.puck"
        case .handball: "figure.handball"
        case .tennis: "tennis.racket"
        case .motorsport: "flag.checkered"
        case .winter: "figure.skiing.crosscountry"
        case .golf: "figure.golf"
        case .basketball: "basketball"
        case .combat: "figure.boxing"
        case .cycling: "bicycle"
        case .other: "sportscourt"
        }
    }

    /// Ord og navn per sportsgren på alle appens språk (og tyrkisk), pluss ligaer og turneringer,
    /// som er like på alle språk. «=ord» må stå alene; kinesiske ord søkes som tekst.
    private static let keywords: [(SportKind, [String])] = [
        (.football, [
            // Ligaer og turneringer
            "uefa", "fifa", "champions league", "europa league", "conference league", "premier league", "eliteserien",
            "obos-ligaen", "allsvenskan", "superliga", "veikkausliiga", "bundesliga", "ligue 1", "laliga", "la liga",
            "serie a", "eredivisie", "ekstraklasa", "süper lig", "primeira liga", "brasileirão", "mls", "fa cup",
            "copa del rey", "coppa italia", "dfb-pokal", "vm-kval", "em-kval", "world cup qualif", "euro 20",
            // no, sv, da, en, de, fi, fr, es, it, pt, nl, pl, tr, zh
            "fotball", "fotboll", "fodbold", "football", "soccer", "fußball", "fussball", "jalkapallo", "fútbol",
            "calcio", "futebol", "voetbal", "piłka nożna", "pilka nozna", "futbol", "足球", "英超", "西甲", "意甲", "德甲"
        ]),
        (.hockey, [
            "nhl", "shl", "khl", "liiga", "fjordkraft-ligaen", "metal ligaen",
            "ishockey", "hockey", "jääkiekko", "ijshockey", "hokej", "buz hokeyi", "冰球"
        ]),
        (.handball, [
            "ehf", "håndball", "handboll", "håndbold", "handball", "käsipallo", "balonmano", "pallamano",
            "handebol", "andebol", "handbal", "piłka ręczna", "pilka reczna", "hentbol", "手球"
        ]),
        (.tennis, [
            "atp", "wta", "wimbledon", "roland-garros", "roland garros", "us open", "australian open", "davis cup",
            "tennis", "tenis", "tênis", "tenisz", "网球"
        ]),
        (.motorsport, [
            "f1", "formel 1", "formula 1", "formel1", "formule 1", "fórmula 1", "formuła 1", "formula uno",
            "motogp", "moto gp", "nascar", "indycar", "rally", "wrc", "rallycross",
            "speedway", "superbike", "motorsport", "automovilismo", "automobilismo", "sport auto", "赛车", "一级方程式"
        ]),
        (.winter, [
            "fis", "langrenn", "skiskyting", "alpint", "=hopp", "hoppuka", "hopprenn", "skihopp", "skiflyging",
            "skiskydning", "skidskytte", "längdskidor", "backhoppning", "biathlon", "cross-country", "ski jumping",
            "alpine skiing", "skispringen", "langlauf", "ski alpin", "hiihto", "ampumahiihto", "mäkihyppy",
            "ski de fond", "saut à ski", "=esqui", "sci alpino", "sci di fondo", "salto con gli sci",
            "schaatsen", "langlaufen", "skoki narciarskie", "biegi narciarskie", "skøyter", "skridsko", "speed skating",
            "freestyle", "snowboard", "滑雪", "冬奥"
        ]),
        (.golf, ["=golf", "pga", "lpga", "dp world", "ryder cup", "the masters", "golfturnering", "高尔夫"]),
        (.basketball, [
            "nba", "wnba", "euroleague", "eurobasket", "basket", "koripallo", "baloncesto", "pallacanestro",
            "basquete", "basquetebol", "koszykówka", "koszykowka", "basketbal", "basketbol", "篮球"
        ]),
        (.combat, [
            "ufc", "mma", "boksing", "boxing", "boxen", "=boxe", "boxeo", "pugilato", "nyrkkeily",
            "bryting", "brottning", "wrestling", "lucha libre", "kampsport", "kickboxing", "拳击"
        ]),
        (.cycling, [
            "tour de france", "giro d italia", "la vuelta", "uci", "sykling", "cykling", "cycling", "radsport", "pyöräily",
            "cyclisme", "ciclismo", "wielrennen", "kolarstwo", "bisiklet", "自行车"
        ])
    ]

    /// Generelle ord for sport på alle språkene: «Sportsnytt», «Deportes», «Urheilu», «体育».
    private static let genericSport = ["sport", "idrett", "idrott", "deporte", "esporte", "desporto", "urheilu",
                                       "sportowy", "体育"]

    /// Reklame, shopping og pauser hører aldri hjemme blant sportssendingene.
    private static let fillers = ["shopping", "teleshop", "tv shop", "tvshop", "teletienda", "televendita", "telezakupy",
                                  "infomercial", "reklame", "reklam", "werbung", "publicité", "publicidad", "pubblicità",
                                  "mainos", "pause", "ingen sending", "no broadcast", "off air", "sendeslutt",
                                  "slutt for i dag", "testbilde", "sendepause", "fin des programmes", "fine trasmissioni"]

    /// Ordlistene ferdig behandlet én gang, så hver sending kan sjekkes raskt.
    /// Hele ord: «=ord» og korte forkortelser («NHL», «F1»). Lengre ord kan stå først i et sammensatt ord
    /// («hoppuka», «fotballkamp»). Uttrykk med flere ord må starte på et ordskille. Kinesisk søkes som tekst.
    nonisolated private struct Matcher: Sendable {
        var whole = Set<String>()
        var prefixes: [String] = []
        var phrases: [String] = []
        var cjk: [String] = []

        init(_ keywords: [String]) {
            for raw in keywords {
                var key = raw.trimmingCharacters(in: .whitespaces)
                if key.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) {
                    cjk.append(key)
                } else if key.hasPrefix("=") {
                    key.removeFirst()
                    whole.insert(SportKind.fold(key))
                } else if key.contains(" ") || key.contains("-") {
                    phrases.append(" " + SportKind.words(key).joined(separator: " "))
                } else {
                    key = SportKind.fold(key)
                    if key.count <= 3 { whole.insert(key) } else { prefixes.append(key) }
                }
            }
        }

        func matches(_ words: [String], joined: String) -> Bool {
            for word in words {
                if whole.contains(word) { return true }
                for prefix in prefixes where word.hasPrefix(prefix) { return true }
            }
            if phrases.contains(where: { joined.contains($0) }) { return true }
            return cjk.contains(where: { joined.contains($0) })
        }
    }

    private static let matchers: [(SportKind, Matcher)] = keywords.map { ($0.0, Matcher($0.1)) }
    private static let genericMatcher = Matcher(genericSport)
    private static let fillerMatcher = Matcher(fillers)

    /// Ordene i en tekst, med små bokstaver og uten aksenter: «Fútbol: Home-Shopping!» → ["futbol", "home", "shopping"].
    static func words(_ text: String) -> [String] {
        fold(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Små bokstaver uten aksenter, så «Fútbol» og «Futbol» blir like.
    fileprivate static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Er teksten reklame/shopping, og hvilken sportsgren er den? Ordene deles opp bare én gang.
    static func classify(_ text: String) -> (filler: Bool, kind: SportKind?) {
        let list = words(text)
        let joined = " " + list.joined(separator: " ") + " "
        if fillerMatcher.matches(list, joined: joined) || list.contains(where: { $0.contains("shopping") }) {
            return (true, nil)
        }
        for (kind, matcher) in matchers where matcher.matches(list, joined: joined) {
            return (false, kind)
        }
        if genericMatcher.matches(list, joined: joined) {
            return (false, .other)
        }
        return (false, nil)
    }

    /// Gjenkjent sportsgren, eller nil hvis teksten ikke ser ut som sport.
    static func detect(_ text: String) -> SportKind? {
        classify(text).kind
    }
}

nonisolated enum SportGuide {
    /// Alle sportssendinger i TV-guiden, sortert på tid.
    /// Samme sending på flere kanaler (SD, HD, FHD) vises bare én gang, på den første kanalen.
    /// Tungt for store guider, så den kjøres i bakgrunnen.
    static func build(channels: [(channel: MediaItem, programmes: [EPGProgramme])], now: Date = .now) -> [SportListing] {
        let windowStart = now.addingTimeInterval(-4 * 3600)
        var result: [SportListing] = []
        var seen = Set<String>()
        // Samme tittel går igjen mange ganger («Sportsnytt», «Pause»), så hver tekst sjekkes bare én gang.
        var cache: [String: (filler: Bool, kind: SportKind?)] = [:]
        for (channel, list) in channels {
            guard !list.isEmpty else { continue }
            let sportChannel = Catalog.isSport(channel)
            for programme in list where programme.stop > windowStart {
                let text = programme.categories.isEmpty
                    ? programme.title
                    : programme.title + " " + programme.categories.joined(separator: " ")
                let info: (filler: Bool, kind: SportKind?)
                if let cached = cache[text] {
                    info = cached
                } else {
                    info = SportKind.classify(text)
                    cache[text] = info
                }
                // På sportskanaler regnes alt som sport; ellers bare det som tydelig er sport.
                guard !info.filler, sportChannel || info.kind != nil else { continue }
                let key = programme.title.lowercased() + "|" + String(Int(programme.start.timeIntervalSince1970 / 60))
                guard seen.insert(key).inserted else { continue }
                result.append(SportListing(item: channel, programme: programme, kind: info.kind ?? .other))
            }
        }
        result.sort { $0.programme.start < $1.programme.start }
        return result
    }
}
