// CollectionPickerSheet.swift
// AMENAPP — Media/Save
//
// Pull-up sheet for saving a media item to a named MediaCollection.
// Uses .glassSheet(isPresented:detent:.medium) per GlassSheet.swift contract.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - CollectionPickerSheet

@MainActor
struct CollectionPickerSheet: View {
    @Binding var isPresented: Bool
    var mediaId: String
    var onSaved: (MediaCollection?) -> Void

    // MARK: State

    @State private var collections: [MediaCollection] = []
    @State private var isLoading = true
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""
    @State private var newCollectionIcon = "folder.fill"
    @State private var isSaving = false
    @State private var errorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Grid layout

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    // SF Symbol options for new collection picker (subset)
    private let symbolOptions = [
        "folder.fill", "heart.fill", "bookmark.fill", "star.fill",
        "book.fill", "cross.fill", "music.note", "video.fill",
        "camera.fill", "mic.fill", "graduationcap.fill", "church"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Save to root (no collection)
                    rootSaveButton

                    // Existing collections grid
                    if isLoading {
                        loadingSkeleton
                    } else if collections.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(collections) { collection in
                                CollectionCard(collection: collection) {
                                    save(to: collection)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // New collection inline creator
                    newCollectionSection

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Save to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .foregroundStyle(Color.amenGold)
                }
            }
        }
        .task { await loadCollections() }
    }

    // MARK: Subviews

    private var rootSaveButton: some View {
        Button {
            save(to: nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill")
                    .font(.title3)
                    .foregroundStyle(Color.amenGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("Quick save without a collection")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(14)
            .background { cardBackground(cornerRadius: LiquidGlassTokens.cornerRadiusMedium) }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityLabel("Save to quick saves without a collection")
    }

    private var loadingSkeleton: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                AmenGlassLoadingSkeleton(
                    cornerRadius: LiquidGlassTokens.cornerRadiusMedium,
                    height: 90
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Color.amenGold.opacity(0.7))
            Text("No collections yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Create your first collection below")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var newCollectionSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.82)) {
                    showingNewCollection.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: showingNewCollection ? "minus.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.amenGold)
                    Text(showingNewCollection ? "Cancel" : "New Collection")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Spacer()
                }
                .padding(14)
                .background { cardBackground(cornerRadius: LiquidGlassTokens.cornerRadiusMedium) }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityLabel(showingNewCollection ? "Cancel new collection" : "Create new collection")

            if showingNewCollection {
                newCollectionForm
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var newCollectionForm: some View {
        VStack(spacing: 12) {
            TextField("Collection name", text: $newCollectionName)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(12)
                .background { cardBackground(cornerRadius: LiquidGlassTokens.cornerRadiusSmall) }
                .padding(.horizontal, 16)
                .accessibilityLabel("Collection name")

            // SF Symbol picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(symbolOptions, id: \.self) { symbol in
                        symbolPickerButton(symbol: symbol)
                    }
                }
                .padding(.horizontal, 16)
            }

            Button {
                Task { await createAndSave() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(Color.amenGold)
                    } else {
                        Image(systemName: "folder.badge.plus")
                        Text("Create & Save")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background { cardBackground(cornerRadius: LiquidGlassTokens.cornerRadiusMedium) }
            }
            .buttonStyle(.plain)
            .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            .padding(.horizontal, 16)
            .accessibilityLabel("Create collection and save item")
        }
    }

    // MARK: Helpers

    /// Extracted to avoid type-checker complexity in the ForEach body.
    @ViewBuilder
    private func symbolPickerButton(symbol: String) -> some View {
        let isSelected = newCollectionIcon == symbol
        let unselectedStyle: AnyShapeStyle = reduceTransparency
            ? AnyShapeStyle(Color(.systemFill))
            : AnyShapeStyle(LiquidGlassTokens.blurThin)
        let bgStyle: AnyShapeStyle = isSelected
            ? AnyShapeStyle(Color.amenGold.opacity(0.15))
            : unselectedStyle
        Button {
            newCollectionIcon = symbol
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isSelected ? Color.amenGold : AmenTheme.Colors.textSecondary)
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall, style: .continuous)
                        .fill(bgStyle)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(symbol) as icon")
    }

    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.7)
                }
        }
    }

    // MARK: Actions

    private func save(to collection: MediaCollection?) {
        isSaving = true
        onSaved(collection)
        isPresented = false
    }

    private func createAndSave() async {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        isSaving = true
        errorMessage = nil

        do {
            let db = Firestore.firestore()
            let ref = db.collection("collections").document(uid).collection("items").document()
            let newCollection = MediaCollection(
                id: ref.documentID,
                userId: uid,
                name: name,
                icon: newCollectionIcon,
                color: "#F0C96E",
                itemCount: 0,
                createdAt: .now
            )
            try ref.setData(from: newCollection)
            onSaved(newCollection)
            isPresented = false
        } catch {
            errorMessage = "Could not create collection. Please try again."
            isSaving = false
        }
    }

    private func loadCollections() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        do {
            let db = Firestore.firestore()
            let snapshot = try await db
                .collection("collections")
                .document(uid)
                .collection("items")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            collections = try snapshot.documents.compactMap { try $0.data(as: MediaCollection.self) }
        } catch {
            errorMessage = "Could not load collections."
        }
        isLoading = false
    }
}

// MARK: - CollectionCard

private struct CollectionCard: View {
    let collection: MediaCollection
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: collection.icon)
                        .font(.title2)
                        .foregroundStyle(Color(hex: collection.color))
                    Spacer()
                    Text("\(collection.itemCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                Text(collection.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(reduceTransparency
                        ? AnyShapeStyle(Color(.systemBackground))
                        : AnyShapeStyle(LiquidGlassTokens.blurThin))
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(Color(hex: collection.color).opacity(0.40), lineWidth: 1)
                    }
            }
            .shadow(
                color: LiquidGlassTokens.shadowSoft.color,
                radius: LiquidGlassTokens.shadowSoft.radius,
                y: LiquidGlassTokens.shadowSoft.y
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save to \(collection.name), \(collection.itemCount) items")
    }
}
