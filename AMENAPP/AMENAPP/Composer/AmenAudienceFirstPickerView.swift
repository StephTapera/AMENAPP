// AmenAudienceFirstPickerView.swift
// AMENAPP
//
// Audience-First Composer Gate - shown BEFORE the compose sheet opens.
// The user declares "Who is this for?" so distribution intent is set from
// the very first keystroke rather than as an afterthought inside the editor.
//
// Space flow: tapping "Space" opens a nested picker listing the user's joined
// Spaces fetched from Firestore. Selecting a Space records spaceId + spaceName
// in AmenAudienceMetadata, returns to the routing preview, and commits on Continue.

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
        case .privateJournal: return "Only me"
        case .family:         return "Family circle"
        case .friends:        return "Approved friends"
        case .church:         return "Church community"
        case .space:          return "Choose a specific Space"
        case .everyone:       return "Public on AMEN"
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

struct AmenSpaceListItem: Identifiable, Equatable {
    let id: String
    let name: String
    let spaceType: String
    let memberCount: Int
}

// MARK: - Post Destination Model

typealias PostDestinationType = AmenPostAudience

struct PostDestinationOption: Identifiable {
    let id: PostDestinationType
    let title: String
    let subtitle: String
    let icon: String
    let visibilityDescription: String
    let chips: [String]
    let requiresSelection: Bool
    let helperText: String?

    static let all: [PostDestinationOption] = [
        .init(
            id: .privateJournal,
            title: "Private Journal",
            subtitle: "Only me",
            icon: "lock.fill",
            visibilityDescription: "Only you can see this post. It stays out of your profile and feeds.",
            chips: ["Private", "Hidden from profile", "Private by default"],
            requiresSelection: false,
            helperText: "Private Journal is the safest default."
        ),
        .init(
            id: .family,
            title: "Family",
            subtitle: "Family circle",
            icon: "figure.2.and.child.holdinghands",
            visibilityDescription: "Begins with your family circle and keeps the conversation close.",
            chips: ["Semi-private", "Can comment", "Limited sharing"],
            requiresSelection: false,
            helperText: nil
        ),
        .init(
            id: .friends,
            title: "Friends",
            subtitle: "Approved friends",
            icon: "person.2.fill",
            visibilityDescription: "Shared with people you follow or have approved as friends.",
            chips: ["Friends", "Can comment", "Profile optional"],
            requiresSelection: false,
            helperText: nil
        ),
        .init(
            id: .church,
            title: "Church",
            subtitle: "Church community",
            icon: "building.columns.fill",
            visibilityDescription: "Starts in your church community for shared care, prayer, and updates.",
            chips: ["Community", "Can comment", "Church context"],
            requiresSelection: false,
            helperText: nil
        ),
        .init(
            id: .space,
            title: "Space",
            subtitle: "Choose a Space",
            icon: "building.2.fill",
            visibilityDescription: "Routes the post to a specific Space you choose before continuing.",
            chips: ["Requires Space", "Members", "Can comment"],
            requiresSelection: true,
            helperText: "Choose the Space where this post should begin."
        ),
        .init(
            id: .everyone,
            title: "Everyone",
            subtitle: "Public on AMEN",
            icon: "globe",
            visibilityDescription: "Public posts can be discovered across AMEN and may appear on your profile.",
            chips: ["Public", "Can share", "Visible on profile"],
            requiresSelection: false,
            helperText: "Public posts may be visible across AMEN."
        )
    ]

    static func option(for destination: PostDestinationType) -> PostDestinationOption {
        all.first { $0.id == destination } ?? all[0]
    }
}

// MARK: - AmenAudienceFirstPickerView

/// A bottom sheet presented before the compose editor. The user previews the
/// routing choice, then taps Continue to pass the selected audience back to the composer.
struct AmenAudienceFirstPickerView: View {

