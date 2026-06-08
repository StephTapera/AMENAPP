// AmenAudienceFirstPickerView.swift
// AMENAPP
//
// Audience-First Composer Gate — shown BEFORE the compose sheet opens.
// The user declares "Who is this for?" so distribution intent is set from
// the very first keystroke rather than as an afterthought inside the editor.
//
// Space flow: tapping "Space" does NOT immediately dismiss; it slides into a
// sub-picker listing the user's joined Spaces fetched from Firestore.
// Selecting a Space records spaceId + spaceName in AmenAudienceMetadata and
// THEN calls the callback.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - AmenPostAudience

/// Who the author intends to reach. Chosen before opening the compose editor.
enum AmenPostAudience: String, CaseIterable, Identifiable {
    case privateJournal = "private_journal"
    case family         = "family"
    case friends        = "friends"
    case church         = "church"
    case space          = "space"
    case everyone       = "everyone"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .privateJournal: return "Private Journal"
        case .family:         return "Family"
        case .friends:        return "Friends"
        case .church:         return "Church"
        case .space:          return "Space"
        case .everyone:       return "Everyone"
        }
    }

    var subtitle: String {
        switch self {
        case .privateJournal: return "Only you can see this"
        case .family:         return "Your family circle"
        case .friends:        return "People you follow"
        case .church:         return "Your church community"
        case .space:          return "Choose a specific Space"
        case .everyone:       return "Public \u{00B7} Anyone on AMEN"
        }
    }

    var icon: String {
        switch self {
        case .privateJournal: return "lock.fill"
        case .family:         return "figure.2.and.child.holdinghands"
        case .friends:        return "person.2.fill"
        case .church:         return "building.columns.fill"
        case .space:          return "building.2.fill"
        case .everyone:       return "globe"
        }
    }

    /// Maps the audience choice to the closest `CreatePostView.PostCategory` hint.
    var suggestedPostCategory: CreatePostView.PostCategory? {
        switch self {
        case .privateJournal: return nil
        case .family:         return nil
        case .friends:        return nil
        case .church:         return .openTable
        case .space:          return .openTable
        case .everyone:       return .openTable
        }
    }
}

// MARK: - AmenAudienceMetadata

/// Extra context attached to an audience selection, populated for cases
/// where a sub-selection is needed (e.g. which specific Space).
struct AmenAudienceMetadata {
    var spaceId: String?
    var spaceName: String?
    var spaceType: String?
}

// MARK: - AmenSpaceListItem

struct AmenSpaceListItem: Identifiable {
    let id: String
    let name: String
    let spaceType: String
    let memberCount: Int
}

// MARK: - AmenAudienceFirstPickerView

/// A compact `.medium` bottom sheet presented BEFORE the compose editor.
/// Tapping a non-Space row closes this sheet and immediately opens the compose
/// flow with the chosen audience pre-selected.
/// Tapping "Space" transitions into an inline Space picker.
struct AmenAudienceFirstPickerView: View {

    @Binding var isPresented: Bool
    /// Called once with the final audience + any extra metadata.
    let onAudienceSelected: (AmenPostAudience, AmenAudienceMetadata?) -> Void

    @State private var rowsVisible = false
    @State private var showSpacePicker = false

