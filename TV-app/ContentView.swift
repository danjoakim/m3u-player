import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case search, home, live, movies, series, sport

    var title: LocalizedStringKey {
        switch self {
        case .search: "Search"
        case .home: "Home"
        case .live: "Live"
        case .movies: "Movies"
        case .series: "Series"
        case .sport: "Sports"
        }
    }

    var icon: String {
        switch self {
        case .search: "magnifyingglass"
        case .home: "house"
        case .live: "tv"
        case .movies: "film"
        case .series: "rectangle.stack"
        case .sport: "sportscourt"
        }
    }
}

/// Faner nederst på iPhone, smal ikonmeny til venstre på iPad.
struct ContentView: View {
    @State private var library = Library()
    @State private var tab: AppTab = .home
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                RailLayout(tab: $tab, screen: { screen($0) })
            } else {
                tabLayout
            }
        }
        .environment(library)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task { await library.bootstrap() }
        .fullScreenCover(item: $library.nowPlaying) { item in
            Group {
                if item.kind == .live {
                    ChannelWatchView(channel: item)
                } else {
                    PlayerScreen(item: item)
                }
            }
            .environment(library)
        }
    }

    private var tabLayout: some View {
        TabView(selection: $tab) {
            ForEach([AppTab.home, .live, .movies, .series, .sport], id: \.self) { item in
                Tab(item.title, systemImage: item.icon, value: item) {
                    screen(item)
                }
            }
            Tab(value: AppTab.search, role: .search) {
                screen(.search)
            }
        }
    }

    @ViewBuilder
    private func screen(_ item: AppTab) -> some View {
        NavigationStack {
            switch item {
            case .home: HomeView(tab: $tab).appDestinations()
            case .live: LiveView().appDestinations()
            case .movies: MoviesView().appDestinations()
            case .series: SeriesView().appDestinations()
            case .sport: SportView().appDestinations()
            case .search: SearchView().appDestinations()
            }
        }
    }
}

/// iPad: smal meny med bare ikoner. Skjermene beholder plassen sin når man bytter fane.
private struct RailLayout<Screen: View>: View {
    @Environment(Library.self) private var library
    @Binding var tab: AppTab
    let screen: (AppTab) -> Screen
    @State private var visited: Set<AppTab> = [.home]
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 0) {
            rail
            ZStack {
                ForEach(AppTab.allCases, id: \.self) { item in
                    if visited.contains(item) {
                        screen(item)
                            .opacity(item == tab ? 1 : 0)
                            .allowsHitTesting(item == tab)
                            .accessibilityHidden(item != tab)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: tab) { _, newValue in visited.insert(newValue) }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(library)
        }
    }

    private var rail: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.accent)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.bg)
                }
                .padding(.bottom, 22)
                .accessibilityHidden(true)

            ForEach(AppTab.allCases, id: \.self) { item in
                let selected = item == tab
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: item.icon)
                            .font(.system(size: 21, weight: .regular))
                        Capsule()
                            .fill(selected ? Theme.accent : Color.clear)
                            .frame(width: 18, height: 2.5)
                    }
                    .foregroundStyle(selected ? Theme.text : Color(hex: 0x7C869A))
                    .frame(width: 56, height: 58)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: 0x7C869A))
                    .frame(width: 56, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            let initial = library.profileName.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
            if let initial {
                Button {
                    showSettings = true
                } label: {
                    Text(verbatim: initial)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 40, height: 40)
                        .background(Color(hex: 0x2B3A55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 24)
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .background(Color(hex: 0x0D1016).ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(hex: 0x1A1F29)).frame(width: 1).ignoresSafeArea()
        }
    }
}

#Preview {
    ContentView()
}
