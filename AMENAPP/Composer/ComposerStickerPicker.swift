// ComposerStickerPicker.swift
// AMENAPP — Composer module: faith-first sticker picker sheet.
//
// Responsibilities:
//   • ComposerStickerProvider  — ObservableObject + ComposerAttachmentProvider
//     Firestore recents (users/{uid}/stickerRecents), limit 20.
//   • StickerPack / StickerItem — local model (no re-declaration of contract types).
//   • ComposerStickerPickerView — .sheet with search, recents rail, pack grid.
//   • StickerFaithCell          — glass ZStack cell for built-in SF Symbol stickers.
//
// Design tokens:  AmenTheme.Colors.*, Motion.adaptive(), .amenGlassCard(),
//                 .amenGlassInputBar(), .amenPress()
// Never re-declares ComposerStickerAttachment or ComposerAttachment (ComposerContract.swift).

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - ComposerStickerProvider

@MainActor
final class ComposerStickerProvider: ObservableObject, ComposerAttachmentProvider {

    // MARK: ComposerAttachmentProvider
    @Published var pendingAttachment: ComposerAttachment?

    // MARK: Recents
    @Published var recentStickers: [ComposerStickerAttachment] = []

    private let db = Firestore.firestore()
    private var currentUID: String? { Auth.auth().currentUser?.uid }

    // MARK: - ComposerAttachmentProvider reset
    func reset() {
        pendingAttachment = nil
    }

    // MARK: - Recents: save

