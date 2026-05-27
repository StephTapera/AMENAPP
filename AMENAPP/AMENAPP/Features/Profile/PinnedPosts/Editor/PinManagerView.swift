// PinManagerView.swift
// AMENAPP — Profile Header v2
//
// Sheet for managing the 3 pin slots.
// Supports drag-to-reorder, swipe-to-unpin, and displays pin age per item.
// Calls store.reorder() on move, store.unpinPost() on delete.

import SwiftUI

// MARK: - PinManagerView

public struct PinManagerView: View {

    // MARK: - Dependencies

    @Bindable public var store: PinnedPostsStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local state

    @State private var errorMessage: String?
    @State private var showError = false

    // MARK: - Init

    public init(store: PinnedPostsStore) {
        self.store = store
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pinned Posts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .alert("Something went wrong", isPresented: $showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if let errorMessage {
                        Text(errorMessage)
                    }
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.pinnedPreviews.isEmpty && !store.isLoading {
            emptyState
        } else {
            List {
                ForEach(store.pinnedPreviews) { preview in
                    PinManagerRow(preview: preview)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .onMove { source, destination in
                    Task { await handleMove(from: source, to: destination) }
                }
                .onDelete { offsets in
                    Task { await handleDelete(at: offsets) }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .overlay(alignment: .bottom) {
                if store.isLoading {
                    loadingBanner
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pin.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Pinned Posts")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Pin up to 3 posts to feature them at the top of your profile.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading banner

    private var loadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            Text("Updating pins…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .padding(.bottom, 16)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .fontWeight(.semibold)
        }
    }

    // MARK: - Actions

    private func handleMove(from source: IndexSet, to destination: Int) async {
        var updated = store.pinnedPreviews
        updated.move(fromOffsets: source, toOffset: destination)
        let newOrder = updated.map(\.id)

        do {
            try await store.reorder(newOrder)
        } catch {
            showError(error)
        }
    }

    private func handleDelete(at offsets: IndexSet) async {
        let toDelete = offsets.compactMap { store.pinnedPreviews[safe: $0] }
        for preview in toDelete {
            do {
                try await store.unpinPost(preview.id)
            } catch {
                showError(error)
                break
            }
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - PinManagerRow

private struct PinManagerRow: View {

    let preview: PinnedPostPreview
    private let amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)

    var body: some View {
        HStack(spacing: 12) {
            // Pin icon accent
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(amenGold.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "pin.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(amenGold)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.content)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    // Type badge
                    Text(typeBadgeLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(amenGold.opacity(0.78)))

                    // Pin age
                    if let age = pinAgeText {
                        Text(age)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Helpers

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.56))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
            )
    }

    private var typeBadgeLabel: String {
        switch preview.type.lowercased() {
        case "prayer":                 return "Prayer"
        case "testimonies",
             "testimony":             return "Testimony"
        case "verse":                  return "Verse"
        case "opentable":             return "Reflection"
        default:                       return "Post"
        }
    }

    private var pinAgeText: String? {
        guard let pinnedAt = preview.pinnedAt else { return nil }
        return "Pinned \(relativeTimeString(from: pinnedAt))"
    }

    private var accessibilityLabel: String {
        let age = pinAgeText ?? ""
        return "\(typeBadgeLabel): \(preview.content.prefix(60)). \(age)"
    }

    // MARK: - Relative time

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    // Build a detached store with stubbed data for preview rendering
    let store = PinnedPostsStore(userId: "preview-uid")

    return PinManagerView(store: store)
}
#endif
