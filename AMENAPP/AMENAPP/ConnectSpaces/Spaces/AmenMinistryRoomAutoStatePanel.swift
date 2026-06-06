// AmenMinistryRoomAutoStatePanel.swift
// AMEN Connect + Spaces — Living Ministry Rooms
// Agent 3 — built 2026-06-01

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Auto State ViewModel

@MainActor
final class AmenMinistryRoomAutoStatePanelViewModel: ObservableObject {
    @Published var items: [AmenConnectSpacesDerivedItem] = []
    @Published var isLoading: Bool = false
    @Published var loadError: String?

    private let spaceId: String
    private var listener: ListenerRegistration?

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    var openDecisions: [AmenConnectSpacesDerivedItem] {
        items.filter { $0.kind == .decision && $0.status == .open }
    }

    var blockers: [AmenConnectSpacesDerivedItem] {
        items.filter { $0.kind == .risk && $0.status == .open }
    }

    var ownersAndNextSteps: [AmenConnectSpacesDerivedItem] {
        items.filter { $0.owner != nil }
    }

    func startListening() {
        isLoading = true
        let db = Firestore.firestore()
        listener = db
            .collection(AmenConnectSpacesFirestoreBinding.spacesCollection)
            .document(spaceId)
            .collection(AmenConnectSpacesFirestoreBinding.itemsSubcollection)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.loadError = error.localizedDescription
                    return
                }
                guard let snapshot else { return }
                self.items = snapshot.documents.compactMap { doc in
                    try? AmenConnectSpacesFirestoreBinding.bindDerivedItem(doc)
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}

// MARK: - Auto State Panel

struct AmenMinistryRoomAutoStatePanel: View {
    let spaceId: String
    @Binding var isExpanded: Bool

    @StateObject private var viewModel: AmenMinistryRoomAutoStatePanelViewModel

    init(spaceId: String, isExpanded: Binding<Bool>) {
        self.spaceId = spaceId
        _isExpanded = isExpanded
        _viewModel = StateObject(wrappedValue: AmenMinistryRoomAutoStatePanelViewModel(spaceId: spaceId))
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animationStyle: Animation {
        reduceMotion ? .easeInOut(duration: 0.01) : .easeInOut(duration: 0.25)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Glass card header
            panelHeader

            if isExpanded {
                panelContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: Color.accentColor.opacity(0.12), radius: 12, y: 4)
        }
        .task {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        Button {
            withAnimation(animationStyle) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Room State")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color.accentColor)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .animation(animationStyle, value: isExpanded)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse room state panel" : "Expand room state panel")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Panel Content

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .opacity(0.2)
                .padding(.horizontal, 14)

            if let error = viewModel.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    // Open Decisions
                    itemSection(
                        title: "Open Decisions",
                        icon: "scale.3d",
                        items: viewModel.openDecisions,
                        emptyLabel: "No open decisions"
                    )

                    // Blockers
                    itemSection(
                        title: "Blockers",
                        icon: "exclamationmark.triangle",
                        items: viewModel.blockers,
                        emptyLabel: "No blockers"
                    )

                    // Owners & Next Steps
                    ownerSection

                    // Next Gathering (stub)
                    nextGatheringSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Item Section

    private func itemSection(
        title: String,
        icon: String,
        items: [AmenConnectSpacesDerivedItem],
        emptyLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)

            if items.isEmpty {
                Text(emptyLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.quaternary)
                    .italic()
            } else {
                ForEach(items) { item in
                    derivedItemRow(item)
                }
            }
        }
    }

    private func derivedItemRow(_ item: AmenConnectSpacesDerivedItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 5, height: 5)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                if let owner = item.owner {
                    Text("Owner: \(owner.prefix(20))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let due = item.due {
                    Text("Due: \(due.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(buildItemAccessibilityLabel(item))
    }

    private func buildItemAccessibilityLabel(_ item: AmenConnectSpacesDerivedItem) -> String {
        var parts = [item.title]
        if let owner = item.owner { parts.append("Owner: \(owner.prefix(20))") }
        if let due = item.due { parts.append("Due: \(due.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: ". ")
    }

    // MARK: - Owners & Next Steps Section

    private var ownerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text("Owners & Next Steps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Owners and Next Steps")

            let owned = viewModel.ownersAndNextSteps
            if owned.isEmpty {
                Text("No owners assigned")
                    .font(.system(size: 12))
                    .foregroundStyle(.quaternary)
                    .italic()
            } else {
                ForEach(owned) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.431, green: 0.294, blue: 0.710))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            if let owner = item.owner {
                                Text(String(owner.prefix(20)))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.title), owned by \(item.owner.map { String($0.prefix(20)) } ?? "unknown")")
                }
            }
        }
    }

    // MARK: - Next Gathering (stub)

    private var nextGatheringSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text("Next Gathering")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Next Gathering")

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Sunday 9:00 AM")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Sunday 9:00 AM")
        }
    }
}
