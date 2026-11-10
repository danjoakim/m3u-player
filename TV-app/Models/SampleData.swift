import Foundation

/// Sample content shown before the user adds a playlist.
/// Every entry plays Apple's and Mux's public test streams.
enum SampleData {
    static var m3u: String {
        let streamA = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
        let streamB = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
        var lines = ["#EXTM3U"]

        func add(_ name: String, _ group: String, _ stream: String, id: String? = nil) {
            let idPart = id.map { " tvg-id=\"\($0)\"" } ?? ""
            lines.append("#EXTINF:-1\(idPart) group-title=\"\(group)\",\(name)")
            lines.append("\(stream)?demo=\(lines.count)")
        }

        add("North Channel", "Entertainment", streamB, id: "nordkanalen")
        add("Sport One", "Sports", streamA, id: "sport1")
        add("Sport Two", "Sports", streamB, id: "sport2")
        add("Sport Three", "Sports", streamA, id: "sport3")
        add("News 24", "News", streamB, id: "nyheter24")
        add("Film Plus", "Entertainment", streamA, id: "filmpluss")
        add("Documentary", "Entertainment", streamB, id: "dokumentar")
        add("Kids+", "Kids", streamA, id: "barn")

        add("Last Train from Bergen", "Movies – Nordic", streamA)
        add("Northern Lights over Lofoten", "Movies – Nordic", streamB)
        add("Winter Harbour", "Movies – Nordic", streamA)
        add("The Coastline", "Movies – Thriller", streamB)
        add("Midnight Route", "Movies – Thriller", streamA)
        add("The Lighthouse Keeper", "Movies – Thriller", streamB)

        for e in 1...3 { add("Fjordland S01E0\(e)", "Series – Nordic", e % 2 == 0 ? streamA : streamB) }
        for e in 1...5 { add("Fjordland S02E0\(e)", "Series – Nordic", e % 2 == 0 ? streamB : streamA) }
        for e in 1...4 { add("Coast Guard S01E0\(e)", "Series – Nordic", e % 2 == 0 ? streamA : streamB) }
        for e in 1...3 { add("High Mountain S01E0\(e)", "Series – Drama", e % 2 == 0 ? streamB : streamA) }

        return lines.joined(separator: "\n")
    }

    private typealias Slot = (title: String, minutes: Int, category: String, desc: String)

    private static let schedules: [String: [Slot]] = [
        "nordkanalen": [
            ("Evening News", 30, "News", "The day's top stories from home and abroad."),
            ("Weather", 10, "News", "The forecast for the coming days."),
            ("Ocean Giants", 60, "Documentary", "Follow the whales along the Norwegian coast through a whole year."),
            ("Quiz Night", 50, "Entertainment", "Four teams compete to be crowned the sharpest minds of the evening.")
        ],
        "sport1": [
            ("Ice Hockey: Nordvik – Elvdal", 150, "Sports", "The league final, live. Elvdal won the last two meetings, but Nordvik are unbeaten at home."),
            ("Studio: After the Game", 30, "Sports", "Analysis and interviews after tonight's game."),
            ("Sports News", 30, "Sports", "Results and highlights from today's sport."),
            ("Ice Hockey: Tonight's Highlights", 45, "Sports", "Every goal from tonight's games.")
        ],
        "sport2": [
            ("Tennis: Women's Final", 120, "Sports", "The final, live from centre court."),
            ("Tennis: Highlights", 40, "Sports", "The best of today's matches."),
            ("Golf: Final Round", 90, "Sports", "The tournament is decided.")
        ],
        "sport3": [
            ("Football: Fjellby – Havnestad", 110, "Sports", "Top-of-the-table clash, live."),
            ("Handball: Norway – Denmark", 90, "Sports", "Men's international."),
            ("Cross-Country Skiing: Sprint", 60, "Sports", "The sprint finals from the World Cup.")
        ],
        "nyheter24": [
            ("News", 15, "News", "The latest news."),
            ("The Debate", 45, "News", "Current issues debated in the studio."),
            ("News", 15, "News", "The latest news."),
            ("Business News", 15, "News", "Markets and business.")
        ],
        "filmpluss": [
            ("Last Train from Bergen", 110, "Movie", "A night train journey takes an unexpected turn."),
            ("Winter Harbour", 95, "Movie", "A small fishing village pulls together as the storm arrives.")
        ],
        "dokumentar": [
            ("Mountain People", 50, "Documentary", "Life on the country's highest farms."),
            ("The Build", 45, "Documentary", "Behind the scenes at one of the largest construction sites in the Nordics.")
        ],
        "barn": [
            ("Bedtime Stories", 30, "Kids", "Calm stories before bedtime."),
            ("Cartoons", 30, "Kids", "Fun cartoons for the little ones.")
        ]
    ]

    /// Made-up TV guide for the sample channels, relative to now.
    static func epg(now: Date = .now) -> EPGData {
        let halfHour = (now.timeIntervalSince1970 / 1800).rounded(.down) * 1800
        let base = Date(timeIntervalSince1970: halfHour).addingTimeInterval(-3600)
        let end = base.addingTimeInterval(30 * 3600)
        var programmes: [String: [EPGProgramme]] = [:]

        for (index, key) in schedules.keys.sorted().enumerated() {
            guard let slots = schedules[key], !slots.isEmpty else { continue }
            var time = base.addingTimeInterval(-Double((index * 17) % 60) * 60)
            var list: [EPGProgramme] = []
            var i = 0
            while time < end {
                let slot = slots[i % slots.count]
                let stop = time.addingTimeInterval(Double(slot.minutes) * 60)
                list.append(EPGProgramme(start: time, stop: stop, title: slot.title, subtitle: nil,
                                         desc: slot.desc, categories: [slot.category]))
                time = stop
                i += 1
            }
            programmes[key] = list
        }
        return EPGData(programmes: programmes, nameToID: [:], updated: now, sourceURL: "")
    }
}
