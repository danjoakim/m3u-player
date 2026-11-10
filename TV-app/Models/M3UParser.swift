import Foundation

/// Leser M3U/M3U8-spillelister (#EXTINF med tvg-id, tvg-logo, group-title osv.).
nonisolated enum M3UParser {
    static func parse(_ text: String) -> [MediaItem] {
        var items: [MediaItem] = []
        var seen = Set<String>()
        var info: (attrs: [String: String], name: String)?
        var extGroup: String?

        // Leser linjene direkte som bytes. Det er mange ganger raskere enn
        // å dele opp en stor tekst tegn for tegn.
        let bytes = Array(text.utf8)
        let count = bytes.count
        var start = 0
        while start < count {
            var end = start
            while end < count, bytes[end] != 0x0A, bytes[end] != 0x0D { end += 1 }
            var a = start, b = end
            while a < b, bytes[a] == 0x20 || bytes[a] == 0x09 { a += 1 }
            while b > a, bytes[b - 1] == 0x20 || bytes[b - 1] == 0x09 { b -= 1 }
            start = end + 1
            guard a < b else { continue }

            // Kommentar-/infolinjer starter med «#».
            if bytes[a] == 0x23 {
                if hasPrefix(bytes, a, b, extinfPrefix) {
                    info = parseInfo(bytes: bytes, from: a, to: b)
                    extGroup = nil
                } else if hasPrefix(bytes, a, b, extgrpPrefix) {
                    extGroup = String(decoding: bytes[(a + extgrpPrefix.count)..<b], as: UTF8.self)
                        .trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            guard let current = info else { continue }
            info = nil
            let line = String(decoding: bytes[a..<b], as: UTF8.self)
            guard let url = URL(string: line), url.scheme != nil else { continue }

            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }

            var name = current.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { name = current.attrs["tvg-name"] ?? url.lastPathComponent }

            var group = (current.attrs["group-title"] ?? extGroup ?? "")
                .trimmingCharacters(in: .whitespaces)
            if group.isEmpty { group = String(localized: "Uncategorized") }

            let logo = current.attrs["tvg-logo"].flatMap { $0.isEmpty ? nil : URL(string: $0) }
            // Direktekanaler fra Xtream ligger under /live/ og er aldri episoder.
            let isLivePath = url.path.contains("/live/")
            let episode = isLivePath ? nil : episodeInfo(in: name)
            let kind = isLivePath ? ContentKind.live : classify(name: name, group: group, url: url, isEpisode: episode != nil)
            let isSeries = kind == .series
            let displayName: String
            switch kind {
            case .live: displayName = TitleCleaner.cleanChannel(name)
            case .movie: displayName = TitleCleaner.clean(name)
            case .series: displayName = name
            }

            items.append(MediaItem(
                id: key,
                name: displayName,
                url: url,
                logo: logo,
                group: group,
                tvgID: current.attrs["tvg-id"],
                kind: kind,
                seriesTitle: isSeries ? TitleCleaner.clean(episode?.title ?? name) : nil,
                season: isSeries ? (episode?.season ?? 1) : nil,
                episode: isSeries ? (episode?.episode ?? 0) : nil
            ))
        }
        return items
    }

    private static let extinfPrefix = Array("#EXTINF".utf8)
    private static let extgrpPrefix = Array("#EXTGRP:".utf8)
    private static let wantedKeys: Set<String> = ["tvg-id", "tvg-name", "tvg-logo", "group-title"]

    private static func hasPrefix(_ bytes: [UInt8], _ a: Int, _ b: Int, _ prefix: [UInt8]) -> Bool {
        guard b - a >= prefix.count else { return false }
        for i in 0..<prefix.count where bytes[a + i] != prefix[i] { return false }
        return true
    }

    /// Rask variant som leser `#EXTINF`-linjen rett fra bytes og bare henter feltene appen bruker.
    static func parseInfo(bytes: [UInt8], from a: Int, to b: Int) -> (attrs: [String: String], name: String) {
        let start = min(a + 8, b)   // etter «#EXTINF:»
        var inQuotes = false
        var comma = -1
        var j = start
        while j < b {
            let c = bytes[j]
            if c == 0x22 {
                inQuotes.toggle()
            } else if c == 0x2C, !inQuotes {
                comma = j
                break
            }
            j += 1
        }
        let attrEnd = comma >= 0 ? comma : b
        let name = comma >= 0 ? String(decoding: bytes[(comma + 1)..<b], as: UTF8.self) : ""

        var attrs: [String: String] = [:]
        var i = start
        while i < attrEnd {
            var eq = i
            while eq < attrEnd, bytes[eq] != 0x3D { eq += 1 }          // «=»
            guard eq < attrEnd else { break }
            var keyStart = eq
            while keyStart > i, bytes[keyStart - 1] != 0x20 { keyStart -= 1 }
            let valueStart = eq + 1
            guard valueStart < attrEnd, bytes[valueStart] == 0x22 else {   // «"»
                i = eq + 1
                continue
            }
            var valueEnd = valueStart + 1
            while valueEnd < attrEnd, bytes[valueEnd] != 0x22 { valueEnd += 1 }
            guard valueEnd < attrEnd else { break }
            let key = String(decoding: bytes[keyStart..<eq], as: UTF8.self).lowercased()
            if wantedKeys.contains(key) {
                attrs[key] = String(decoding: bytes[(valueStart + 1)..<valueEnd], as: UTF8.self)
            }
            i = valueEnd + 1
        }
        return (attrs, name)
    }

    /// Lenke til TV-guide i hodet: `#EXTM3U url-tvg="…"` eller `x-tvg-url="…"`.
    static func headerEPGURL(_ text: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline).prefix(5) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#EXTM3U") else { continue }
            let attrs = parseInfo(line).attrs
            guard let value = attrs["url-tvg"] ?? attrs["x-tvg-url"] else { return nil }
            let first = value.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
            return (first?.isEmpty ?? true) ? nil : first
        }
        return nil
    }

    /// Deler `#EXTINF:-1 tvg-id="x" group-title="y",Navn` i attributter og navn.
    static func parseInfo(_ line: String) -> (attrs: [String: String], name: String) {
        let body = line.dropFirst(8)
        var inQuotes = false
        var splitIndex: Substring.Index?
        for i in body.indices {
            let c = body[i]
            if c == "\"" {
                inQuotes.toggle()
            } else if c == ",", !inQuotes {
                splitIndex = i
                break
            }
        }

        let attrPart = splitIndex.map { body[..<$0] } ?? body
        let name = splitIndex.map { String(body[body.index(after: $0)...]) } ?? ""

        var attrs: [String: String] = [:]
        var i = attrPart.startIndex
        while let eq = attrPart[i...].firstIndex(of: "=") {
            var keyStart = eq
            while keyStart > attrPart.startIndex {
                let prev = attrPart.index(before: keyStart)
                if attrPart[prev] == " " { break }
                keyStart = prev
            }
            let key = attrPart[keyStart..<eq].lowercased()
            let afterEq = attrPart.index(after: eq)
            guard afterEq < attrPart.endIndex, attrPart[afterEq] == "\"" else {
                i = afterEq
                continue
            }
            let valueStart = attrPart.index(after: afterEq)
            guard let valueEnd = attrPart[valueStart...].firstIndex(of: "\"") else { break }
            attrs[key] = String(attrPart[valueStart..<valueEnd])
            i = attrPart.index(after: valueEnd)
            if i >= attrPart.endIndex { break }
        }
        return (attrs, name)
    }

    /// Finner «S01E03» / «S1 E3» i et navn.
    static func episodeInfo(in name: String) -> (title: String, season: Int, episode: Int)? {
        let chars = Array(name)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if (c == "S" || c == "s"), i == 0 || !chars[i - 1].isLetter {
                var j = i + 1
                var seasonDigits = ""
                while j < chars.count, chars[j].isASCII, chars[j].isNumber, seasonDigits.count < 3 {
                    seasonDigits.append(chars[j])
                    j += 1
                }
                if !seasonDigits.isEmpty {
                    while j < chars.count, chars[j] == " " { j += 1 }
                    if j < chars.count, chars[j] == "E" || chars[j] == "e" {
                        j += 1
                        var episodeDigits = ""
                        while j < chars.count, chars[j].isASCII, chars[j].isNumber, episodeDigits.count < 4 {
                            episodeDigits.append(chars[j])
                            j += 1
                        }
                        if !episodeDigits.isEmpty, let s = Int(seasonDigits), let e = Int(episodeDigits) {
                            let trimSet = CharacterSet.whitespacesAndNewlines
                                .union(CharacterSet(charactersIn: "-–_.|:"))
                            var title = String(chars[0..<i]).trimmingCharacters(in: trimSet)
                            if title.isEmpty { title = name }
                            return (title, s, e)
                        }
                    }
                }
            }
            i += 1
        }
        return nil
    }

    static func classify(name: String, group: String, url: URL, isEpisode: Bool) -> ContentKind {
        let path = url.path.lowercased()
        if path.contains("/movie/") { return .movie }
        if path.contains("/series/") { return .series }
        if isEpisode { return .series }

        let g = group.lowercased()
        if ["vod", "movie", "filmer", "kino", "cinema"].contains(where: { g.contains($0) }) { return .movie }
        if ["serie", "series", "tv show", "tvshow"].contains(where: { g.contains($0) }) { return .series }

        let ext = url.pathExtension.lowercased()
        if ["mp4", "mkv", "avi", "mov", "m4v"].contains(ext) { return .movie }
        return .live
    }
}
