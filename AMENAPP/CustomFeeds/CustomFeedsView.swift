// CustomFeedsView.swift
// AMENAPP — Custom Feeds feature (Agent G)
//
// Two view entry points:
//   EditFeedsView  — manage / reorder existing feeds  (presented modally)
//   CreateFeedView — compose a brand-new custom feed  (pushed from EditFeedsView)

import SwiftUI
import FirebaseAuth

// MARK: - EditFeedsView

struct EditFeedsView: View {

    @State private var vm = CustomFeedsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AmenTheme.Colors.backgroundGrouped
                    .ignoresSafeArea()

                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    feedList
                }
            }
            .navigationTitle("Edit feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await vm.loadFeeds() }
        }
    }

    // MARK: Feed list

    private var feedList: some View {
        List {
            // "Create new feed" row
            NavigationLink {
                CreateFeedView(vm: vm)
            } label: {
                createFeedRow
            }
            .listRowBackground(AmenTheme.Colors.backgroundGroupedRow)

            // Beta info banner
            betaBanner
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            // Built-in feeds (locked / non-draggable)
            let builtIns = vm.feeds.filter { $0.isBuiltIn }
            let customs  = vm.feeds.filter { !$0.isBuiltIn }

            if !builtIns.isEmpty {
                Section {
                    ForEach(builtIns) { feed in
                        FeedRow(feed: feed, isBuiltIn: true)
                            .listRowBackground(AmenTheme.Colors.backgroundGroupedRow)
                    }
                }
            }

            if !customs.isEmpty {
                Section {
                    ForEach(customs) { feed in
                        FeedRow(feed: feed, isBuiltIn: false)
                            .listRowBackground(AmenTheme.Colors.backgroundGroupedRow)
                    }
                    .onMove { from, to in
                        // Compute destination offset into full `feeds` array
                        let builtInCount = builtIns.count
                        let adjustedFrom = IndexSet(from.map { $0 + builtInCount })
                        let adjustedTo   = to + builtInCount
                        withAnimation(Motion.adaptive(Motion.springRelease)) {
                            vm.reorder(from: adjustedFrom, to: adjustedTo)
                        }
                    }
                    .onDelete { idxSet in
                        let toDelete = idxSet.map { customs[$0] }
                        Task {
                            for feed in toDelete {
                                await vm.deleteFeed(feed)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: "Create new feed" row

    private var createFeedRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(AmenTheme.Colors.amenBlue, lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
            }
            Text("Create new feed")
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.amenBlue)
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityLabel("Create new feed")
    }

    // MARK: Beta banner

    private var betaBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Beta  ·  Tap and drag to reorder feeds.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Beta feature. Tap and drag to reorder feeds.")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .fontWeight(.semibold)
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
    }
}

// MARK: - FeedRow

private struct FeedRow: View {
    let feed: CustomFeedConfig
    let isBuiltIn: Bool

    private var detailLabel: String? {
        guard !isBuiltIn else { return nil }
        let topics   = feed.topicIds.count
        let profiles = feed.profileIds.count
        if topics > 0 && profiles > 0 {
            return "\(topics) topic\(topics == 1 ? "" : "s"), \(profiles) profile\(profiles == 1 ? "" : "s")"
        } else if topics > 0 {
            return "\(topics) topic\(topics == 1 ? "" : "s")"
        } else if profiles > 0 {
            return "\(profiles) profile\(profiles == 1 ? "" : "s")"
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle indicator (system provides the real handle via .onMove)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isBuiltIn
                    ? AmenTheme.Colors.textQuaternary
                    : AmenTheme.Colors.textTertiary
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                if let detail = detailLabel {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }

            Spacer()

            if isBuiltIn {
                Text("Built-in")
                    .font(.caption2)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(AmenTheme.Colors.surfaceChip)
                    )
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isBuiltIn
                ? "\(feed.name), built-in feed"
                : [feed.name, detailLabel].compactMap { $0 }.joined(separator: ", ")
        )
    }
}

// MARK: - CreateFeedView

struct CreateFeedView: View {

    let vm: CustomFeedsViewModel
    @Environment(\.dismiss) private var dismiss

    // Draft state
    @State private var name: String = ""
    @State private var feedDescription: String = ""
    @State private var isPublic: Bool = false
    @State private var draftProfileIds: [String] = []
    @State private var draftTopicIds: [String] = []

    // Suggested profiles
    @State private var suggestedProfiles: [SuggestedUser] = []
    @State private var isLoadingSuggestions: Bool = false

    // Presentation
    @State private var showCommunityPicker: Bool = false
    @State private var isCreating: Bool = false

    @FocusState private var focusedField: Field?
    private enum Field { case name, description }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    feedDetailsSection
                    publicToggleSection
                    inFeedSection
                    suggestedProfilesSection
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, AmenLayout.horizontalInset)
                .padding(.top, 16)
            }
            .background(AmenTheme.Colors.backgroundGrouped.ignoresSafeArea())
            .navigationTitle("Create feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { createButton }
            .task { await loadSuggestions() }
        }
    }

    // MARK: - Feed details (name + description)

    private var feedDetailsSection: some View {
        VStack(spacing: 0) {
            // Name field
            TextField("Feed name", text: $name)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .description }
                .accessibilityLabel("Feed name")

            Divider()
                .padding(.leading, 16)

            // Description field
            TextField("Enter a brief description.", text: $feedDescription, axis: .vertical)
                .font(.body)
                .lineLimit(3...6)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .focused($focusedField, equals: .description)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .accessibilityLabel("Feed description")
        }
        .amenGlassCard()
    }

    // MARK: - Public toggle

    private var publicToggleSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Public feed")
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Text("When this is on, anyone can see and share this feed. The feed and its profiles may be suggested for others to follow.")
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isPublic)
                .labelsHidden()
                .tint(AmenTheme.Colors.amenBlue)
                .accessibilityLabel("Public feed")
                .accessibilityHint("When on, anyone can see and share this feed.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .amenGlassCard()
    }

    // MARK: - "In this feed" section

    private var inFeedSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("In this feed")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.bottom, 8)

            Button {
                showCommunityPicker = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                        .font(.body)
                    Text("Add profiles or topics")
                        .font(.body)
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                    Spacer()
                    if !draftProfileIds.isEmpty || !draftTopicIds.isEmpty {
                        let count = draftProfileIds.count + draftTopicIds.count
                        Text("\(count) added")
                            .font(.footnote)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add profiles or topics to this feed")
        }
        // Sheet: community/topic picker
        .sheet(isPresented: $showCommunityPicker) {
            communityPickerSheet
        }
        .amenGlassCard()
    }

    /// Placeholder community picker — replace with ComposerCommunityPickerView when available.
    @ViewBuilder
    private var communityPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Add profiles or topics to your feed.")
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
            .navigationTitle("Add to feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCommunityPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCommunityPicker = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Suggested profiles section

    @ViewBuilder
    private var suggestedProfilesSection: some View {
        if isLoadingSuggestions || !suggestedProfiles.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("Suggested profiles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.bottom, 8)

                VStack(spacing: 0) {
                    if isLoadingSuggestions {
                        HStack {
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    } else {
                        ForEach(Array(suggestedProfiles.prefix(5).enumerated()), id: \.element.id) { idx, profile in
                            SuggestedProfileRow(
                                profile: profile,
                                isAdded: draftProfileIds.contains(profile.id)
                            ) {
                                toggleProfile(profile.id)
                            }
                            if idx < min(suggestedProfiles.count, 5) - 1 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                }
                .amenGlassCard()
            }
        }
    }

    // MARK: - Create button (sticky footer)

    private var createButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                guard !isCreating, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                isCreating = true
                Task {
                    await vm.createFeed(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: feedDescription,
                        isPublic: isPublic,
                        profileIds: draftProfileIds,
                        topicIds: draftTopicIds
                    )
                    isCreating = false
                    dismiss()
                }
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(AmenTheme.Colors.buttonPrimaryText)
                            .padding(.trailing, 6)
                    }
                    Text("Create feed")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.pill, style: .continuous)
                        .fill(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? AmenTheme.Colors.textTertiary
                              : AmenTheme.Colors.buttonPrimary)
                )
                .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            }
            .buttonStyle(AmenPressStyle())
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            .padding(.horizontal, AmenLayout.horizontalInset)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityLabel("Create feed, \(name)")
            .accessibilityHint(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Enter a feed name to enable this button."
                : "Double tap to create your custom feed."
            )
        }
        .background(AmenTheme.Colors.backgroundGrouped.opacity(0.95))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
    }

    // MARK: - Helpers

    private func toggleProfile(_ profileId: String) {
        withAnimation(Motion.adaptive(Motion.popToggle)) {
            if draftProfileIds.contains(profileId) {
                draftProfileIds.removeAll { $0 == profileId }
            } else {
                draftProfileIds.append(profileId)
            }
        }
    }

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        suggestedProfiles = await SuggestedFollowsService.shared.fetchSuggestions()
        isLoadingSuggestions = false
    }
}

// MARK: - SuggestedProfileRow

private struct SuggestedProfileRow: View {
    let profile: SuggestedUser
    let isAdded: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView

            // Name + username
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)

                if !profile.username.isEmpty {
                    Text("@\(profile.username)")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Add / Added pill
            Button(action: onTap) {
                Text(isAdded ? "Added" : "Add")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isAdded ? AmenTheme.Colors.textSecondary : AmenTheme.Colors.amenBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .strokeBorder(
                                isAdded
                                    ? AmenTheme.Colors.textTertiary
                                    : AmenTheme.Colors.amenBlue,
                                lineWidth: 1.2
                            )
                    )
            }
            .buttonStyle(AmenPressStyle(scale: 0.94))
            .accessibilityLabel(isAdded
                ? "Remove \(profile.displayName) from feed"
                : "Add \(profile.displayName) to feed"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: Avatar

    private var avatarView: some View {
        Group {
            if let urlString = profile.profileImageURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(AmenTheme.Colors.amenBlue.opacity(0.15))
            Text(initials(for: profile.displayName))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
