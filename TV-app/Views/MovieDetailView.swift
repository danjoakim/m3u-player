import SwiftUI

/// Infoside for en film: bilde, handling, detaljer og avspillingsknapper.
struct MovieDetailView: View {
    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    let movie: MediaItem

    @State private var info: VODInfo?
    @State private var isLoading = true

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        let favorite = library.isFavorite(movie.id)
        let progress = library.progress(for: movie.id) ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHeader(title: movie.name,
                             meta: metaLine,
                             backdrop: info?.backdrop ?? info?.poster ?? movie.logo,
                             poster: info?.poster ?? movie.logo)

                HStack(spacing: 10) {
                    Button {
                        library.play(movie)
                    } label: {
                        Label(progress > 0.01 && progress < 0.95 ? String(localized: "Resume") : String(localized: "Play"),
                              systemImage: "play.fill")
                            .frame(maxWidth: compact ? .infinity : nil)
                    }
                    .buttonStyle(AccentButtonStyle())

                    Button {
                        library.toggleFavorite(movie.id)
                    } label: {
                        Image(systemName: favorite ? "checkmark" : "plus")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .accessibilityLabel(favorite ? String(localized: "Remove from My List") : String(localized: "Add to My List"))

                    if let trailer = info?.trailer {
                        Button {
                            openURL(trailer)
                        } label: {
                            Label("Trailer", systemImage: "film.stack")
                                .padding(.horizontal, 14)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
                .padding(.horizontal, 20)

                if progress > 0.01 && progress < 0.95 {
                    ProgressBar(value: progress)
                        .clipShape(Capsule())
                        .padding(.horizontal, 20)
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }

                if let plot = info?.plot {
                    Text(plot)
                        .font(.body)
                        .foregroundStyle(Theme.soft)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: 760, alignment: .leading)
                }

                DetailFacts(facts: [
                    ("Director", info?.director),
                    ("Cast", info?.cast),
                    ("Genre", info?.genre),
                    ("Category", movie.group)
                ])
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .navigationTitle(movie.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            info = await library.vodInfo(for: movie)
            isLoading = false
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = info?.year { parts.append(year) }
        if let duration = info?.durationText { parts.append(duration) }
        if let genre = info?.genre?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) {
            parts.append(genre)
        }
        if let rating = info?.rating { parts.append("★ " + rating) }
        return parts.isEmpty ? String(localized: "Movie") : parts.joined(separator: " · ")
    }
}

/// Stort bilde øverst med tittel, og plakat ved siden av på iPad.
struct DetailHeader: View {
    let title: String
    let meta: String
    let backdrop: URL?
    let poster: URL?

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        Theme.tint(for: title)
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color.white.opacity(0.06))
                    .frame(width: 320, height: 320)
                    .offset(x: 80, y: -40)
            }
            .overlay {
                if let backdrop {
                    AsyncImage(url: backdrop) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .overlay {
                LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg],
                               startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 20) {
                    if !compact, let poster {
                        AsyncImage(url: poster) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Theme.surface
                            }
                        }
                        .frame(width: 140, height: 210)
                        .clipShape(.rect(cornerRadius: 12))
                        .shadow(radius: 12)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: compact ? 32 : 44, weight: .bold))
                            .tracking(-1)
                            .foregroundStyle(Theme.text)
                            .lineLimit(3)
                        Text(meta)
                            .font(.subheadline)
                            .foregroundStyle(Theme.soft)
                    }
                }
                .padding(20)
            }
            .frame(height: compact ? 300 : 400)
            .clipped()
    }
}

/// Faktaliste: regissør, skuespillere, sjanger osv. Tomme felt vises ikke.
struct DetailFacts: View {
    let facts: [(LocalizedStringKey, String?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(facts.enumerated()), id: \.offset) { entry in
                let fact = entry.element
                if let value = fact.1, !value.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.0)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}
