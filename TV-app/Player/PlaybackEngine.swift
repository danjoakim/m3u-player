import UIKit
import AVFoundation
import AVKit
import Foundation

struct MediaTrack: Identifiable, Hashable {
    let id: String
    let name: String
}

nonisolated enum EngineKind: Sendable {
    case apple, vlc
}

/// Felles grensesnitt for Apples spiller og VLC, så resten av appen ikke trenger å vite hvilken som brukes.
protocol PlaybackEngine: AnyObject {
    var isPlaying: Bool { get }
    var isBuffering: Bool { get }
    var currentSeconds: Double { get }
    var durationSeconds: Double { get }
    var failed: Bool { get }
    var lastError: Error? { get }
    /// Avspillingen har nådd slutten.
    var didFinish: Bool { get }
    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    var currentAudio: String? { get }
    var currentSubtitle: String? { get }

    func load(url: URL, startAt: Double?)
    func play()
    func pause()
    func seek(to seconds: Double)
    func selectAudio(_ id: String)
    func selectSubtitle(_ id: String?)
    func refresh()
    func stop()
}

/// Flaten videoen tegnes på. Én og samme flate brukes hele tiden, også når
/// visningen bytter mellom vindu og fullskjerm, så avspillingen aldri starter på nytt.
final class VideoSurfaceView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        // Trykk skal gå til kontrollene, ikke fanges av videoen.
        isUserInteractionEnabled = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.forEach { if $0 is AVPlayerLayer { $0.frame = bounds } }
        subviews.forEach { $0.frame = bounds }
    }
}

// MARK: - Apples spiller

final class AppleEngine: PlaybackEngine {
    let player = AVPlayer()
    let playerLayer: AVPlayerLayer
    private(set) var pip: AVPictureInPictureController?
    private var item: AVPlayerItem?
    private var audioGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?

    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var currentAudio: String?
    private(set) var currentSubtitle: String?

    var isPlaying: Bool { player.timeControlStatus == .playing }
    var isBuffering: Bool {
        player.timeControlStatus == .waitingToPlayAtSpecifiedRate || item?.status == .unknown
    }
    var currentSeconds: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }
    var durationSeconds: Double {
        let seconds = item?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }
    var failed: Bool { item?.status == .failed }
    var didFinish: Bool {
        durationSeconds > 0 && currentSeconds >= durationSeconds - 1 && player.rate == 0
    }
    var lastError: Error? { item?.error }
    var isReady: Bool { item?.status == .readyToPlay }
    var hasVideo: Bool { (item?.presentationSize ?? .zero) != .zero }
    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    init(surface: VideoSurfaceView) {
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = surface.bounds
        surface.layer.addSublayer(playerLayer)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer: playerLayer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    func load(url: URL, startAt: Double?) {
        let item = AVPlayerItem(url: url)
        self.item = item
        player.replaceCurrentItem(with: item)
        player.play()
        Task { await loadTracks(for: item) }
    }

    private func loadTracks(for item: AVPlayerItem) async {
        let asset = item.asset
        if let group = try? await asset.loadMediaSelectionGroup(for: .audible) {
            audioGroup = group
            audioTracks = group.options.enumerated().map { MediaTrack(id: String($0.offset), name: $0.element.displayName) }
        }
        if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
            legibleGroup = group
            subtitleTracks = [MediaTrack(id: "off", name: String(localized: "Off"))]
                + group.options.enumerated().map { MediaTrack(id: String($0.offset), name: $0.element.displayName) }
        }
    }

    func refresh() {
        guard let item else { return }
        if let group = audioGroup,
           let option = item.currentMediaSelection.selectedMediaOption(in: group),
           let index = group.options.firstIndex(of: option) {
            currentAudio = String(index)
        }
        if let group = legibleGroup {
            if let option = item.currentMediaSelection.selectedMediaOption(in: group),
               let index = group.options.firstIndex(of: option) {
                currentSubtitle = String(index)
            } else {
                currentSubtitle = "off"
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func selectAudio(_ id: String) {
        guard let group = audioGroup, let index = Int(id), group.options.indices.contains(index) else { return }
        item?.select(group.options[index], in: group)
    }

    func selectSubtitle(_ id: String?) {
        guard let group = legibleGroup else { return }
        if let id, let index = Int(id), group.options.indices.contains(index) {
            item?.select(group.options[index], in: group)
        } else {
            item?.select(nil, in: group)
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerLayer.removeFromSuperlayer()
    }
}
