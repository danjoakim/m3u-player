import Foundation

/// Velger spiller før avspillingen starter, slik de beste IPTV-appene gjør,
/// i stedet for å prøve Apples spiller og vente på at den feiler.
nonisolated enum EngineSelector {
    /// Formater bare VLC kan spille.
    static let vlcOnlyExtensions: Set<String> = ["mkv", "avi", "wmv", "flv", "webm", "divx", "ogm", "mpg", "mpeg"]

    /// Kodeker Apples spiller håndterer i HLS.
    private static let appleCodecs = ["avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "mp4a", "ac-3", "ec-3", "ec+3",
                                      "alac", "flac", "opus", "stpp", "wvtt", "mp3"]

    static func choose(for url: URL, rememberedVLC: Bool, vlcAvailable: Bool) async -> (EngineKind, URL) {
        let ext = url.pathExtension.lowercased()
        if vlcAvailable, rememberedVLC || vlcOnlyExtensions.contains(ext) {
            return (.vlc, url)
        }

        switch ext {
        case "m3u8":
            // Les spillelistefilen og se om den oppgir kodeker Apple ikke støtter.
            if vlcAvailable, let manifest = await fetchPrefix(url, limit: 65_536), hasUnsupportedCodecs(manifest) {
                return (.vlc, url)
            }
            return (.apple, url)
        case "", "ts":
            // Rå MPEG-TS: finn HLS-versjonen av samme strøm hvis serveren har den.
            for alternative in StreamFallback.alternatives(for: url) {
                if let head = await fetchPrefix(alternative, limit: 512), head.hasPrefix("#EXTM3U") {
                    return (.apple, alternative)
                }
            }
            if let head = await fetchPrefix(url, limit: 512), head.hasPrefix("#EXTM3U") {
                return (.apple, url)
            }
            return (vlcAvailable ? .vlc : .apple, url)
        default:
            return (.apple, url)
        }
    }

    static func hasUnsupportedCodecs(_ manifest: String) -> Bool {
        for line in manifest.split(whereSeparator: \.isNewline) {
            guard let start = line.range(of: "CODECS=\"") else { continue }
            let rest = line[start.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { continue }
            for codec in rest[..<end].split(separator: ",") {
                let value = codec.trimmingCharacters(in: .whitespaces).lowercased()
                if !appleCodecs.contains(where: { value.hasPrefix($0) }) { return true }
            }
        }
        return false
    }

    /// Henter bare de første bytene av en adresse, og avbryter så (viktig for direktestrømmer som aldri slutter).
    static func fetchPrefix(_ url: URL, limit: Int) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request) else { return nil }
        defer { bytes.task.cancel() }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= limit { break }
            }
        } catch {
            if data.isEmpty { return nil }
        }
        return String(decoding: data, as: UTF8.self)
    }
}
