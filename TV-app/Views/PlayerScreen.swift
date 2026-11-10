import SwiftUI
import AVKit

/// Fullskjermspiller for filmer og episoder, med Strøms felles kontroller.
/// Går automatisk videre til neste episode når en episode er ferdig.
struct PlayerScreen: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var model = PlayerModel()
    @State private var item: MediaItem
    @State private var nextEpisode: MediaItem?
    @State private var countdown: Int?
    @State private var autoplayCancelled = false

    private static let countdownSeconds = 10

    init(item: MediaItem) {
        _item = State(initialValue: item)
    }

    private var title: String {
        if let series = item.seriesTitle, let code = item.episodeCode {
            return series + " · " + code
        }
        return item.name
    }

    /// «Neste episode»-knappen vises de siste 40 sekundene og når episoden er ferdig.
    private var showNext: Bool {
        guard nextEpisode != nil, !autoplayCancelled else { return false }
        if model.didFinish { return true }
        let remaining = model.durationSeconds - model.currentSeconds
        return model.durationSeconds > 120 && remaining > 0 && remaining <= 40
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()
            StreamPlayerView(model: model, title: title, onClose: close)

            if showNext, let next = nextEpisode {
                NextEpisodeCard(episode: next, countdown: countdown,
                                total: Self.countdownSeconds,
                                onPlay: playNext,
                                onCancel: {
                                    autoplayCancelled = true
                                    countdown = nil
                                })
                .padding(.trailing, 24)
                .padding(.bottom, 96)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showNext)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task(id: item.id) {
            nextEpisode = nil
            countdown = nil
            autoplayCancelled = false
            let start = item.kind == .live ? nil : library.resumePosition(for: item.id)
            model.load(item, startAt: start, library: library)
            nextEpisode = await library.nextEpisode(after: item)
        }
        .onChange(of: model.didFinish) { _, finished in
            guard finished else { return }
            markFinished()
            // Uten automatisk avspilling blir kortet stående med «Spill nå».
            if library.autoplayNext, nextEpisode != nil, !autoplayCancelled {
                countdown = Self.countdownSeconds
            }
        }
        .task(id: countdown) {
            guard let seconds = countdown else { return }
            if seconds <= 0 {
                playNext()
                return
            }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled, countdown == seconds {
                countdown = seconds - 1
            }
        }
    }

    /// Lagrer episoden som sett.
    private func markFinished() {
        guard item.kind != .live, model.durationSeconds > 0 else { return }
        library.saveProgress(id: item.id, position: model.durationSeconds,
                             duration: model.durationSeconds, item: item)
    }

    private func playNext() {
        guard let next = nextEpisode else { return }
        markFinished()
        countdown = nil
        item = next
    }

    private func close() {
        if item.kind != .live, !model.didFinish {
            library.saveProgress(id: item.id, position: model.currentSeconds,
                                 duration: model.durationSeconds, item: item)
        }
        model.stop()
        dismiss()
    }
}

/// Kort nede til høyre: «Neste episode», med nedtelling når episoden er ferdig.
private struct NextEpisodeCard: View {
    let episode: MediaItem
    let countdown: Int?
    let total: Int
    let onPlay: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next Episode")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Theme.accent)
            if let code = episode.episodeCode {
                Text(code)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
            }
            HStack(spacing: 10) {
                Button(action: onPlay) {
                    HStack(spacing: 8) {
                        if let countdown {
                            ZStack {
                                Circle().stroke(Theme.bg.opacity(0.25), lineWidth: 3)
                                Circle()
                                    .trim(from: 0, to: CGFloat(countdown) / CGFloat(max(total, 1)))
                                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 1), value: countdown)
                            }
                            .frame(width: 18, height: 18)
                            Text("Next episode in \(countdown) s")
                        } else {
                            Image(systemName: "forward.end.fill")
                            Text("Play Now")
                        }
                    }
                    .monospacedDigit()
                }
                .buttonStyle(AccentButtonStyle())

                if countdown != nil {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(GhostButtonStyle())
                }
            }
        }
        .padding(16)
        .background(Theme.surface.opacity(0.95), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
        .frame(maxWidth: 360, alignment: .trailing)
    }
}
