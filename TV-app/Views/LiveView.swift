import SwiftUI

struct LiveView: View {
    enum Mode: CaseIterable {
        case list, guide

        var title: LocalizedStringKey {
            switch self {
            case .list: "List"
            case .guide: "TV Guide"
            }
        }
    }

    @Environment(Library.self) private var library
    @State private var mode: Mode = .list
    @State private var group: String?
    @State private var query = ""
    @State private var showCategories = false

    private var items: [MediaItem] {
        library.orderedLive.filter { item in
            (group == nil || item.group == group)
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let items = self.items
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            CategoryPicker(options: library.visibleLiveGroups, counts: library.liveCategoryCounts, selection: $group, scope: "live")
                .padding(.vertical, 10)

            if mode == .list {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            ChannelRow(item: item)
                                .padding(.horizontal, 20)
                            Divider()
                                .overlay(Theme.border)
                                .padding(.leading, 82)
                        }
                    }
                }
            } else {
                GuideView(channels: Array(items.prefix(300)))
                if items.count > 300 {
                    Text("Showing the first 300 channels. Choose a category to see more.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .padding(8)
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle("Live TV")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCategories = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Manage Categories")
            }
        }
        .sheet(isPresented: $showCategories) {
            CategoryManagerView().environment(library)
        }
        .searchable(text: $query, prompt: "Search channels")
        .overlay {
            if library.isRestoring {
                RestoringView()
            } else if items.isEmpty {
                ContentUnavailableView("No Channels", systemImage: "tv",
                                       description: Text("Try another category or search."))
            }
        }
    }
}
