// AmenDiscussionRoomListView.swift
// AMEN App — Community OS / Discussion OS (A6) Phase 2
//
// Browsable list of AmenDiscussionRooms for a given context (church, event, space).
// When contextRef is nil, shows all public rooms for global discovery.
//
// Feature flag gate: AMENFeatureFlags.shared.communityOSDiscussionEnabled
//
// Design (C3):
//   - systemGroupedBackground page background
//   - White cards (28pt continuous corner radius), soft shadow
//   - System semantic colors only
//   - No public participant counts (anti-vanity), no engagement comparisons
//   - Segmented filter by room type
//   - Create button → AmenUniversalComposer with discuss intent

import SwiftUI

// MARK: - AmenDiscussionRoomListView

struct AmenDiscussionRoomListView: View {

    /// When non-nil, only rooms whose `sourceContextRef` matches this value are shown.
    /// Pass nil to show all public rooms (global discovery mode).
    var contextRef: String? = nil

    @StateObject private var service = AmenDiscussionService()
    @State private var showCreateSheet = false
    @State private var selectedTypeFilter: AmenDiscussionRoomType? = nil
    @State private var selectedRoom: AmenDiscussionRoom? = nil
    @State private var errorAlertMessage: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed

    private var filteredRooms: [AmenDiscussionRoom] {
        guard let filter = selectedTypeFilter else { return service.rooms }
        return service.rooms.filter { $0.type == filter }
    }

    private var pinnedRooms: [AmenDiscussionRoom] {
        filteredRooms.filter { $0.isPinned }
    }

    private var unpinnedRooms: [AmenDiscussionRoom] {
        filteredRooms.filter { !$0.isPinned }
    }

    // MARK: - Body

    var body: some View {
        guard AMENFeatureFlags.shared.communityOSDiscussionEnabled else {
            return AnyView(featureUnavailableView)
        }
        return AnyView(mainContent)
    }

    // MARK: - Main content