    /// Writes the sticker to Firestore users/{uid}/stickerRecents/{stickerId},
    /// capping the collection at 20 entries (oldest dropped client-side via in-memory sort).
    func saveRecent(_ sticker: ComposerStickerAttachment) {
        guard let uid = currentUID else { return }

        // Update local recents immediately (optimistic).
        var updated = recentStickers.filter { $0.stickerId != sticker.stickerId }
        updated.insert(sticker, at: 0)
        if updated.count > 20 { updated = Array(updated.prefix(20)) }
        recentStickers = updated

        // Persist to Firestore.
        let docRef = db
            .collection("users").document(uid)
            .collection("stickerRecents").document(sticker.stickerId)

        let payload: [String: Any] = [
            "stickerId": sticker.stickerId,
            "url":       sticker.url,
            "category":  sticker.category,
            "packId":    sticker.packId,
            "savedAt":   FieldValue.serverTimestamp()
        ]
        docRef.setData(payload, merge: true) { error in
            if let error {
                print("[StickerProvider] saveRecent error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recents: load

    /// Reads Firestore users/{uid}/stickerRecents ordered by savedAt desc, limit 20.
    func loadRecents() async {
        guard let uid = currentUID else { return }
        do {
            let snapshot = try await db
                .collection("users").document(uid)
                .collection("stickerRecents")
                .order(by: "savedAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            let stickers: [ComposerStickerAttachment] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard
                    let stickerId = data["stickerId"] as? String,
                    let url       = data["url"]       as? String,
                    let category  = data["category"]  as? String,
                    let packId    = data["packId"]     as? String
                else { return nil }
                var att = ComposerStickerAttachment()
                att.stickerId = stickerId
                att.url       = url
                att.category  = category
                att.packId    = packId
                return att
            }
            recentStickers = stickers
        } catch {
            print("[StickerProvider] loadRecents error: \(error.localizedDescription)")
        }
    }
}

// MARK: - StickerPack / StickerItem models

struct StickerPack: Identifiable {
    var id: String
    var name: String
    var stickers: [StickerItem]
}

struct StickerItem: Identifiable {
    var id: String
    var packId: String
    var url: String           // Remote image URL (empty for built-in packs)
    var localAsset: String?   // SF Symbol name or local asset name
    var displayName: String   // Human-readable for accessibility
}

// MARK: - Built-in Faith Pack

private enum AmenFaithPack {
    static let pack = StickerPack(
        id: "amen_faith",
        name: "Faith",
        stickers: [
            StickerItem(id: "cross",           packId: "amen_faith", url: "", localAsset: "cross.fill",               displayName: "Cross"),
            StickerItem(id: "dove",            packId: "amen_faith", url: "", localAsset: "bird.fill",                displayName: "Dove"),
            StickerItem(id: "praying_hands",   packId: "amen_faith", url: "", localAsset: "hands.sparkles.fill",      displayName: "Praying Hands"),
            StickerItem(id: "verse_badge_jn3", packId: "amen_faith", url: "", localAsset: nil,                        displayName: "John 3:16"),
            StickerItem(id: "verse_badge_ps23",packId: "amen_faith", url: "", localAsset: nil,                        displayName: "Psalm 23"),
            StickerItem(id: "heart_fire",      packId: "amen_faith", url: "", localAsset: "heart.fill",               displayName: "Heart Fire"),
            StickerItem(id: "bible",           packId: "amen_faith", url: "", localAsset: "book.closed.fill",         displayName: "Bible"),
            StickerItem(id: "church",          packId: "amen_faith", url: "", localAsset: "building.columns.fill",    displayName: "Church"),
        ]
    )
}

// MARK: - StickerFaithCell

/// 52×52 glass cell rendering an SF Symbol sticker or a verse badge.
struct StickerFaithCell: View {
    let item: StickerItem
    let isRecent: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    private var cellSize: CGFloat { isRecent ? 48 : 52 }

    var body: some View {
        ZStack {
            // Glass background
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.75)
                )

            // Content
            Group {
                if let symbol = item.localAsset {
                    Image(systemName: symbol)
                        .resizable()
                        .scaledToFit()
                        .padding(11)
                        .foregroundStyle(
                            item.id == "heart_fire"
                                ? AmenTheme.Colors.amenGold
                                : AmenTheme.Colors.amenGold
                        )
                } else {
                    // Verse badge: "John 3:16" / "Psalm 23"
                    VStack(spacing: 1) {
                        Text(verseBadgeText(for: item.id))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                            .lineLimit(2)
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: cellSize, height: cellSize)
        .accessibilityLabel(item.displayName + " sticker")
        .accessibilityAddTraits(.isButton)
    }

    private func verseBadgeText(for id: String) -> String {
        switch id {
        case "verse_badge_jn3":  return "John\n3:16"
        case "verse_badge_ps23": return "Ps\n23"
        default:                 return id
        }
    }
}

// MARK: - ComposerStickerPickerView

struct ComposerStickerPickerView: View {
    @ObservedObject var provider: ComposerStickerProvider
    @Binding var isPresented: Bool

    @State private var searchText: String = ""
    @State private var expandedPackIds: Set<String> = ["amen_faith"]
    @State private var selectedItemId: String? = nil
    @FocusState private var searchFocused: Bool

    // Built-in packs — Faith always first, placeholder licensed packs at end.
    private var allPacks: [StickerPack] {
        var packs: [StickerPack] = [AmenFaithPack.pack]
        // Emoji placeholder pack (SF symbols as stand-ins for Unicode emoji stickers).
        packs.append(StickerPack(
            id: "emoji",
            name: "Emoji",
            stickers: [
                StickerItem(id: "emoji_fire",   packId: "emoji", url: "", localAsset: "flame.fill",           displayName: "Fire"),
                StickerItem(id: "emoji_star",   packId: "emoji", url: "", localAsset: "star.fill",            displayName: "Star"),
                StickerItem(id: "emoji_sun",    packId: "emoji", url: "", localAsset: "sun.max.fill",         displayName: "Sun"),
                StickerItem(id: "emoji_moon",   packId: "emoji", url: "", localAsset: "moon.fill",            displayName: "Moon"),
                StickerItem(id: "emoji_rose",   packId: "emoji", url: "", localAsset: "leaf.fill",            displayName: "Leaf"),
                StickerItem(id: "emoji_sparkle",packId: "emoji", url: "", localAsset: "sparkles",             displayName: "Sparkles"),
                StickerItem(id: "emoji_music",  packId: "emoji", url: "", localAsset: "music.note",           displayName: "Music Note"),
                StickerItem(id: "emoji_bell",   packId: "emoji", url: "", localAsset: "bell.fill",            displayName: "Bell"),
                StickerItem(id: "emoji_globe",  packId: "emoji", url: "", localAsset: "globe",                displayName: "Globe"),
                StickerItem(id: "emoji_heart2", packId: "emoji", url: "", localAsset: "heart.circle.fill",    displayName: "Heart Circle"),
            ]
        ))
        // Placeholder licensed pack (not yet available).
        packs.append(StickerPack(
            id: "licensed_coming_soon",
            name: "More Packs Coming Soon",
            stickers: []
        ))
        return packs
    }

    private var filteredPacks: [StickerPack] {
        guard !searchText.isEmpty else { return allPacks }
        let query = searchText.lowercased()
        return allPacks.compactMap { pack in
            let filtered = pack.stickers.filter {
                $0.displayName.lowercased().contains(query) ||
                $0.id.lowercased().contains(query)
            }
            guard !filtered.isEmpty else { return nil }
            return StickerPack(id: pack.id, name: pack.name, stickers: filtered)
        }
    }

    private var filteredRecents: [ComposerStickerAttachment] {
        guard !searchText.isEmpty else { return provider.recentStickers }
        let query = searchText.lowercased()
        return provider.recentStickers.filter {
            $0.stickerId.lowercased().contains(query) ||
            $0.category.lowercased().contains(query)
        }
    }

    // 5-column grid
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            ZStack {
                // Sheet background
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Search bar ──────────────────────────────────────
                        searchBar

                        // ── Recents rail ────────────────────────────────────
                        if !filteredRecents.isEmpty {
                            recentsSection
                        }

                        // ── Pack sections ───────────────────────────────────
                        ForEach(filteredPacks) { pack in
                            packSection(pack)
                        }

                        // Bottom safe area buffer
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        searchFocused = false
                        isPresented = false
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await provider.loadRecents() }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .font(.system(size: 15, weight: .medium))
            TextField("Search stickers…", text: $searchText)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    withAnimation(Motion.adaptive(Motion.springRelease)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .amenGlassInputBar(cornerRadius: 16)
        .accessibilityLabel("Search stickers")
    }

    // MARK: - Recents Section

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recents")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(filteredRecents) { sticker in
                        recentCell(sticker)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private func recentCell(_ sticker: ComposerStickerAttachment) -> some View {
        // Resolve the matching StickerItem from all packs for proper rendering.
        let item = resolvedItem(for: sticker)
        Button {
            select(sticker: sticker)
        } label: {
            StickerFaithCell(item: item, isRecent: true)
        }
        .buttonStyle(.plain)
        .amenPress(scale: 0.90)
        .scaleEffect(selectedItemId == sticker.stickerId ? 1.18 : 1.0)
        .animation(Motion.adaptive(Motion.springPress), value: selectedItemId)
    }

    // MARK: - Pack Section

    @ViewBuilder
    private func packSection(_ pack: StickerPack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header — tappable to collapse/expand
            Button {
                withAnimation(Motion.adaptive(Motion.springRelease)) {
                    if expandedPackIds.contains(pack.id) {
                        expandedPackIds.remove(pack.id)
                    } else {
                        expandedPackIds.insert(pack.id)
                    }
                }
            } label: {
                HStack {
                    sectionHeader(pack.name)
                    Spacer()
                    if !pack.stickers.isEmpty {
                        Image(systemName: expandedPackIds.contains(pack.id)
                              ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pack.name + " pack, " + (expandedPackIds.contains(pack.id) ? "expanded" : "collapsed"))
            .accessibilityAddTraits(.isButton)

            if pack.stickers.isEmpty {
                // Coming-soon placeholder
                Text("More packs will be available soon.")
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .padding(.vertical, 8)
            } else if expandedPackIds.contains(pack.id) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(pack.stickers) { item in
                        Button {
                            let attachment = ComposerStickerAttachment(
                                id: UUID(),
                                stickerId: item.id,
                                url: item.url,
                                category: pack.name,
                                packId: pack.id
                            )
                            select(sticker: attachment)
                        } label: {
                            StickerFaithCell(item: item, isRecent: false)
                        }
                        .buttonStyle(.plain)
                        .amenPress(scale: 0.88)
                        .scaleEffect(selectedItemId == item.id ? 1.18 : 1.0)
                        .animation(Motion.adaptive(Motion.springPress), value: selectedItemId)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.4)
    }

    // MARK: - Selection handler

    private func select(sticker: ComposerStickerAttachment) {
        // 1. Haptic
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // 2. Pop animation
        withAnimation(Motion.adaptive(Motion.popToggle)) {
            selectedItemId = sticker.stickerId
        }

        // 3. Save recent + set pending attachment
        provider.saveRecent(sticker)
        provider.pendingAttachment = .sticker(sticker)

        // 4. Dismiss after spring settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(Motion.adaptive(Motion.springRelease)) {
                isPresented = false
            }
        }
    }

    // MARK: - Helpers

    /// Resolves a matching StickerItem from allPacks for a ComposerStickerAttachment.
    /// Falls back to a generic item if no match found.
    private func resolvedItem(for sticker: ComposerStickerAttachment) -> StickerItem {
        for pack in allPacks {
            if let found = pack.stickers.first(where: { $0.id == sticker.stickerId }) {
                return found
            }
        }
        // Generic fallback for stickers from unlisted/licensed packs.
        return StickerItem(
            id: sticker.stickerId,
            packId: sticker.packId,
            url: sticker.url,
            localAsset: "photo.fill",
            displayName: sticker.category.isEmpty ? "Sticker" : sticker.category
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Sticker Picker") {
    @Previewable @StateObject var provider = ComposerStickerProvider()
    @Previewable @State var shown = true

    Color.gray.opacity(0.15)
        .ignoresSafeArea()
        .sheet(isPresented: $shown) {
            ComposerStickerPickerView(provider: provider, isPresented: $shown)
        }
}
#endif