    var body: some View {
        ZStack {
            if showSpacePicker {
                AmenSpacePickerSheet(
                    isPresented: $isPresented,
                    onSpaceSelected: { item in
                        let meta = AmenAudienceMetadata(
                            spaceId: item.id,
                            spaceName: item.name,
                            spaceType: item.spaceType
                        )
                        commit(audience: .space, metadata: meta)
                    },
                    onBack: {
                        withAnimation(.amenSpringStandard) {
                            showSpacePicker = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                audienceList
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.amenSpringStandard, value: showSpacePicker)
        .onAppear {
            withAnimation(.amenSpringEntry) { rowsVisible = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Audience list page

    private var audienceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Who is this for?")
                    .font(AMENFont.bold(22))
                    .foregroundStyle(.primary)
                Text("You can always change this while writing.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(AmenPostAudience.allCases.enumerated()), id: \.element.id) { index, audience in
                    AudienceOptionRow(
                        audience: audience,
                        isVisible: rowsVisible,
                        delay: Double(index) * 0.045,
                        trailingIcon: audience == .space ? "chevron.right" : "chevron.right"
                    ) {
                        handleTap(audience)
                    }
                    if index < AmenPostAudience.allCases.count - 1 {
                        Divider().padding(.leading, 60).opacity(0.25)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.6)
                    )
            )
            .padding(.horizontal, 16)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Tap handler

    @MainActor
    private func handleTap(_ audience: AmenPostAudience) {
        HapticManager.impact(style: .light)
        if audience == .space {
            withAnimation(.amenSpringStandard) { showSpacePicker = true }
        } else {
            commit(audience: audience, metadata: nil)
        }
    }

    @MainActor
    private func commit(audience: AmenPostAudience, metadata: AmenAudienceMetadata?) {
        withAnimation(.amenSpringStandard) { isPresented = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            onAudienceSelected(audience, metadata)
        }
    }
}

// MARK: - AmenSpacePickerSheet

/// Fetches the current user's joined Spaces from Firestore and presents
/// them as a tappable list. Back button returns to the audience list.
private struct AmenSpacePickerSheet: View {

    @Binding var isPresented: Bool
    let onSpaceSelected: (AmenSpaceListItem) -> Void
    let onBack: () -> Void

    @State private var spaces: [AmenSpaceListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with back button
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Back")
                .accessibilityHint("Return to audience selection")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose a Space")
                        .font(AMENFont.bold(20))
                        .foregroundStyle(.primary)
                    Text("Your post will be shared to this Space.")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Content
            if isLoading {
                spaceLoadingView
            } else if let error = errorMessage {
                spaceErrorView(error)
            } else if spaces.isEmpty {
                spaceEmptyView
            } else {
                spaceListView
            }

            Spacer(minLength: 20)
        }
        .task { await fetchJoinedSpaces() }
    }

    // MARK: States

    private var spaceLoadingView: some View {
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 60)
                    .shimmering()
            }
        }
        .padding(.horizontal, 16)
    }

    private func spaceErrorView(_ msg: String) -> some View {
        Text(msg)
            .font(AMENFont.regular(14))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
    }

    private var spaceEmptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.2")
                .font(.systemScaled(36))
                .foregroundStyle(.tertiary)
            Text("You haven't joined any Spaces yet.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 32)
    }

    private var spaceListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                    Button {
                        HapticManager.impact(style: .light)
                        onSpaceSelected(space)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: iconFor(spaceType: space.spaceType))
                                .font(.systemScaled(18, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(space.name)
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.primary)
                                Text(displayType(space.spaceType))
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle")
                                .font(.systemScaled(18))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(space.name)
                    .accessibilityHint("Post to \(space.name)")

                    if index < spaces.count - 1 {
                        Divider().padding(.leading, 60).opacity(0.25)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.6)
                    )
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: Firestore fetch

    private func fetchJoinedSpaces() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            errorMessage = "Sign in to see your Spaces."
            return
        }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("spaces")
                .whereField("memberIds", arrayContains: uid)
                .order(by: "name")
                .limit(to: 50)
                .getDocuments()

            spaces = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard let name = data["name"] as? String else { return nil }
                return AmenSpaceListItem(
                    id: doc.documentID,
                    name: name,
                    spaceType: data["spaceType"] as? String ?? "organization",
                    memberCount: data["memberCount"] as? Int ?? 0
                )
            }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Couldn't load your Spaces. Please try again."
        }
    }

    // MARK: Helpers

    private func iconFor(spaceType: String) -> String {
        switch spaceType {
        case "church":          return "building.columns"
        case "bibleStudy":      return "text.book.closed.fill"
        case "smallGroup":      return "person.3.fill"
        case "familyGroup":     return "house.fill"
        case "friendGroup":     return "person.2.fill"
        case "podcast":         return "mic.fill"
        case "bookClub":        return "book.closed.fill"
        case "worshipTeam":     return "music.note.list"
        case "volunteerTeam":   return "hands.sparkles.fill"
        case "youthMinistry":   return "figure.play"
        default:                return "building.2.fill"
        }
    }

    private func displayType(_ raw: String) -> String {
        // Convert camelCase rawValue to readable label
        switch raw {
        case "church":          return "Church"
        case "campusMinistry":  return "Campus Ministry"
        case "bibleStudy":      return "Bible Study"
        case "smallGroup":      return "Small Group"
        case "familyGroup":     return "Family Group"
        case "friendGroup":     return "Friend Group"
        case "podcast":         return "Podcast"
        case "bookClub":        return "Book Club"
        case "worshipTeam":     return "Worship Team"
        case "volunteerTeam":   return "Volunteer Team"
        case "youthMinistry":   return "Youth Ministry"
        case "mentor":          return "Mentor"
        case "nonprofit":       return "Nonprofit"
        case "organization":    return "Organization"
        case "missionTeam":     return "Mission Team"
        case "businessTeam":    return "Business Team"
        default:                return raw
        }
    }
}

// MARK: - AudienceOptionRow

private struct AudienceOptionRow: View {
    let audience: AmenPostAudience
    let isVisible: Bool
    let delay: Double
    let trailingIcon: String
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: audience.icon)
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(audience.displayName)
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                    Text(audience.subtitle)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: trailingIcon)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isPressed ? Color.primary.opacity(0.06) : Color.clear)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.amenEaseQuick, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .animation(.amenSpringEntry.delay(delay), value: isVisible)
        .accessibilityLabel(audience.displayName)
        .accessibilityHint(audience.subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Shimmer helper (if not already in project)

private extension View {
    @ViewBuilder
    func shimmering() -> some View {
        self.redacted(reason: .placeholder)
    }
}

// MARK: - Preview

#Preview("Audience Picker") {
    @Previewable @State var shown = true
    Color(.systemGroupedBackground)
        .ignoresSafeArea()
        .sheet(isPresented: $shown) {
            AmenAudienceFirstPickerView(isPresented: $shown) { audience, metadata in
                print("Selected: \(audience.displayName), space: \(metadata?.spaceName ?? "none")")
            }
        }
}
