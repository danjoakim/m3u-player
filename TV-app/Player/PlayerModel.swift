import SwiftUI
import UIKit
import AVFoundation
import AVKit

/// Styrer avspillingen: velger motor, viser ventehjul mens strømmen sjekkes,
/// og bytter til VLC hvis Apples spiller bare gir lyd eller feiler.
@Observable
final class PlayerModel {
    let surface = VideoSurfaceView()

    private(set) var engineKind: EngineKind?
    private(set) var itemID: String?
    private(set) var isLive = false
    /// Mens motoren velges og vi venter på bilde. Vises som ventehjul.
    private(set) var isPreparing = false
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentSeconds = 0.0
    private(set) var durationSeconds = 0.0
    private(set) var failed = false
    /// Filmen eller episoden er spilt ferdig.
    private(set) var didFinish = false
    private(set) var errorDetail: String?
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var currentAudio: String?
    private(set) var currentSubtitle: String?
    private(set) var canPictureInPicture = false

    private var engine: PlaybackEngine?
    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    // MARK: - Start og stopp

    /// Starter avspilling. Gjør ingenting hvis samme innhold allerede spilles.
    func load(_ item: MediaItem, startAt: Double?, library: Library) {
        guard itemID != item.id else { return }
        itemID = item.id
        isLive = item.kind == .live
        loadTask?.cancel()
        teardown()
        failed = false
        errorDetail = nil
        isPreparing = true
        startPolling()
        loadTask = Task { await run(item: item, startAt: startAt, library: library) }
    }

    func stop() {
        loadTask?.cancel()
        pollTask?.cancel()
        pollTask = nil
        teardown()
        itemID = nil
    }

    private func run(item: MediaItem, startAt: Double?, library: Library) async {
        let (kind, url) = await EngineSelector.choose(for: item.url,
                                                      rememberedVLC: library.needsVLC(item.id),
                                                      vlcAvailable: VLCSupport.isAvailable)
        guard !Task.isCancelled else { return }

        if kind == .apple {
            let apple = AppleEngine(surface: surface)
            apple.isMuted = true   // ingen lyd før vi vet at bildet virker
            engine = apple
            engineKind = .apple
            apple.load(url: url, startAt: nil)

            let outcome = await waitForPicture(apple)
            guard !Task.isCancelled else { return }

            switch outcome {
            case .picture:
                if let startAt, startAt > 0 { apple.seek(to: startAt) }
                apple.isMuted = false
                canPictureInPicture = apple.pip != nil
                isPreparing = false
                return
            case .soundOnly where !VLCSupport.isAvailable:
                apple.isMuted = false
                isPreparing = false
                return
            case .failed where !VLCSupport.isAvailable:
                errorDetail = PlaybackDiagnostics.describe(apple.lastError, url: url)
                failed = true
                isPreparing = false
                teardown()
                return
            default:
                // Lyd uten bilde eller feil: VLC tar over, og vi husker det til neste gang.
                library.markNeedsVLC(item.id)
                teardown()
            }
        }

        guard let vlc = VLCSupport.makeEngine(surface: surface) else {
            failed = true
            isPreparing = false
            return
        }
        engine = vlc
        engineKind = .vlc
        vlc.load(url: url, startAt: startAt)
        isPreparing = false
    }

    private enum Outcome { case picture, soundOnly, failed }

    private func waitForPicture(_ apple: AppleEngine) async -> Outcome {
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !apple.isReady {
            if apple.failed || Task.isCancelled || ContinuousClock.now > readyDeadline { return .failed }
            try? await Task.sleep(for: .milliseconds(150))
        }
        let videoDeadline = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < videoDeadline, !Task.isCancelled {
            if apple.hasVideo { return .picture }
            if apple.failed { return .failed }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return apple.hasVideo ? .picture : .soundOnly
    }

    private func teardown() {
        engine?.stop()
        engine = nil
        engineKind = nil
        surface.subviews.forEach { $0.removeFromSuperview() }
        isPlaying = false
        isBuffering = false
        currentSeconds = 0
        durationSeconds = 0
        audioTracks = []
        subtitleTracks = []
        currentAudio = nil
        currentSubtitle = nil
        canPictureInPicture = false
        didFinish = false
    }

    // MARK: - Tilstand

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func poll() {
        guard let engine else { return }
        engine.refresh()
        isPlaying = engine.isPlaying
        isBuffering = engine.isBuffering
        currentSeconds = engine.currentSeconds
        durationSeconds = engine.durationSeconds
        audioTracks = engine.audioTracks
        subtitleTracks = engine.subtitleTracks
        currentAudio = engine.currentAudio
        currentSubtitle = engine.currentSubtitle
        if !isLive, !isPreparing, engine.didFinish != didFinish {
            didFinish = engine.didFinish
        }
        if !isPreparing, engine.failed, !failed {
            failed = true
        }
    }

    // MARK: - Kontroller

    func togglePlay() {
        guard let engine else { return }
        if engine.isPlaying { engine.pause() } else { engine.play() }
        poll()
    }

    func seek(to seconds: Double) {
        engine?.seek(to: seconds)
        currentSeconds = seconds
    }

    func skip(by seconds: Double) {
        seek(to: max(currentSeconds + seconds, 0))
    }

    func selectAudio(_ id: String) {
        engine?.selectAudio(id)
        poll()
    }

    func selectSubtitle(_ id: String) {
        engine?.selectSubtitle(id == "off" || id == "-1" ? nil : id)
        poll()
    }

    func startPictureInPicture() {
        (engine as? AppleEngine)?.pip?.startPictureInPicture()
    }
}
