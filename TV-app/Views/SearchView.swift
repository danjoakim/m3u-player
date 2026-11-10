import SwiftUI

struct SearchView: View {
    @Environment(Library.self) private var library
    @State private var query = ""

    var body: some View {
        let channels = query.isEmpty ? [] : Array(library.orderedLive.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(30))
        let movies = query.isEmpty ? [] : Array(library.visibleMovies.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(30))
        let shows = query.isEmpty ? [] : Array(library.visibleSeries.filter { $0.title.localizedCaseInsensitiveContains(query) }.prefix(30))

        List {
            if !channels.isEmpty {
                Section("Channels") {
                    ForEach(channels) { item in
                        ChannelRow(item: item)
                    }
                }
            }
            if !shows.isEmpty {
                Section("Series") {
                    ForEach(shows) { show in
                        NavigationLink(value: show) {
                            HStack(spacing: 14) {
                                LogoTile(name: show.title, logo: show.logo, size: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(show.title).font(.body.weight(.semibold))
                                    Text(show.episodesText).font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
            }
            if !movies.isEmpty {
                Section("Movies") {
                    ForEach(movies) { movie in
                        NavigationLink(value: movie) {
                            HStack(spacing: 14) {
                                LogoTile(name: movie.name, logo: movie.logo, size: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(movie.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                                    Text(movie.group).font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Channels, movies and series")
        .overlay {
            if query.isEmpty {
                ContentUnavailableView("Search Everything", systemImage: "magnifyingglass",
                                       description: Text("Find channels, movies and series."))
            } else if channels.isEmpty && movies.isEmpty && shows.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