    private var mainContent: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                Group {
                    if service.isLoading && service.rooms.isEmpty {
                        loadingState
                    } else if filteredRooms.isEmpty {
                        emptyState
                    } else {
                        roomList
                    }
                }
            }
            .navigationTitle("Discussions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .top) {
                filterBar
                    .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationDestination(item: $selectedRoom) { room in
                AmenDiscussionThreadView(room: room)
            }
            .sheet(isPresented: $showCreateSheet) {
                createRoomSheet
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { errorAlertMessage != nil },
                    set: { if !$0 { errorAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorAlertMessage = nil }
            } message: {
                Text(errorAlertMessage ?? "")
            }
        }
        .task {
            await loadRooms()
        }
        .refreshable {
            await loadRooms()
        }
        .onChange(of: service.errorMessage) { _, msg in
            if let msg { errorAlertMessage = msg }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Start a new discussion room")
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                filterChip(
                    label: "All",
                    systemImage: "square.grid.2x2",
                    isSelected: selectedTypeFilter == nil
                ) {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.18)) {
                        selectedTypeFilter = nil
                    }
                }

                // Per-type chips
                ForEach(AmenDiscussionRoomType.allCases, id: \.self) { type in
                    filterChip(
                        label: type.displayName,
                        systemImage: type.systemImage,
                        isSelected: selectedTypeFilter == type
                    ) {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.18)) {
                            selectedTypeFilter = (selectedTypeFilter == type) ? nil : type
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func filterChip(
        label: String,
        systemImage: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.systemScaled(11))
                Text(label)
                    .font(.systemScaled(13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.10)
                          : Color(uiColor: .secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter, \(isSelected ? "selected" : "not selected")")
    }

    // MARK: - Room list

    private var roomList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Pinned rooms
                if !pinnedRooms.isEmpty {
                    sectionHeader("Pinned")
                    ForEach(pinnedRooms) { room in
                        roomCard(room)
                    }
                }

                // Regular rooms
                if !unpinnedRooms.isEmpty {
                    if !pinnedRooms.isEmpty {
                        sectionHeader("All Rooms")
                    }
                    ForEach(unpinnedRooms) { room in
                        roomCard(room)
                    }
                }

                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.systemScaled(13, weight: .semibold))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Room card

    private func roomCard(_ room: AmenDiscussionRoom) -> some View {
        Button {
            selectedRoom = room
        } label: {
            roomCardContent(room)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel(roomCardAccessibilityLabel(room))
    }

    private func roomCardContent(_ room: AmenDiscussionRoom) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Room type icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: room.type.systemImage)
                    .font(.systemScaled(18, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // Title + pinned badge
                HStack(spacing: 6) {
                    Text(room.title)
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .label))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if room.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.systemScaled(10))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }

                // Description or last activity preview
                if !room.description.isEmpty {
                    Text(room.description)
                        .font(.systemScaled(13))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                // Footer: room type + privacy + last active
                HStack(spacing: 8) {
                    Label(room.type.displayName, systemImage: room.type.systemImage)
                        .font(.systemScaled(11))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))

                    Spacer()

                    // Privacy indicator
                    Image(systemName: room.privacyLevel.systemImage)
                        .font(.systemScaled(10))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))

                    // Last active (not a count — just relative timestamp)
                    if let lastAt = room.lastMessageAt {
                        Text(relativeTime(from: lastAt))
                            .font(.systemScaled(11))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                }

                // Provenance source hint
                if room.hasProvenance, let prov = room.provenance {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.systemScaled(10))
                        Text("From \(prov.sourceTypeDisplayName)")
                            .font(.systemScaled(11))
                    }
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 4)
        )
    }

    private func roomCardAccessibilityLabel(_ room: AmenDiscussionRoom) -> String {
        var parts = [room.title, room.type.displayName, room.privacyLevel.displayName]
        if room.isPinned { parts.append("Pinned") }
        if room.hasProvenance, let prov = room.provenance {
            parts.append("From \(prov.sourceTypeDisplayName)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .tint(Color.accentColor)
            Text("Loading discussions…")
                .font(.systemScaled(14))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(38, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)

            if selectedTypeFilter != nil {
                Text("No \(selectedTypeFilter!.displayName) rooms yet.")
                    .font(.callout)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
                Button("Show all rooms") {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.18)) {
                        selectedTypeFilter = nil
                    }
                }
                .font(.callout)
                .foregroundStyle(Color.accentColor)
            } else {
                Text("No discussion rooms yet.\nBe the first to start one.")
                    .font(.callout)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
                Button("Start a Room") {
                    showCreateSheet = true
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            selectedTypeFilter != nil
                ? "No \(selectedTypeFilter!.displayName) rooms yet."
                : "No discussion rooms yet. Tap Start a Room to create one."
        )
    }

    // MARK: - Create room sheet

    private var createRoomSheet: some View {
        // Delegates to AmenUniversalComposer with discuss intent.
        // When communityOSUniversalComposerEnabled is off, show a lightweight inline fallback.
        Group {
            if AMENFeatureFlags.shared.communityOSUniversalComposerEnabled {
                AmenUniversalComposer(
                    sourceRef: contextRef ?? "",
                    sourceType: "discussion",
                    initialIntent: "discuss",
                    isPresented: $showCreateSheet
                )
            } else {
                // Lightweight fallback sheet
                NavigationStack {
                    VStack(spacing: 24) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.systemScaled(36, weight: .ultraLight))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            .accessibilityHidden(true)
                        Text("Discussion creation is coming soon.")
                            .font(.callout)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                    .navigationTitle("New Discussion")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showCreateSheet = false }
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Feature unavailable

    private var featureUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(40, weight: .ultraLight))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
            Text("Discussions are coming soon.")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discussions feature is not yet available.")
    }

    // MARK: - Load helper

    private func loadRooms() async {
        do {
            try await service.loadRooms(forContextRef: contextRef)
        } catch {
            errorAlertMessage = error.localizedDescription
        }
    }

    // MARK: - Relative time helper

    private func relativeTime(from date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60       { return "now" }
        if diff < 3_600    { return "\(Int(diff / 60))m" }
        if diff < 86_400   { return "\(Int(diff / 3_600))h" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Global discovery") {
    AmenDiscussionRoomListView(contextRef: nil)
}

#Preview("Church context") {
    AmenDiscussionRoomListView(contextRef: "/churches/demo_church_123")
}
#endif
