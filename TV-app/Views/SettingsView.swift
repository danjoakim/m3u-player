import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LocalAuthentication

struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showImporter = false

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                // MARK: Kilde
                Section {
                    Picker("Source", selection: $library.sourceKind) {
                        Text("M3U Link").tag(SourceKind.m3u)
                        Text(verbatim: "Xtream Codes").tag(SourceKind.xtream)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if library.sourceKind == .m3u {
                        TextField("https://…/playlist.m3u", text: $library.playlistURL, axis: .vertical)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await library.loadPlaylist() }
                        } label: {
                            Text("Load Playlist")
                        }
                        .disabled(library.isLoading || library.playlistURL.isEmpty)
                        Button("Import M3U File…") { showImporter = true }
                            .disabled(library.isLoading)
                    } else {
                        TextField("Server address", text: $library.xtreamServer)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                        TextField("Username", text: $library.xtreamUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                        SecureField("Password", text: $library.xtreamPassword)
                            .textContentType(.password)
                        Button {
                            Task { await library.loadPlaylist() }
                        } label: {
                            Text("Log In")
                        }
                        .disabled(library.isLoading || library.xtreamServer.isEmpty
                                  || library.xtreamUsername.isEmpty || library.xtreamPassword.isEmpty)
                        if let expiry = library.xtreamExpiry {
                            LabeledContent("Account expires", value: expiry.formatted(date: .abbreviated, time: .omitted))
                        }
                    }

                    if let progress = library.playlistProgress {
                        LoadProgressView(progress: progress)
                    }
                } header: {
                    Text("Playlist")
                } footer: {
                    if library.sourceKind == .m3u {
                        Text("Paste the link from your provider, or import a file. The playlist is stored on this device.")
                    } else {
                        Text("Enter the server address, username and password from your provider. The password is stored securely in the keychain.")
                    }
                }

                if let error = library.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.live)
                    }
                }

                // MARK: TV-guide
                Section {
                    TextField("https://…/epg.xml.gz", text: $library.epgURL, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await library.loadEPG() }
                    } label: {
                        Text("Update TV Guide")
                    }
                    .disabled(library.isLoadingEPG || library.isSample || library.resolvedEPGURL() == nil)
                    if let progress = library.epgProgress {
                        LoadProgressView(progress: progress)
                    }
                    if let epg = library.epg {
                        LabeledContent("Channels with Guide", value: "\(epg.channelCount)")
                        if !library.isSample {
                            LabeledContent("Updated", value: epg.updated.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    if let error = library.epgError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.live)
                    }
                } header: {
                    Text("TV Guide (EPG)")
                } footer: {
                    if library.isSample {
                        Text("The sample channels have a built-in TV guide. Add your own playlist first.")
                    } else if library.sourceKind == .xtream {
                        Text("Xtream accounts get their TV guide automatically. Enter a link here only to use a different guide.")
                    } else {
                        Text("XMLTV link from your provider, .xml or .xml.gz. Filled in automatically if the playlist includes one. The guide updates every 12 hours.")
                    }
                }

                // MARK: Innhold
                // MARK: Profil
                Section {
                    TextField("Your name", text: $library.profileName)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Shown on the home page, for example “Continue Watching for Dan”.")
                }

                // MARK: Avspilling
                Section {
                    Toggle("Autoplay Next Episode", isOn: $library.autoplayNext)
                        .tint(Theme.accent)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("When an episode ends, the next one starts after a 10-second countdown. When this is off, you can still start the next episode yourself.")
                }

                // MARK: Voksent innhold
                Section {
                    Toggle("Hide Adult Content", isOn: Binding(
                        get: { library.hideAdult },
                        set: { newValue in
                            if newValue {
                                library.setHideAdult(true)
                            } else {
                                Task {
                                    if await confirmOwner() { library.setHideAdult(false) }
                                }
                            }
                        }
                    ))
                    .tint(Theme.accent)
                } footer: {
                    if library.adultCategoryCount > 0 {
                        Text("Hides categories such as XXX, Adult and 18+ everywhere in the app. Turning it off requires Face ID, Touch ID or your passcode. Your playlist has \(library.adultCategoryCount) such categories.")
                    } else {
                        Text("Hides categories such as XXX, Adult and 18+ everywhere in the app. Turning it off requires Face ID, Touch ID or your passcode.")
                    }
                }

                Section("Content") {
                    LabeledContent("Channels", value: "\(library.catalog.live.count)")
                    LabeledContent("Movies", value: "\(library.catalog.movies.count)")
                    LabeledContent("Series", value: "\(library.catalog.series.count)")
                    if library.isSample {
                        LabeledContent("Source", value: String(localized: "Sample content"))
                    } else if let date = library.lastUpdated {
                        LabeledContent("Updated", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                // MARK: Språk
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Text("Language")
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(currentLanguage)
                                .foregroundStyle(Theme.muted)
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(Theme.muted)
                        }
                    }
                } footer: {
                    Text("Opens iOS Settings, where you can choose the language for this app.")
                }

                Section {
                    Button("Reset to Sample Content", role: .destructive) {
                        library.resetToSample()
                    }
                } footer: {
                    Text("The app doesn't include any content. Only use playlists you have the right to watch.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.m3uPlaylist, .plainText, .data]) { result in
                if case .success(let url) = result {
                    Task { await library.importFile(url) }
                }
            }
        }
    }

    /// Bekrefter med Face ID, Touch ID eller kode. Har enheten ingen kode, tillates det.
    private func confirmOwner() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: String(localized: "Show adult content"))
        } catch {
            return false
        }
    }

    /// Språket appen faktisk vises på, med navnet på det språket.
    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let name = Locale.current.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// Fremdriftslinje med tekst: «Laster ned 12 MB av 40 MB».
struct LoadProgressView: View {
    let progress: LoadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.accent)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    label
                }
            }
            if progress.fraction != nil {
                label
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var label: some View {
        Group {
            switch progress.phase {
            case .connecting:
                Text("Connecting…")
            case .downloading:
                let received = progress.received.formatted(.byteCount(style: .file))
                if progress.expected > 0 {
                    let expected = progress.expected.formatted(.byteCount(style: .file))
                    Text("Downloading \(received) of \(expected)")
                } else {
                    Text("Downloading \(received)")
                }
            case .processing:
                Text("Processing…")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.muted)
        .monospacedDigit()
    }
}
