import SwiftUI

/// Kategorier sortert etter land: «NO | Sport» havner under «Norge» som «Sport».
nonisolated enum CategoryGroups {
    struct Section: Identifiable {
        let id: String
        let title: String
        let groups: [String]
    }

    /// Landskoden foran i en kategori: «NO | Sport», «|SE| Film», «[DK] Barn», «UK: News».
    static func code(of group: String) -> String? {
        let scalars = Array(group.trimmingCharacters(in: .whitespaces))
        var i = 0
        if i < scalars.count, "[(|".contains(scalars[i]) { i += 1 }
        while i < scalars.count, scalars[i] == " " { i += 1 }
        var code = ""
        while i < scalars.count, scalars[i].isASCII, scalars[i].isUppercase, code.count < 4 {
            code.append(scalars[i])
            i += 1
        }
        guard (2...3).contains(code.count) else { return nil }
        while i < scalars.count, scalars[i] == " " { i += 1 }
        guard i < scalars.count, "])|:-–".contains(scalars[i]) else { return nil }
        return code
    }

    /// «Norge», «Sverige», «Engelsk» – eller selve koden hvis den er ukjent.
    static func countryName(for code: String) -> String {
        let region = code == "UK" ? "GB" : code
        let locale = Locale.current
        if region.count == 2, let name = locale.localizedString(forRegionCode: region), name != region {
            return name
        }
        if let name = locale.localizedString(forLanguageCode: code.lowercased()), name.lowercased() != code.lowercased() {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return code
    }

    /// Navn uten landskode, til bruk inne i landets egen seksjon.
    static func shortName(_ group: String) -> String {
        TitleCleaner.cleanChannel(group)
    }

    /// Fullt, lesbart navn: «Norge · Sport».
    static func displayTitle(_ group: String) -> String {
        guard let code = code(of: group) else { return group }
        let short = shortName(group)
        return short == group ? group : countryName(for: code) + " · " + short
    }

    /// Seksjoner: brukerens land først, så de andre landene alfabetisk, og «Andre» til slutt.
    static func sections(_ groups: [String]) -> [Section] {
        let region = ChannelOrder.regionKeywords()
        var byCode: [String: [String]] = [:]
        var other: [String] = []
        for group in groups {
            if let code = code(of: group) {
                byCode[code, default: []].append(group)
            } else {
                other.append(group)
            }
        }
        // Et «land» med bare én kategori er ofte ikke et land; legg den under «Andre».
        for (code, list) in byCode where list.count == 1 {
            other.append(contentsOf: list)
            byCode[code] = nil
        }
        let codes = byCode.keys.sorted { a, b in
            let aLocal = region.short.contains(a), bLocal = region.short.contains(b)
            if aLocal != bLocal { return aLocal }
            return countryName(for: a).localizedCompare(countryName(for: b)) == .orderedAscending
        }
        var result = codes.map { Section(id: $0, title: countryName(for: $0), groups: byCode[$0] ?? []) }
        if !other.isEmpty {
            result.append(Section(id: "_other", title: String(localized: "Other"), groups: other))
        }
        return result
    }
}

/// Stor knapp som viser valgt kategori og åpner kategorilisten.
struct CategoryPicker: View {
    let options: [String]
    var counts: [String: Int] = [:]
    @Binding var selection: String?
    let scope: String

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSheet = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(selection.map(CategoryGroups.displayTitle) ?? String(localized: "All categories"))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .font(.headline)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
                .background(selection == nil ? Theme.surface : Theme.accent.opacity(0.15), in: Capsule())
                .overlay(Capsule().stroke(selection == nil ? Theme.border : Theme.accent))
            }
            .buttonStyle(.plain)

            if selection != nil {
                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show All")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, sizeClass == .compact ? 20 : 32)
        .sheet(isPresented: $showSheet) {
            CategorySheet(options: options, counts: counts, selection: $selection, scope: scope)
        }
    }
}

/// Liste over alle kategorier, sortert etter land, med søk og nylig brukte øverst.
private struct CategorySheet: View {
    let options: [String]
    let counts: [String: Int]
    @Binding var selection: String?
    let scope: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sections: [CategoryGroups.Section] = []
    @State private var recents: [String] = []

    private var recentsKey: String { "recentCategories." + scope }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        row(nil, title: String(localized: "All categories"))
                    }
                    if !recents.isEmpty {
                        Section("Recent") {
                            ForEach(recents, id: \.self) { group in
                                row(group, title: CategoryGroups.displayTitle(group))
                            }
                        }
                    }
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.groups, id: \.self) { group in
                                row(group, title: section.id == "_other" ? group : CategoryGroups.shortName(group))
                            }
                        }
                    }
                } else {
                    let matches = options.filter {
                        $0.localizedCaseInsensitiveContains(query)
                            || CategoryGroups.displayTitle($0).localizedCaseInsensitiveContains(query)
                    }
                    ForEach(matches, id: \.self) { group in
                        row(group, title: CategoryGroups.displayTitle(group))
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search categories")
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if !query.isEmpty, !options.contains(where: { $0.localizedCaseInsensitiveContains(query) || CategoryGroups.displayTitle($0).localizedCaseInsensitiveContains(query) }) {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            sections = CategoryGroups.sections(options)
            let saved = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
            recents = saved.filter { options.contains($0) }
        }
    }

    private func row(_ group: String?, title: String) -> some View {
        Button {
            selection = group
            if let group { remember(group) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let group, let count = counts[group] {
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
                if selection == group {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func remember(_ group: String) {
        var list = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        list.removeAll { $0 == group }
        list.insert(group, at: 0)
        UserDefaults.standard.set(Array(list.prefix(5)), forKey: recentsKey)
    }
}
