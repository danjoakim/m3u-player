import Foundation

/// Sorterer kanalkategorier slik at det som passer brukerens land kommer først.
nonisolated enum ChannelOrder {
    /// Ord som kjennetegner brukerens land og språk, f.eks. «NO», «NORWAY», «NORGE», «NORSK».
    static func regionKeywords(locale: Locale = .current) -> (short: Set<String>, long: Set<String>) {
        var short = Set<String>()
        var long = Set<String>()
        func add(_ name: String?) {
            guard let name else { return }
            let upper = name.uppercased()
            long.insert(upper)
            for word in upper.split(whereSeparator: { !$0.isLetter }) where word.count >= 4 {
                long.insert(String(word))
            }
        }
        let localeIDs = ["en", locale.identifier, locale.language.languageCode?.identifier ?? "en"]
        if let region = locale.region?.identifier.uppercased() {
            short.insert(region)
            if region == "GB" { short.insert("UK") }
            for id in localeIDs { add(Locale(identifier: id).localizedString(forRegionCode: region)) }
        }
        if let language = locale.language.languageCode?.identifier {
            if language.count <= 3 { short.insert(language.uppercased()) }
            for id in localeIDs { add(Locale(identifier: id).localizedString(forLanguageCode: language)) }
        }
        return (short, long)
    }

    static func matchesRegion(_ group: String, short: Set<String>, long: Set<String>) -> Bool {
        let upper = group.uppercased()
        let tokens = upper.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if tokens.contains(where: { short.contains(String($0)) }) { return true }
        return long.contains { upper.contains($0) }
    }

    /// Kategorier for brukerens land først, ellers i leverandørens rekkefølge.
    static func automatic(_ groups: [String], locale: Locale = .current) -> [String] {
        let keywords = regionKeywords(locale: locale)
        let local = groups.filter { matchesRegion($0, short: keywords.short, long: keywords.long) }
        let localSet = Set(local)
        return local + groups.filter { !localSet.contains($0) }
    }
}
