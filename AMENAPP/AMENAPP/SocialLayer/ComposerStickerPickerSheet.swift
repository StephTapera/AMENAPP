// ComposerStickerPickerSheet.swift
// AMENAPP — SocialLayer
//
// INTEGRATION NOTE (Phase 4 — CreatePostView wiring):
// ─────────────────────────────────────────────────────────────────────────────
// 1. Add a `@State private var showStickerPicker = false` to CreatePostView.
//
// 2. In the toolbar / attachment row, add a sticker button:
//      Button { showStickerPicker = true } label: {
//          Image(systemName: "face.smiling.fill")
//              .font(.system(size: 22))
//              .foregroundStyle(AmenTheme.Colors.amenGold)
//      }
//      .accessibilityLabel("Add sticker")
//
// 3. Attach the sheet to CreatePostView's body:
//      .sheet(isPresented: $showStickerPicker) {
//          ComposerStickerPickerSheet { attachment in
//              draft.attachments.append(.sticker(attachment))
//              showStickerPicker = false
//          }
//      }
//
// 4. In the attachment strip / post-submit pipeline, handle
//    ComposerAttachmentKind.sticker via the existing attachment routing
//    (stickerId + packId are already fields on ComposerStickerAttachment).
//
// 5. No changes to CreatePostView's form, validation, or submit logic are
//    required — the sticker is just another ComposerAttachment.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - Category enum

private enum StickerCategory: String, CaseIterable {
    case recent   = "Recent"
    case faith    = "Faith"
    case animated = "Animated"
}

// MARK: - StickerRecentsStore

/// Persists last-10 used stickers to UserDefaults, keyed "stickerRecents".
private final class StickerRecentsStore: ObservableObject {
    private static let key = "stickerRecents"
    private static let maxCount = 10

    @Published private(set) var recents: [ComposerStickerAttachment] = []

    init() {
        load()
    }

    func add(_ attachment: ComposerStickerAttachment) {
        var updated = recents.filter { $0.stickerId != attachment.stickerId }
        updated.insert(attachment, at: 0)
        if updated.count > Self.maxCount {
            updated = Array(updated.prefix(Self.maxCount))
        }
        recents = updated
        save(updated)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([ComposerStickerAttachment].self, from: data)
        else { return }
        recents = decoded
    }

    private func save(_ attachments: [ComposerStickerAttachment]) {
        guard let data = try? JSONEncoder().encode(attachments) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

// MARK: - ComposerStickerPickerSheet

struct ComposerStickerPickerSheet: View {
    let onSelect: (ComposerStickerAttachment) -> Void

    // MARK: State

    @State private var searchText = ""
    @State private var selectedCategory: StickerCategory = .faith
    @StateObject private var recentsStore = StickerRecentsStore()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Derived data

    private var filteredFaithStickers: [AmenFaithSticker] {
        guard !searchText.isEmpty else { return AmenFaithStickerPack.stickers }
        return AmenFaithStickerPack.stickers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredRecentAttachments: [ComposerStickerAttachment] {
        guard !searchText.isEmpty else { return recentsStore.recents }
        return recentsStore.recents.filter {
            // Match against the Faith sticker name when the packId is known
            if $0.packId == "amen-faith-v1",
               let sticker = AmenFaithStickerPack.stickers.first(where: { s in s.id == $0.stickerId }) {
                return sticker.name.localizedCaseInsensitiveContains(searchText)
            }
            return $0.stickerId.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Grid

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                categoryChips
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                Divider()
                    .foregroundStyle(AmenTheme.Colors.separatorSubtle)

                stickerContent
            }
            .background(Color.clear)
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(32)
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            TextField("Search stickers…", text: $searchText)
                .font(AMENFont.medium(15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    withAnimation(Motion.adaptive(Motion.springPress)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .amenGlassInputBar(cornerRadius: 14)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StickerCategory.allCases, id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryChip(_ category: StickerCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.14)
                    : .spring(response: 0.28, dampingFraction: 0.72)
            ) {
                selectedCategory = category
            }
        } label: {
            Text(category.rawValue)
                .font(AMENFont.medium(13))
                .foregroundStyle(isSelected ? Color.white : AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(AmenTheme.Colors.amenGold)
                    } else {
                        Capsule(style: .continuous)
                            .fill(AmenTheme.Colors.surfaceChip)
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? AmenTheme.Colors.amenGold.opacity(0.5)
                                : AmenTheme.Colors.borderSoft,
                            lineWidth: 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : Motion.springPress,
            value: isSelected
        )
        .accessibilityLabel(category.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var stickerContent: some View {
        switch selectedCategory {
        case .recent:
            recentGrid
        case .faith:
            faithGrid
        case .animated:
            animatedPlaceholder
        }
    }

    // MARK: Recent grid

    private var recentGrid: some View {
        Group {
            if filteredRecentAttachments.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    title: searchText.isEmpty ? "No recent stickers" : "No results",
                    subtitle: searchText.isEmpty
                        ? "Your recently used stickers will appear here"
                        : "Try a different search term"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredRecentAttachments) { attachment in
                            recentCell(attachment)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .transition(
            reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .leading)),
                removal: .opacity
            )
        )
    }

    private func recentCell(_ attachment: ComposerStickerAttachment) -> some View {
        // Resolve to an AmenFaithSticker for rendering if possible
        let faithSticker = attachment.packId == "amen-faith-v1"
            ? AmenFaithStickerPack.stickers.first(where: { $0.id == attachment.stickerId })
            : nil

        return Button {
            handleSelect(attachment: attachment, stickerName: faithSticker?.name ?? attachment.stickerId)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
                    .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, y: 2)

                if let sticker = faithSticker {
                    sticker.stickerView
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 36))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                }
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(AmenPressStyle(scale: 0.93))
        .accessibilityLabel(faithSticker?.name ?? attachment.stickerId)
        .accessibilityHint("Double-tap to add sticker")
    }

    // MARK: Faith grid

    private var faithGrid: some View {
        Group {
            if filteredFaithStickers.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: "No results",
                    subtitle: "Try searching for cross, dove, fire, or bible"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredFaithStickers) { sticker in
                            faithCell(sticker)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .transition(
            reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity
            )
        )
    }

    private func faithCell(_ sticker: AmenFaithSticker) -> some View {
        Button {
            handleSelect(
                attachment: sticker.attachment(),
                stickerName: sticker.name
            )
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceCard)
                    .shadow(color: AmenTheme.Colors.shadowCard, radius: 6, y: 2)

                sticker.stickerView
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(AmenPressStyle(scale: 0.93))
        .accessibilityLabel(sticker.name)
        .accessibilityHint("Double-tap to add sticker")
    }

    // MARK: Animated placeholder

    private var animatedPlaceholder: some View {
        emptyState(
            icon: "sparkles",
            title: "Animated Stickers",
            subtitle: "Giphy stickers are coming soon — stay tuned!"
        )
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Empty state

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.7))

            Text(title)
                .font(AMENFont.semiBold(16))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Text(subtitle)
                .font(AMENFont.regular(13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Selection handler

    private func handleSelect(attachment: ComposerStickerAttachment, stickerName: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        recentsStore.add(attachment)
        withAnimation(Motion.adaptive(Motion.popToggle)) {
            onSelect(attachment)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Sticker Picker") {
    Color.black.opacity(0.4)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ComposerStickerPickerSheet { attachment in
                print("Selected sticker: \(attachment.stickerId)")
            }
        }
}
#endif
