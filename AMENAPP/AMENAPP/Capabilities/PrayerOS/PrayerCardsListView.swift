// PrayerCardsListView.swift
// AMEN Capabilities v1 — Prayer cards list (Wave 1: Lane D)
//
// Displays all prayer cards for the signed-in user.
// Backed by PrayerOSService (prayerOS_listCards callable).
// Status filter refreshes the list automatically via .onChange.
//
// Contract: Docs/Capabilities/CONTRACTS.md §2.3, §3.3
// Models:   AMENAPP/AMENAPP/Capabilities/CapabilityModels.swift (FROZEN)

import SwiftUI

// MARK: - PrayerCardsListView

struct PrayerCardsListView: View {

    // MARK: Dependencies

    @StateObject private var service = PrayerOSService.shared

    // MARK: State

    @State private var showingCreateSheet = false
    @State private var statusFilter: PrayerStatus = .active

    // MARK: - Body

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Prayers")
                .toolbar { toolbarContent }
                .sheet(isPresented: $showingCreateSheet) {
                    PrayerOSCardSheet(editingCard: nil)
                        .presentationDetents([.medium, .large])
                }
                .task {
                    try? await service.loadCards(status: statusFilter)
                }
                .onChange(of: statusFilter) { _, newStatus in
                    Task { try? await service.loadCards(status: newStatus) }
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if service.isLoading {
            loadingView
        } else if service.cards.isEmpty {
            emptyStateView
        } else {
            cardListView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Loading prayers…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading your prayers")
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hands.and.sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(emptyStateTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(emptyStateSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingCreateSheet = true
            } label: {
                Label("Start your first prayer", systemImage: "plus")
                    .font(.body)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Start your first prayer")
            .accessibilityHint("Double-tap to create a new prayer card")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var cardListView: some View {
        List {
            ForEach(service.cards) { card in
                NavigationLink {
                    PrayerCardDetailView(card: card)
                } label: {
                    PrayerCardRow(card: card)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("Add Prayer")
            .accessibilityHint("Double-tap to create a new prayer card")
        }

        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker("Filter", selection: $statusFilter) {
                    Text("Active").tag(PrayerStatus.active)
                    Text("Answered").tag(PrayerStatus.answered)
                    Text("Archived").tag(PrayerStatus.archived)
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter prayers")
            .accessibilityHint("Choose which prayer status to display")
        }
    }

    // MARK: - Helpers

    private var emptyStateTitle: String {
        switch statusFilter {
        case .active:   return "No active prayers"
        case .answered: return "No answered prayers yet"
        case .archived: return "No archived prayers"
        }
    }

    private var emptyStateSubtitle: String {
        switch statusFilter {
        case .active:   return "Start by adding a prayer for someone or something on your heart."
        case .answered: return "When God answers a prayer, mark it answered to keep a testimony."
        case .archived: return "Archived prayers are stored here for reference."
        }
    }
}

// MARK: - PrayerCardRow

struct PrayerCardRow: View {

    let card: PrayerCard

    private var pendingFollowUpCount: Int {
        card.followUps.filter { $0.status == .pending }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Subject + status indicator
            HStack(alignment: .firstTextBaseline) {
                Text(card.subject.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                statusBadge
            }

            // Category chip
            Text(card.category.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            // Detail preview
            if !card.detail.isEmpty {
                Text(card.detail.prefix(100))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Pending follow-up count badge
            if pendingFollowUpCount > 0 {
                Label(
                    "\(pendingFollowUpCount) follow-up\(pendingFollowUpCount == 1 ? "" : "s") pending",
                    systemImage: "bell.badge"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        switch card.status {
        case .active:
            EmptyView()
        case .answered:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
                .accessibilityHidden(true)
        case .archived:
            Image(systemName: "archivebox.fill")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Accessibility label

    private var accessibilityDescription: String {
        var parts = ["Prayer for \(card.subject.displayName)", card.category.displayName]
        switch card.status {
        case .answered: parts.append("answered")
        case .archived: parts.append("archived")
        case .active: break
        }
        if pendingFollowUpCount > 0 {
            parts.append("\(pendingFollowUpCount) follow-up\(pendingFollowUpCount == 1 ? "" : "s") pending")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - PrayerCardDetailView

/// Minimal detail view for the navigation destination.
/// Displays full card info and provides edit and status-change actions.
struct PrayerCardDetailView: View {

    let card: PrayerCard

    @State private var showingEditSheet = false

    var body: some View {
        List {
            Section("Subject") {
                LabeledContent("Name", value: card.subject.displayName)
                LabeledContent("Type", value: card.subject.type == .person ? "Person" : "Topic")
            }

            Section("Category") {
                LabeledContent("Category", value: card.category.displayName)
            }

            if !card.detail.isEmpty {
                Section("Detail") {
                    Text(card.detail)
                        .font(.body)
                        .accessibilityLabel("Prayer detail: \(card.detail)")
                }
            }

            if !card.followUps.isEmpty {
                Section("Follow-ups") {
                    ForEach(Array(card.followUps.enumerated()), id: \.offset) { index, fu in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(fu.dueAt, style: .date)
                                    .font(.subheadline)
                                if let note = fu.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: followUpStatusIcon(fu.status))
                                .foregroundStyle(followUpStatusColor(fu.status))
                        }
                    }
                }
            }
        }
        .navigationTitle(card.subject.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditSheet = true }
                    .accessibilityLabel("Edit this prayer card")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            PrayerOSCardSheet(editingCard: card)
                .presentationDetents([.medium, .large])
        }
    }

    private func followUpStatusIcon(_ status: PrayerFollowUpStatus) -> String {
        switch status {
        case .pending:   return "clock"
        case .done:      return "checkmark.circle.fill"
        case .dismissed: return "xmark.circle"
        }
    }

    private func followUpStatusColor(_ status: PrayerFollowUpStatus) -> Color {
        switch status {
        case .pending:   return .orange
        case .done:      return .green
        case .dismissed: return .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    PrayerCardsListView()
}
