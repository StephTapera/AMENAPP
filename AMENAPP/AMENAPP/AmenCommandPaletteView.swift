import SwiftUI

// MARK: - Command Palette Item

struct AmenCommandPaletteItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let category: String
    let keywords: [String]
    var action: () -> Void = {}
}

// MARK: - Command Palette View

struct AmenCommandPaletteView: View {
    @Binding var isPresented: Bool

    var onJumpToThreads: (() -> Void)?
    var onSearchScripture: (() -> Void)?
    var onAskBerean: (() -> Void)?
    var onOpenPrayer: (() -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onOpenGiving: (() -> Void)?

    @State private var query = ""
    @FocusState private var focused: Bool

    private var allItems: [AmenCommandPaletteItem] {[
        AmenCommandPaletteItem(
            icon: "bubble.left.and.bubble.right",
            title: "Jump to Threads",
            category: "Navigate",
            keywords: ["threads", "rooms", "covenant", "chat"],
            action: { onJumpToThreads?() }
        ),
        AmenCommandPaletteItem(
            icon: "book.pages",
            title: "Search Scripture",
            category: "Search",
            keywords: ["bible", "verse", "scripture", "passage", "study"],
            action: { onSearchScripture?() }
        ),
        AmenCommandPaletteItem(
            icon: "brain.head.profile",
            title: "Ask Berean",
            category: "AI",
            keywords: ["berean", "ai", "ask", "study", "counsel"],
            action: { onAskBerean?() }
        ),
        AmenCommandPaletteItem(
            icon: "hands.sparkles",
            title: "Prayer Requests",
            category: "Navigate",
            keywords: ["prayer", "pray", "request", "intercede"],
            action: { onOpenPrayer?() }
        ),
        AmenCommandPaletteItem(
            icon: "books.vertical",
            title: "Open Library",
            category: "Navigate",
            keywords: ["library", "book", "read", "resource"],
            action: { onOpenLibrary?() }
        ),
        AmenCommandPaletteItem(
            icon: "heart",
            title: "Giving",
            category: "Navigate",
            keywords: ["give", "tithe", "offering", "donate", "stewardship"],
            action: { onOpenGiving?() }
        ),
    ]}

    private var results: [AmenCommandPaletteItem] {
        guard !query.isEmpty else { return allItems }
        let lower = query.lowercased()
        return allItems.filter { item in
            item.title.lowercased().contains(lower) ||
            item.category.lowercased().contains(lower) ||
            item.keywords.contains { $0.contains(lower) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.25)
            resultsList
        }
        .onAppear { focused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Jump to…", text: $query)
                .focused($focused)
                .autocorrectionDisabled()
                .accessibilityLabel("Search commands")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var resultsList: some View {
        Group {
            if results.isEmpty {
                Text("Nothing found")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(32)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(results) { item in
                            Button {
                                isPresented = false
                                // Brief delay so the sheet has time to dismiss before routing
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    item.action()
                                }
                            } label: {
                                commandRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func commandRow(_ item: AmenCommandPaletteItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .font(.body)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(item.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.left")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityLabel("\(item.title), \(item.category)")
    }
}
