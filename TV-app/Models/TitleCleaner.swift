import Foundation

/// Gjør titler fra IPTV-lister lesevennlige:
/// «NO | Breaking Bad (2008) [4K]» → «Breaking Bad», «|EN| The Office US HD» → «The Office US».
nonisolated enum TitleCleaner {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Mønstrene er faste og testet, så dette feiler aldri.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    // Prefiks med landskode eller tagg.
    /// «[NO] », «|EN| », «(SE) », «[EN/NO] »
    private static let wrappedPrefix =
        regex(#"^\s*[\[\(|]\s*[A-Z0-9+]{2,4}(?:\s*[/-]\s*[A-Z]{2,4})?\s*[\]\)|]\s*"#)
    /// «NO | », «ENG | », «EN/NO | », «4K | », «VIP | »
    private static let pipePrefix =
        regex(#"^\s*(?:[A-Z]{2,3}|4K|UHD|FHD|VIP)(?:\s*/\s*[A-Z]{2,3})?\s*\|\s*"#)
    /// «NO: », «UK: » (bare to bokstaver, så «CSI: Miami» får være i fred)
    private static let colonPrefix = regex(#"^\s*[A-Z]{2}\s*:\s+"#)
    /// «NO - », «DE – »
    private static let dashPrefix = regex(#"^\s*[A-Z]{2}\s+[-–]\s+"#)

    // Tagger inne i eller på slutten av tittelen.
    /// Alt i hakeparentes: «[4K]», «[MULTI-SUB]»
    private static let squareTags = regex(#"\s*\[[^\]]*\]\s*"#)
    /// År eller tekniske tagger i vanlig parentes: «(2008)», «(Multi-Sub)», «(NORDIC 4K)»
    private static let parenTags = regex(
        #"\s*\((?:(?:19|20)\d{2}|[^)]*\b(?:sub|subs|multi|dub|dubbed|4k|uhd|fhd|hd|vost|vostfr|nordic|norsk|svensk|dansk|eng|english)\b[^)]*)\)\s*"#,
        .caseInsensitive)
    /// Kvalitet og språk til slutt: « HD», « 4K», « - MULTI-SUB»
    private static let trailingTags = regex(
        #"(?:\s*[-–|]?\s*\b(?:4K|UHD|FHD|HD|SD|HEVC|H\.?26[45]|HDR10\+?|HDR|MULTI(?:-?SUBS?)?|SUBS?|DUAL|VOSTFR|NORDIC)\b)+\s*$"#)
    /// « - 2008» til slutt (men ikke «Blade Runner 2049»)
    private static let trailingYear = regex(#"\s+[-–]\s+(?:19|20)\d{2}\s*$"#)
    private static let spaces = regex(#"\s{2,}"#)

    private static let tags: Set<String> = ["4K", "UHD", "FHD", "HD", "SD", "HEVC", "H264", "H265", "HDR", "HDR10",
                                            "MULTI", "MULTI-SUB", "SUB", "SUBS", "DUAL", "VOSTFR", "NORDIC"]
    private static let edgeCharacters = CharacterSet(charactersIn: " -–|:·").union(.whitespaces)

    /// For filmer og serier.
    static func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Rask vei: de fleste titler trenger ingen rydding.
        let lastToken = trimmed.split(separator: " ").last.map(String.init) ?? ""
        if !trimmed.contains(where: { "[(|:-–".contains($0) }) && !tags.contains(lastToken) {
            return trimmed
        }
        var value = stripPrefixes(trimmed)
        value = replace(squareTags, in: value, with: " ")
        value = replace(parenTags, in: value, with: " ")
        value = replace(trailingTags, in: value, with: "")
        value = replace(trailingYear, in: value, with: "")
        value = replace(spaces, in: value, with: " ")
        value = value.trimmingCharacters(in: edgeCharacters)
        return value.isEmpty ? trimmed : value
    }

    /// For kanaler: fjerner bare landskode foran, så «NO | TV 2 HD» blir «TV 2 HD».
    static func cleanChannel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(where: { "[(|:-–".contains($0) }) else { return trimmed }
        let value = stripPrefixes(trimmed).trimmingCharacters(in: edgeCharacters)
        return value.isEmpty ? trimmed : value
    }

    private static func stripPrefixes(_ input: String) -> String {
        var value = input
        for _ in 0..<3 {
            let before = value
            for pattern in [wrappedPrefix, pipePrefix, colonPrefix, dashPrefix] {
                value = replace(pattern, in: value, with: "")
            }
            if value == before { break }
        }
        return value
    }

    private static func replace(_ regex: NSRegularExpression, in value: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: template)
    }
}
