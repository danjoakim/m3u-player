import UIKit
import Foundation

/// VLC as the second playback engine for formats Apple's player can't handle (MKV, AVI, MPEG-2, raw MPEG-TS …).
/// Requires the Swift package https://github.com/koombea/vlckit-spm (product VLCKitSPM).
/// Without the package the app still builds; it then only uses Apple's player.
enum VLCSupport {
    #if canImport(VLCKitSPM)
    static let isAvailable = true
    #else
    static let isAvailable = false
    #endif

    static func makeEngine(surface: UIView) -> PlaybackEngine? {
        #if canImport(VLCKitSPM)
        return VLCEngine(surface: surface)
        #else
        return nil
        #endif
    }
}

#if canImport(VLCKitSPM)
import VLCKitSPM

final class VLCEngine: PlaybackEngine {
    let player = VLCMediaPlayer()
    private var startAt: Double?
    private var didSeek = false

    private(set) var isPlaying = false
    private(set) var isBuffering = true
    private(set) var currentSeconds = 0.0
    private(set) var durationSeconds = 0.0
    private(set) var failed = false
    private(set) var didFinish = false
    var lastError: Error? { nil }
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var currentAudio: String?
    private(set) var currentSubtitle: String?

    init(surface: UIView) {
        player.drawable = surface
    }

    func load(url: URL, startAt: Double?) {
        self.startAt = startAt
        let media = VLCMedia(url: url)
        media.addOptions(["network-caching": 1500])
        player.media = media
        player.play()
    }

    func refresh() {
        let state = player.state
        isPlaying = player.isPlaying
        isBuffering = state == .opening || (state == .buffering && !player.isPlaying)
        failed = state == .error
        didFinish = state == .ended || (state == .stopped && player.position > 0.97)
        currentSeconds = Double(player.time.intValue) / 1000
        durationSeconds = Double(player.media?.length.intValue ?? 0) / 1000

        if !didSeek, let startAt, startAt > 0, durationSeconds > 0, player.isPlaying {
            seek(to: startAt)
            didSeek = true
        }
        if audioTracks.isEmpty {
            audioTracks = Self.tracks(player.audioTrackIndexes, player.audioTrackNames)
        }
        if subtitleTracks.isEmpty {
            subtitleTracks = Self.tracks(player.videoSubTitlesIndexes, player.videoSubTitlesNames)
        }
        currentAudio = String(player.currentAudioTrackIndex)
        currentSubtitle = String(player.currentVideoSubTitleIndex)
    }

    private static func tracks(_ ids: [Any]?, _ names: [Any]?) -> [MediaTrack] {
        guard let ids, let names else { return [] }
        return zip(ids, names).compactMap { id, name in
            guard let number = id as? NSNumber else { return nil }
            let value = number.int32Value
            let title = value < 0 ? String(localized: "Off") : ((name as? String) ?? "\(value)")
            return MediaTrack(id: String(value), name: title)
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        player.time = VLCTime(int: Int32(max(seconds, 0) * 1000))
    }

    func selectAudio(_ id: String) {
        if let value = Int32(id) { player.currentAudioTrackIndex = value }
    }

    func selectSubtitle(_ id: String?) {
        player.currentVideoSubTitleIndex = id.flatMap { Int32($0) } ?? -1
    }

    func stop() {
        player.stop()
    }
}
#endif
