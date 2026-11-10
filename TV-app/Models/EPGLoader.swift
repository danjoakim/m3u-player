import Foundation

enum EPGError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "The file doesn't look like a TV guide in XMLTV format.")
        }
    }
}

/// Leser XMLTV (vanlig eller .gz) og beholder bare kanaler som finnes i spillelisten.
nonisolated enum EPGLoader {
    static func load(data: Data, sourceURL: String, wantedIDs: Set<String>, wantedNames: Set<String>,
                     now: Date = .now) throws -> EPGData {
        let xml = try gunzipIfNeeded(data)
        let delegate = XMLTVParser(wantedIDs: wantedIDs, wantedNames: wantedNames,
                                   windowStart: now.addingTimeInterval(-4 * 3600),
                                   windowEnd: now.addingTimeInterval(36 * 3600))
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        if !parser.parse(), delegate.programmes.isEmpty {
            throw EPGError.unreadable
        }
        var programmes = delegate.programmes
        for key in programmes.keys {
            programmes[key]?.sort { $0.start < $1.start }
        }
        return EPGData(programmes: programmes, nameToID: delegate.nameToID, updated: now, sourceURL: sourceURL)
    }

    /// Pakker ut .gz. Apples «zlib»-dekoder leser rå DEFLATE, så gzip-hodet fjernes først.
    static func gunzipIfNeeded(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B else { return data }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0, offset + 2 <= bytes.count {
            offset += 2 + (Int(bytes[offset]) | Int(bytes[offset + 1]) << 8)
        }
        if flags & 0x08 != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { throw EPGError.unreadable }
        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        return try (deflated as NSData).decompressed(using: .zlib) as Data
    }

    /// XMLTV-tid: «20261109190000 +0100».
    static func parseDate(_ value: String) -> Date? {
        let parts = value.split(separator: " ")
        guard let main = parts.first else { return nil }
        let digits = Array(main.utf8)
        func number(_ from: Int, _ length: Int) -> Int? {
            guard from + length <= digits.count else { return nil }
            var result = 0
            for i in from..<(from + length) {
                let c = Int(digits[i])
                guard c >= 48, c <= 57 else { return nil }
                result = result * 10 + (c - 48)
            }
            return result
        }
        guard let year = number(0, 4), let month = number(4, 2), let day = number(6, 2),
              let hour = number(8, 2), let minute = number(10, 2) else { return nil }
        let second = number(12, 2) ?? 0

        var offset = 0
        if parts.count > 1 {
            let tz = Array(parts[1].utf8)
            if tz.count == 5 {
                let sign = tz[0] == UInt8(ascii: "-") ? -1 : 1
                let h = (Int(tz[1]) - 48) * 10 + (Int(tz[2]) - 48)
                let m = (Int(tz[3]) - 48) * 10 + (Int(tz[4]) - 48)
                offset = sign * (h * 3600 + m * 60)
            }
        }
        let days = daysFromCivil(year, month, day)
        let seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let year = m <= 2 ? y - 1 : y
        let era = (year >= 0 ? year : year - 399) / 400
        let yoe = year - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}

nonisolated final class XMLTVParser: NSObject, XMLParserDelegate {
    private let wantedIDs: Set<String>
    private let wantedNames: Set<String>
    private let windowStart: Date
    private let windowEnd: Date

    private(set) var programmes: [String: [EPGProgramme]] = [:]
    private(set) var nameToID: [String: String] = [:]
    private var keptChannels = Set<String>()

    private var channelID: String?
    private var channelNames: [String] = []

    private var programmeChannel: String?
    private var programmeStart = Date.distantPast
    private var programmeStop = Date.distantPast
    private var title = ""
    private var subtitle = ""
    private var desc = ""
    private var categories: [String] = []

    private var text = ""
    private var capturing = false

    init(wantedIDs: Set<String>, wantedNames: Set<String>, windowStart: Date, windowEnd: Date) {
        self.wantedIDs = wantedIDs
        self.wantedNames = wantedNames
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "channel":
            channelID = attributeDict["id"]?.lowercased()
            channelNames = []
        case "display-name", "title", "sub-title", "desc", "category":
            text = ""
            capturing = true
        case "programme":
            programmeChannel = nil
            guard let channel = attributeDict["channel"]?.lowercased(),
                  keptChannels.contains(channel) || wantedIDs.contains(channel),
                  let start = EPGLoader.parseDate(attributeDict["start"] ?? "") else { return }
            let stop = EPGLoader.parseDate(attributeDict["stop"] ?? "") ?? start.addingTimeInterval(1800)
            guard stop > windowStart, start < windowEnd else { return }
            programmeChannel = channel
            programmeStart = start
            programmeStop = stop
            title = ""
            subtitle = ""
            desc = ""
            categories = []
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "display-name":
            if channelID != nil, !value.isEmpty { channelNames.append(value.lowercased()) }
        case "channel":
            if let id = channelID {
                let nameMatches = channelNames.filter { wantedNames.contains($0) }
                if wantedIDs.contains(id) || !nameMatches.isEmpty {
                    keptChannels.insert(id)
                    for name in nameMatches where nameToID[name] == nil {
                        nameToID[name] = id
                    }
                }
            }
            channelID = nil
        case "title":
            if programmeChannel != nil, title.isEmpty { title = value }
        case "sub-title":
            if programmeChannel != nil, subtitle.isEmpty { subtitle = value }
        case "desc":
            if programmeChannel != nil, desc.isEmpty { desc = value }
        case "category":
            if programmeChannel != nil, !value.isEmpty, !categories.contains(value) { categories.append(value) }
        case "programme":
            if let channel = programmeChannel {
                programmes[channel, default: []].append(EPGProgramme(
                    start: programmeStart,
                    stop: programmeStop,
                    title: title.isEmpty ? String(localized: "Untitled") : title,
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    desc: desc.isEmpty ? nil : desc,
                    categories: categories
                ))
            }
            programmeChannel = nil
        default:
            break
        }
        if ["display-name", "title", "sub-title", "desc", "category"].contains(elementName) {
            capturing = false
            text = ""
        }
    }
}