    @Binding var isPresented: Bool
    /// Called once with the final audience + any extra metadata.
    let onAudienceSelected: (AmenPostAudience, AmenAudienceMetadata?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @State private var rowsVisible = false
    @State private var showSpacePicker = false
    @State private var selectedDestination: PostDestinationType = .privateJournal
    @State private var selectedSpace: AmenSpaceListItem?
    @State private var expandedInfoDestination: PostDestinationType?

    private var selectedOption: PostDestinationOption {
        PostDestinationOption.option(for: selectedDestination)
    }

    private var continueEnabled: Bool {
        selectedDestination != .space || selectedSpace != nil
    }

    private var continueTitle: String {
        if selectedDestination == .space {
            if let selectedSpace {
                return "Start in \(selectedSpace.name)"
            }
            return "Choose a Space"
        }
        return "Start in \(selectedOption.title)"
    }

    var body: some View {
        ZStack {
            sheetBackground

            if showSpacePicker {
                AmenSpacePickerSheet(
                    selectedSpace: selectedSpace,
                    onSpaceSelected: { item in
                        HapticManager.impact(style: .light)
                        selectedSpace = item
                        selectedDestination = .space
                        withAnimation(animation) {
                            showSpacePicker = false
                        }
                    },
                    onBack: {
                        withAnimation(animation) {
                            showSpacePicker = false
                        }
                    }
                )
                .transition(spacePickerTransition)
            } else {
                audienceList
                    .transition(audienceTransition)
            }
        }
        .animation(animation, value: showSpacePicker)
        .animation(animation, value: selectedDestination)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .amenSpringEntry) {
                rowsVisible = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(40)
        .presentationBackground(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.thinMaterial))
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Audience list page

    private var audienceList: some View {
        VStack(spacing: 0) {
            dragHandle
                .padding(.top, 12)
                .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    DestinationHeroCard(
                        option: selectedOption,
                        selectedSpace: selectedSpace,
                        reduceTransparency: reduceTransparency
                    )
                    .id(selectedDestination.rawValue + (selectedSpace?.id ?? "none"))
                    .transition(.opacity.combined(with: reduceMotion ? .identity : .scale(scale: 0.985)))

                    if let helperText = selectedOption.helperText {
                        VisibilityInfoRow(
                            icon: selectedDestination == .everyone ? "globe.americas.fill" : "shield.checkered",
                            text: helperText,
                            tint: selectedDestination == .everyone ? .orange : .accentColor,
                            reduceTransparency: reduceTransparency
                        )
                    }

                    destinationGrid
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)

            bottomActionArea
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Who is this for?")
                    .font(AMENFont.bold(30))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("Choose where this post should begin.")
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SmartVisibilityPill(reduceTransparency: reduceTransparency)
        }
        .padding(.top, 2)
    }

