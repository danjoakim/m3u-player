import SwiftUI

struct MoviesView: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var group: String?
    @State private var query = ""

    private var items: [MediaItem] {
        library.visibleMovies.filter { item in
            (group == nil || item.group == group)
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let items = self.items
        let minWidth: CGFloat = sizeClass == .compact ? 105 : 150
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CategoryPicker(options: library.visibleMovieGroups, counts: library.movieCategoryCounts, selection: $group, scope: "movies")
                    .padding(.vertical, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 14)], spacing: 20) {
                    ForEach(items) { movie in
                        NavigationLink(value: movie) {
                            PosterCard(title: movie.name, subtitle: movie.group, artwork: movie.logo,
                                       progress: library.progress(for: movie.id))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                library.toggleFavorite(movie.id)
                            } label: {
                                Label(library.isFavorite(movie.id) ? String(localized: "Remove from My List") : String(localized: "Add to My List"),
                                      systemImage: library.isFavorite(movie.id) ? "minus" : "plus")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .navigationTitle("Movies")
        .searchable(text: $query, prompt: "Search movies")
        .overlay {
            if library.isRestoring {
                RestoringView()
            } else if items.isEmpty {
                ContentUnavailableView("No Movies", systemImage: "film",
                                       description: Text("Your playlist has no movies in this selection."))
            }
        }
    }
}
