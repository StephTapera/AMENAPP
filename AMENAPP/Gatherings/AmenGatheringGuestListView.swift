// AmenGatheringGuestListView.swift
// AMENAPP — Gathering Guest List
//
// Privacy: only host/admin can see prayer/pastoral follow-up answers.
// Visibility is controlled by guestListVisibility setting.

import SwiftUI

struct AmenGatheringGuestListView: View {
    let gathering: AmenGathering

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: GuestListViewModel

    init(gathering: AmenGathering) {
        self.gathering = gathering
        _vm = StateObject(wrappedValue: GuestListViewModel(gatheringId: gathering.gatheringId))
    }

    private let tabs: [(String, AmenGatheringRsvpStatus?)] = [
        ("Going", .going),
        ("Maybe", .maybe),
        ("Can't Go", .declined),
        ("Waitlisted", .waitlisted),
        ("Pending", .pending)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading guest list...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.allRsvps.isEmpty {
                    emptyState
                } else {
                    guestListContent
                }
            }
            .navigationTitle("Guest List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await vm.load() }
        }
    }

    private var guestListContent: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            listForCurrentTab
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.0) { (label, status) in
                    let count = vm.count(for: status)
                    if count > 0 {
                        GuestTabChip(
                            label: label,
                            count: count,
                            isSelected: vm.selectedTab == label
                        ) {
                            vm.selectedTab = label
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var listForCurrentTab: some View {
        let status = tabs.first { $0.0 == vm.selectedTab }?.1
        let filtered = vm.rsvps(for: status)

        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { rsvp in
                    GuestRow(rsvp: rsvp, isHost: vm.isHost)
                    if rsvp.id != filtered.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No RSVPs yet")
                .font(.headline)
            Text("Be the first to RSVP to this gathering.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Guest Row

private struct GuestRow: View {
    let rsvp: AmenGatheringRsvp
    let isHost: Bool

    var body: some View {
        HStack(spacing: 12) {
            avatarCircle

            VStack(alignment: .leading, spacing: 2) {
                Text(rsvp.displayName ?? "Guest")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 6) {
                    Image(systemName: rsvp.status.systemImage)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                    Text(rsvp.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let checkedIn = rsvp.checkedInAt {
                        Text("· Checked in \(checkedIn, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if isHost {
                hostControls
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rsvp.displayName ?? "Guest"), \(rsvp.status.displayName)")
    }

    private var avatarCircle: some View {
        Group {
            if let url = rsvp.photoURL, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle().fill(Color(.systemGray5))
            Text(rsvp.displayName?.prefix(1).uppercased() ?? "?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var hostControls: some View {
        if rsvp.status == .pending {
            Menu {
                Button("Approve") {
                    Task {
                        try? await AmenGatheringService.shared.updateGuestRsvpStatus(
                            gatheringId: rsvp.gatheringId,
                            userId: rsvp.uid,
                            status: .going
                        )
                    }
                }
                Button("Deny", role: .destructive) {
                    Task {
                        try? await AmenGatheringService.shared.updateGuestRsvpStatus(
                            gatheringId: rsvp.gatheringId,
                            userId: rsvp.uid,
                            status: .declined
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Manage request from \(rsvp.displayName ?? "guest")")
        }
    }

    private var statusColor: Color {
        switch rsvp.status {
        case .going:      return .green
        case .maybe:      return .orange
        case .declined:   return .red
        case .waitlisted: return .blue
        case .pending:    return .secondary
        }
    }
}

// MARK: - Tab Chip

private struct GuestTabChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.caption.weight(.semibold))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color(.systemGray5))
                    .clipShape(Capsule(style: .continuous))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(isSelected ? Color.primary : Color(.systemGray6))
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(count) people")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - View Model

@MainActor
private final class GuestListViewModel: ObservableObject {
    let gatheringId: String
    @Published var allRsvps: [AmenGatheringRsvp] = []
    @Published var isLoading = false
    @Published var selectedTab = "Going"
    var isHost = false

    init(gatheringId: String) {
        self.gatheringId = gatheringId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            allRsvps = try await AmenGatheringService.shared.listGatheringRsvps(gatheringId: gatheringId)
            if allRsvps.contains(where: { $0.status == .going }) {
                selectedTab = "Going"
            } else if !allRsvps.isEmpty {
                selectedTab = "Maybe"
            }
        } catch {
            // Non-fatal — show empty state
        }
    }

    func count(for status: AmenGatheringRsvpStatus?) -> Int {
        guard let status else { return allRsvps.count }
        return allRsvps.filter { $0.status == status }.count
    }

    func rsvps(for status: AmenGatheringRsvpStatus?) -> [AmenGatheringRsvp] {
        guard let status else { return allRsvps }
        return allRsvps.filter { $0.status == status }
    }
}
