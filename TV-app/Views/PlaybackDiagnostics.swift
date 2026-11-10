import Foundation
import AVFoundation

/// Technical details shown when playback fails.
enum PlaybackDiagnostics {
    static func describe(_ error: Error?, url: URL) -> String {
        var lines: [String] = []
        let ext = url.pathExtension.lowercased()
        lines.append("Format: " + (ext.isEmpty ? "?" : ext) + " · " + (url.scheme ?? "?"))

        guard let error = error as NSError? else { return lines.joined(separator: "\n") }
        lines.append("\(error.domain) \(error.code)")
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("\(underlying.domain) \(underlying.code)")
        }
        if let hint = hint(for: error, ext: ext) {
            lines.append(hint)
        }
        return lines.joined(separator: "\n")
    }

    private static func hint(for error: NSError, ext: String) -> String? {
        if ["mkv", "avi", "wmv", "flv", "ts"].contains(ext) {
            return "Apple's player doesn't support .\(ext)"
        }
        let codes = [error.code] + [(error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code].compactMap { $0 }
        if codes.contains(-11850) || codes.contains(-12939) { return "Raw MPEG-TS stream, not HLS" }
        if codes.contains(-1022) { return "Blocked by App Transport Security (http)" }
        if codes.contains(-1100) || codes.contains(404) { return "Not found on the server (404)" }
        if codes.contains(-12660) || codes.contains(403) { return "Server refused access (403)" }
        if codes.contains(-11828) || codes.contains(-12847) { return "Unsupported format" }
        return nil
    }
}

/// Many IPTV servers send raw MPEG-TS by default but can also serve HLS,
/// which is what Apple's player needs. These are the HLS addresses to try.
nonisolated enum StreamFallback {
    static func alternatives(for url: URL) -> [URL] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        var parts = components.path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return [] }
        let ext = (last as NSString).pathExtension.lowercased()
        guard ext.isEmpty || ext == "ts" else { return [] }
        let base = ext.isEmpty ? last : (last as NSString).deletingPathExtension

        var result: [URL] = []
        // Xtream: /user/pass/id  →  /live/user/pass/id.m3u8
        if parts.count == 3 {
            var xtream = components
            xtream.path = "/live/\(parts[0])/\(parts[1])/\(base).m3u8"
            if let url = xtream.url { result.append(url) }
        }
        // Same address with .m3u8
        parts[parts.count - 1] = base + ".m3u8"
        var same = components
        same.path = "/" + parts.joined(separator: "/")
        if let url = same.url, !result.contains(url) { result.append(url) }
        return result
    }
}

enum PlaybackStatus {
    /// Waits until the item is ready (true) or has failed (false).
    static func waitUntilReady(_ item: AVPlayerItem) async -> Bool {
        while !Task.isCancelled {
            switch item.status {
            case .readyToPlay: return true
            case .failed: return false
            default: try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return false
    }

    /// True when the player shows a picture. Sound without a picture (the QuickTime logo)
    /// means Apple's player can't decode the video, e.g. MPEG-2 on older SD channels.
    static func hasVideo(_ item: AVPlayerItem, timeout: Duration = .seconds(4)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if item.presentationSize != .zero { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return item.presentationSize != .zero
    }
}