    private var destinationGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 154), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(Array(PostDestinationOption.all.enumerated()), id: \.element.id) { index, option in
                DestinationOptionCard(
                    option: option,
                    isSelected: selectedDestination == option.id,
                    isInfoExpanded: expandedInfoDestination == option.id,
                    isVisible: rowsVisible,
                    delay: Double(index) * 0.035,
                    reduceTransparency: reduceTransparency,
                    onTap: { select(option.id) },
                    onLongPress: { toggleInfo(option.id) }
                )
            }
        }
        .padding(.top, 2)
    }

    private var bottomActionArea: some View {
        VStack(spacing: 10) {
            Text("You can change this before posting.")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: continueTapped) {
                HStack(spacing: 10) {
                    Text(continueTitle)
                        .font(AMENFont.semiBold(17))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .contentTransition(.opacity)

                    Image(systemName: continueEnabled ? "arrow.right" : "building.2.fill")
                        .font(.systemScaled(15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, 18)
                .background {
                    Capsule(style: .continuous)
                        .fill(continueEnabled ? Color.accentColor : Color.secondary.opacity(0.45))
                }
                .shadow(color: Color.accentColor.opacity(continueEnabled ? 0.24 : 0), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
            .disabled(!continueEnabled && selectedDestination != .space)
            .accessibilityLabel(continueTitle)
            .accessibilityHint(continueEnabled ? "Continue to the composer" : "Choose a Space before continuing")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background {
            Rectangle()
                .fill(reduceTransparency ? Color(.systemBackground) : Color(.systemBackground).opacity(colorScheme == .dark ? 0.68 : 0.78))
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private var dragHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.secondary.opacity(0.28))
            .frame(width: 72, height: 6)
            .accessibilityHidden(true)
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.045),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var animation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .amenSpringStandard
    }

    private var audienceTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var spacePickerTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Actions

    @MainActor
    private func select(_ destination: PostDestinationType) {
        HapticManager.impact(style: .light)
        withAnimation(animation) {
            selectedDestination = destination
            expandedInfoDestination = nil
        }

        if destination == .space {
            withAnimation(animation) {
                showSpacePicker = true
            }
        }
    }

    @MainActor
    private func toggleInfo(_ destination: PostDestinationType) {
        HapticManager.impact(style: .medium)
        withAnimation(animation) {
            expandedInfoDestination = expandedInfoDestination == destination ? nil : destination
        }
    }

    @MainActor
    private func continueTapped() {
        if selectedDestination == .space && selectedSpace == nil {
            withAnimation(animation) {
                showSpacePicker = true
            }
            return
        }

        let metadata: AmenAudienceMetadata?
        if selectedDestination == .space, let selectedSpace {
            metadata = AmenAudienceMetadata(
                spaceId: selectedSpace.id,
                spaceName: selectedSpace.name,
                spaceType: selectedSpace.spaceType
            )
        } else {
            metadata = nil
        }

        commit(audience: selectedDestination, metadata: metadata)
    }

    @MainActor
    private func commit(audience: AmenPostAudience, metadata: AmenAudienceMetadata?) {
        withAnimation(animation) {
            isPresented = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 180))
            onAudienceSelected(audience, metadata)
        }
    }
}

// MARK: - Liquid Destination Components

private struct SmartVisibilityPill: View {
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Private by default")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.primary)
            Text("You control comments, sharing, and visibility")
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            Capsule(style: .continuous)
                .fill(reduceTransparency ? Color(.secondarySystemBackground) : Color(.systemBackground).opacity(0.45))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
        .amenGlassEffect(in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct DestinationHeroCard: View {
    let option: PostDestinationOption
    let selectedSpace: AmenSpaceListItem?
    let reduceTransparency: Bool

    private var title: String {
        if option.id == .space, let selectedSpace {
            return selectedSpace.name
        }
        return option.title
    }

    private var topPill: String {
        if option.id == .space, let selectedSpace {
            return "Space - \(selectedSpace.name)"
        }
        return "\(option.title) - \(option.subtitle)"
    }

    private var explanation: String {
        if option.id == .space, let selectedSpace {
            let memberText = selectedSpace.memberCount > 0 ? " with \(selectedSpace.memberCount) members" : ""
            return "Starts in \(selectedSpace.name)\(memberText). Space members can respond in context."
        }
        return option.visibilityDescription
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(backgroundFill)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.accentColor.opacity(reduceTransparency ? 0.08 : 0.16))
                        .frame(width: 138, height: 138)
                        .blur(radius: reduceTransparency ? 0 : 34)
                        .offset(x: 26, y: -38)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .bottomLeading) {
                    Circle()
                        .fill(Color.accentColor.opacity(reduceTransparency ? 0.05 : 0.11))
                        .frame(width: 118, height: 118)
                        .blur(radius: reduceTransparency ? 0 : 28)
                        .offset(x: -34, y: 34)
                        .accessibilityHidden(true)
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    DestinationChip(text: topPill, icon: "sparkles", reduceTransparency: reduceTransparency)
                    Spacer(minLength: 8)
                }

                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: option.icon)
                        .font(.systemScaled(31, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 62, height: 62)
                        .background {
                            Circle()
                                .fill(Color.accentColor.opacity(0.14))
                        }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(AMENFont.bold(24))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                        Text(explanation)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                FlexibleChipCloud(chips: option.chips, reduceTransparency: reduceTransparency)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.7)
        }
        .shadow(color: Color.accentColor.opacity(0.12), radius: 26, x: 0, y: 14)
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected destination, \(title)")
        .accessibilityValue(explanation)
    }

    private var backgroundFill: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.thinMaterial)
    }
}

