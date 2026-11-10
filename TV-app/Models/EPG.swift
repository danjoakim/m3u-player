import Foundation

/// Ett program i TV-guiden.
nonisolated struct EPGProgramme: Identifiable, Hashable, Codable, Sendable {
    let start: Date
    let stop: Date
    let title: String
    let subtitle: String?
    let desc: String?
    let categories: [String]

    var id: String { "\(start.timeIntervalSince1970)|\(title)" }

    func isOn(at date: Date) -> Bool { start <= date && stop > date }

    func progress(at date: Date) -> Double {
        let total = stop.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / total, 0), 1)
    }

    var durationText: String { Self.format(minutes: Int(stop.timeIntervalSince(start) / 60)) }

    func remainingText(at date: Date) -> String {
        String(localized: "\(Self.format(minutes: max(Int(stop.timeIntervalSince(date) / 60), 1))) left")
    }

    var timeRange: String {
        start.formatted(date: .omitted, time: .shortened) + "–" + stop.formatted(date: .omitted, time: .shortened)
    }

    var looksLikeSport: Bool {
        let text = (categories.joined(separator: " ") + " " + title).lowercased()
        return Catalog.sportKeywords.contains { text.contains($0) }
    }

    static func format(minutes: Int) -> String {
        Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// TV-guiden for kanalene i listen.
nonisolated struct EPGData: Codable, Sendable {
    /// Programmer per kanal-ID (små bokstaver), sortert på starttid.
    var programmes: [String: [EPGProgramme]]
    /// Kanalnavn (små bokstaver) → kanal-ID, for kanaler uten tvg-id.
    var nameToID: [String: String]
    var updated: Date
    var sourceURL: String

    var channelCount: Int { programmes.count }
}

/// Et sportsprogram i dag, med kanalen det går på.
nonisolated struct SportListing: Identifiable, Sendable {
    let item: MediaItem
    let programme: EPGProgramme
    var kind: SportKind = .other
    var id: String { item.id + "|" + programme.id }
}
