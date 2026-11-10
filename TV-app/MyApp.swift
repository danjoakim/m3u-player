import SwiftUI
import AVFoundation

@main struct MyApp: App {
    init() {
        // Lyd også når lydløs-bryteren er på, og støtte for bilde-i-bilde.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