private struct DestinationOptionCard: View {
    let option: PostDestinationOption
    let isSelected: Bool
    let isInfoExpanded: Bool
    let isVisible: Bool
    let delay: Double
    let reduceTransparency: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: option.icon)
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background {
                            Circle().fill(Color.accentColor.opacity(isSelected ? 0.18 : 0.12))
                        }

                    Spacer(minLength: 6)

                    trailingIndicator
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(option.subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isInfoExpanded {
                    VisibilityMiniInfo(option: option)
                        .transition(.opacity.combined(with: reduceMotion ? .identity : .move(edge: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: isInfoExpanded ? 176 : 116, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(DestinationCardPressStyle(isSelected: isSelected, reduceTransparency: reduceTransparency))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in onLongPress() }
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? (isSelected ? -3 : 0) : 10)
        .animation(reduceMotion ? .easeOut(duration: 0.12).delay(delay) : .amenSpringEntry.delay(delay), value: isVisible)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .amenEaseQuick, value: isInfoExpanded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(option.requiresSelection ? "Opens a Space picker. Long press for visibility details." : "Long press for visibility details.")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.systemScaled(12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background { Circle().fill(Color.accentColor) }
        } else if option.requiresSelection {
            Image(systemName: "chevron.right")
                .font(.systemScaled(13, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
        }
    }

    private var accessibilityLabel: String {
        "\(option.title), \(isSelected ? "selected, " : "")\(option.visibilityDescription)"
    }
}

private struct VisibilityMiniInfo: View {
    let option: PostDestinationOption

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            infoLine("Who can see it", option.subtitle)
            infoLine("Comments", option.id == .privateJournal ? "Off by default" : "Allowed")
            infoLine("Profile", option.id == .everyone ? "May appear" : "Limited")
            infoLine("Sharing", option.id == .everyone ? "Allowed" : "Limited")
        }
        .padding(.top, 2)
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(AMENFont.regular(10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(AMENFont.semiBold(10))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct DestinationChip: View {
    let text: String
    var icon: String? = nil
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .semibold))
            }
            Text(text)
                .font(AMENFont.semiBold(12))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            Capsule(style: .continuous)
                .fill(reduceTransparency ? Color(.systemBackground) : Color(.systemBackground).opacity(0.44))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
        }
        .amenGlassEffect(in: Capsule(style: .continuous))
    }
}

private struct FlexibleChipCloud: View {
    let chips: [String]
    let reduceTransparency: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    DestinationChip(text: chip, reduceTransparency: reduceTransparency)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    DestinationChip(text: chip, reduceTransparency: reduceTransparency)
                }
            }
        }
    }
}

private struct VisibilityInfoRow: View {
    let icon: String
    let text: String
    let tint: Color
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background { Circle().fill(tint.opacity(0.12)) }

            Text(text)
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reduceTransparency ? Color(.secondarySystemBackground) : Color(.systemBackground).opacity(0.42))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 0.8)
        }
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AmenSpacePickerSheet

/// Fetches the current user's joined Spaces from Firestore and presents them as a tappable list.
private struct AmenSpacePickerSheet: View {

