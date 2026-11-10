import SwiftUI
import AVKit
import UIKit
import AVFoundation

/// Video med Strøms egne kontroller. Ser likt ut uansett om Apples spiller eller VLC spiller.
struct StreamPlayerView: View {
    let model: PlayerModel
    var title: String? = nil
    var isFullscreen = false
    var onToggleFullscreen: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var showControls = true
    @State private var scrub: Double?

    var body: some View {
        ZStack {
            Color.black
            VideoSurface(model: model)

            if (model.isPreparing || model.isBuffering) && !model.failed {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if model.failed {
                errorView
            }

            if showControls || model.failed {
                controls
                    .transition(.opacity)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        }
        // Skjul kontrollene etter noen sekunder når noe spiller.
        .task(id: "\(showControls)-\(model.isPlaying)") {
            guard showControls, model.isPlaying else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, model.isPlaying, scrub == nil, !model.failed {
                withAnimation(.easeInOut(duration: 0.3)) { showControls = false }
            }
        }
    }

    // MARK: - Kontroller

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if !model.isPreparing && !model.failed {
                centerButtons
            }
            Spacer(minLength: 0)
            bottomBar
        }
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            if let onClose {
                iconButton("xmark", label: "Close", action: onClose)
            }
            if let title {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.leading, onClose == nil ? 8 : 0)
            }
            Spacer(minLength: 8)
            RoutePicker()
                .frame(width: 44, height: 44)
            if model.canPictureInPicture {
                iconButton("pip.enter", label: "Picture in Picture") { model.startPictureInPicture() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 28)
        .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var centerButtons: some View {
        HStack(spacing: 40) {
            if !model.isLive {
                iconButton("gobackward.10", label: "Back 10 seconds", font: .title2) { model.skip(by: -10) }
            }
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 68, height: 68)
                    .background(Color.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
            if !model.isLive {
                iconButton("goforward.10", label: "Forward 10 seconds", font: .title2) { model.skip(by: 10) }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if !model.isLive, model.durationSeconds > 0 {
                HStack(spacing: 10) {
                    Text(Self.format(scrub.map { $0 * model.durationSeconds } ?? model.currentSeconds))
                    Slider(value: Binding(
                        get: { scrub ?? min(model.currentSeconds / max(model.durationSeconds, 1), 1) },
                        set: { scrub = $0 }
                    ), onEditingChanged: { editing in
                        if !editing, let value = scrub {
                            model.seek(to: value * model.durationSeconds)
                            scrub = nil
                        }
                    })
                    .tint(Theme.accent)
                    Text(Self.format(model.durationSeconds))
                }
                .font(.caption.monospacedDigit())
            }
            HStack(spacing: 4) {
                if model.isLive {
                    Text("LIVE")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(Color(hex: 0x14070A))
                        .background(Theme.live, in: .rect(cornerRadius: 6))
                        .padding(.leading, 8)
                }
                Spacer(minLength: 8)
                if model.audioTracks.count > 1 {
                    trackMenu(model.audioTracks, current: model.currentAudio, icon: "waveform", label: "Audio") {
                        model.selectAudio($0)
                    }
                }
                if model.subtitleTracks.count > 1 {
                    trackMenu(model.subtitleTracks, current: model.currentSubtitle, icon: "captions.bubble", label: "Subtitles") {
                        model.selectSubtitle($0)
                    }
                }
                if let onToggleFullscreen {
                    iconButton(isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               label: isFullscreen ? "Exit Full Screen" : "Full Screen",
                               action: onToggleFullscreen)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 28)
        .padding(.bottom, 6)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
    }

    private var errorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
            Text("The stream may be unavailable, or in a format Apple's player doesn't support.")
                .font(.subheadline)
            if let detail = model.errorDetail {
                Text(verbatim: detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(32)
    }

    // MARK: - Hjelpere

    private func iconButton(_ systemName: String, label: LocalizedStringKey, font: Font = .title3,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func trackMenu(_ tracks: [MediaTrack], current: String?, icon: String, label: LocalizedStringKey,
                           select: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(tracks) { track in
                Button {
                    select(track.id)
                } label: {
                    if track.id == current {
                        Label(track.name, systemImage: "checkmark")
                    } else {
                        Text(track.name)
                    }
                }
            }
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    private static func format(_ seconds: Double) -> String {
        let value = Int(max(seconds, 0))
        let pattern: Duration.TimeFormatStyle.Pattern = value >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(value).formatted(.time(pattern: pattern))
    }
}

/// Viser modellens videoflate. Samme flate gjenbrukes når visningen bytter mellom vindu og fullskjerm.
private struct VideoSurface: UIViewRepresentable {
    let model: PlayerModel

    func makeUIView(context: Context) -> SurfaceHost { SurfaceHost(surface: model.surface) }
    func updateUIView(_ uiView: SurfaceHost, context: Context) {}
}

/// Holder på videoflaten. Når en ny visning dukker opp (f.eks. fullskjerm), flytter den flaten
/// over til seg, så videoen fortsetter uten avbrudd.
final class SurfaceHost: UIView {
    private let surface: VideoSurfaceView

    init(surface: VideoSurfaceView) {
        self.surface = surface
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false
        adopt()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func adopt() {
        if surface.superview !== self {
            surface.removeFromSuperview()
            addSubview(surface)
        }
        surface.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { adopt() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if surface.superview === self { surface.frame = bounds }
    }
}

/// AirPlay-knappen.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(Theme.accent)
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
