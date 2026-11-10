import SwiftUI

/// Velg rekkefølge på kanalkategoriene og skjul de du ikke bruker.
struct CategoryManagerView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var order: [String] = []
    @State private var hidden: Set<String> = []
    @State private var counts: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Sort by My Region") {
                        order = ChannelOrder.automatic(library.catalog.liveGroups).filter { !library.isHidden(group: $0) }
                    }
                    Button("Show All") {
                        hidden = []
                    }
                    .disabled(hidden.isEmpty)
                } footer: {
                    Text("Drag to reorder categories. Hidden categories aren't shown in channel lists.")
                }

                Section {
                    ForEach(order, id: \.self) { group in
                        let isHidden = hidden.contains(group)
                        HStack(spacing: 12) {
                            Button {
                                if isHidden { hidden.remove(group) } else { hidden.insert(group) }
                            } label: {
                                Image(systemName: isHidden ? "eye.slash" : "eye")
                                    .foregroundStyle(isHidden ? Theme.muted : Theme.accent)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isHidden ? String(localized: "Show") : String(localized: "Hide"))

                            Text(group)
                                .foregroundStyle(isHidden ? Theme.muted : Theme.text)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(counts[group] ?? 0)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .monospacedDigit()
                        }
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        library.setLiveGroups(order: order, hidden: hidden)
                        dismiss()
                    }
                }
            }
            .onAppear {
                order = library.orderedLiveGroups
                hidden = library.hiddenLiveGroups
                var result: [String: Int] = [:]
                for item in library.catalog.live { result[item.group, default: 0] += 1 }
                counts = result
            }
        }
    }
}