    let selectedSpace: AmenSpaceListItem?
    let onSpaceSelected: (AmenSpaceListItem) -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var spaces: [AmenSpaceListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dragHandle
                .padding(.top, 12)
                .padding(.bottom, 16)

            header

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
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await fetchJoinedSpaces() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background { Circle().fill(reduceTransparency ? Color(.secondarySystemBackground) : Color(.systemBackground).opacity(0.38)) }
            .amenGlassEffect(in: Circle())
            .accessibilityLabel("Back")
            .accessibilityHint("Return to audience selection")

            VStack(alignment: .leading, spacing: 2) {
                Text("Choose a Space")
                    .font(AMENFont.bold(26))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Your post will begin in this Space.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var dragHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.secondary.opacity(0.28))
            .frame(width: 72, height: 6)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: States

    private var spaceLoadingView: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 64)
                    .shimmering()
            }
        }
        .padding(.horizontal, 20)
    }

    private func spaceErrorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.systemScaled(22, weight: .semibold))
                .foregroundStyle(.orange)
            Text(msg)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background { Capsule(style: .continuous).fill(reduceTransparency ? Color(.secondarySystemBackground) : Color(.systemBackground).opacity(0.35)) }
        .amenGlassEffect(in: Capsule(style: .continuous))
        .padding(.horizontal, 20)
    }

    private var spaceEmptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.2")
                .font(.systemScaled(28, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("You haven't joined any Spaces yet.")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background { Capsule(style: .continuous).fill(reduceTransparency ? Color(.secondarySystemBackground) : Color(.systemBackground).opacity(0.35)) }
        .amenGlassEffect(in: Capsule(style: .continuous))
        .padding(.horizontal, 20)
    }

    private var spaceListView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(spaces) { space in
                    SpaceOptionPill(
                        space: space,
                        icon: iconFor(spaceType: space.spaceType),
                        subtitle: displayType(space.spaceType),
                        isSelected: selectedSpace?.id == space.id
                    ) {
                        onSpaceSelected(space)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
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

private struct SpaceOptionPill: View {
    let space: AmenSpaceListItem
    let icon: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background { Circle().fill(Color.accentColor.opacity(0.13)) }

                VStack(alignment: .leading, spacing: 3) {
                    Text(space.name)
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(space.memberCount > 0 ? "\(subtitle) - \(space.memberCount) members" : subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 10)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 66)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(GlassPillPressStyle())
        .accessibilityLabel(space.name)
        .accessibilityValue(isSelected ? "Selected, \(subtitle)" : subtitle)
        .accessibilityHint("Select this Space")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct DestinationCardPressStyle: ButtonStyle {
    let isSelected: Bool
    let reduceTransparency: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.1 : 0.7)
            }
            .shadow(color: Color.accentColor.opacity(isSelected ? 0.20 : 0), radius: 18, x: 0, y: 10)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.04 : 0.07), radius: configuration.isPressed ? 7 : 14, x: 0, y: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .animation(.amenEaseQuick, value: configuration.isPressed)
    }

    private func backgroundFill(isPressed: Bool) -> some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
        let opacity = isSelected ? 0.52 : (isPressed ? 0.46 : 0.32)
        return AnyShapeStyle(Color(.systemBackground).opacity(opacity))
    }
}

private struct GlassPillPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if reduceTransparency {
                    Capsule(style: .continuous)
                        .fill(Color(.systemBackground))
                } else {
                    Capsule(style: .continuous)
                        .fill(Color(.systemBackground).opacity(configuration.isPressed ? 0.44 : 0.30))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.04 : 0.09), radius: configuration.isPressed ? 8 : 18, x: 0, y: configuration.isPressed ? 3 : 10)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .amenGlassEffect(in: Capsule(style: .continuous))
            .animation(.amenEaseQuick, value: configuration.isPressed)
    }
}

// MARK: - Shimmer helper

private extension View {
    @ViewBuilder
    func shimmering() -> some View {
        self.redacted(reason: .placeholder)
    }
}

// MARK: - Preview

#Preview("Audience Picker") {
    @Previewable @State var shown = true
    AmenAudienceFirstPickerView(isPresented: $shown) { audience, metadata in
        print("Selected: \(audience.displayName), space: \(metadata?.spaceName ?? "none")")
    }
    .background(Color(.systemGroupedBackground))
}
