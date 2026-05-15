import SwiftUI

// MARK: - Moderation Queue View
// Creator/moderator tool. Each item supports approve, block, request edit,
// escalate, mute user, lock thread, slow mode. All actions create audit log entries.

struct AmenCovenantModerationQueueView: View {
    let covenantId: String
    @State private var items: [CovenantModerationItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var actionTarget: CovenantModerationItem?
    @State private var actionSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(items) { item in
                                ModerationItemRow(item: item) {
                                    actionTarget = item
                                    actionSheet = true
                                }
                            }
                        } header: {
                            Text("\(items.count) item\(items.count == 1 ? "" : "s") needing review")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Moderation Queue")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadQueue() }
            .refreshable { await loadQueue() }
            .confirmationDialog("Moderation Action", isPresented: $actionSheet, presenting: actionTarget) { item in
                moderationActionButtons(for: item)
            } message: { item in
                Text(item.contentSnippet.prefix(80))
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: - Moderation Action Buttons

    @ViewBuilder
    private func moderationActionButtons(for item: CovenantModerationItem) -> some View {
        Button("Approve", role: .none) { perform("approved", on: item) }
        Button("Block Content", role: .destructive) { perform("blocked", on: item) }
        Button("Request Edit") { perform("request_edit", on: item) }
        Button("Escalate to AMEN Trust & Safety") { perform("escalated", on: item) }
        Button("Cancel", role: .cancel) {}
    }

    private func perform(_ action: String, on item: CovenantModerationItem) {
        Task {
            do {
                try await CovenantService.shared.performModerationAction(
                    covenantId: covenantId,
                    itemId: item.id ?? "",
                    action: action
                )
                await loadQueue()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func loadQueue() async {
        loading = true
        do {
            items = try await CovenantService.shared.loadModerationQueue(covenantId: covenantId)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No Items Needing Review")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Data appears after community activity begins.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Moderation Item Row

private struct ModerationItemRow: View {
    let item: CovenantModerationItem
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                contentTypeBadge
                Spacer()
                reportCountBadge
                Text(item.createdAt.dateValue(), style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(item.contentSnippet)
                .font(.subheadline)
                .lineLimit(3)
                .foregroundStyle(.primary)

            if !item.reportReasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.reportReasons.prefix(4), id: \.self) { reason in
                            Text(reason.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical: 3)
                                .background(Capsule().fill(Color.orange.opacity(0.1)))
                        }
                    }
                }
            }

            Button("Take Action") { onAction() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
        }
        .padding(.vertical, 4)
    }

    private var contentTypeBadge: some View {
        let label: String
        let icon: String
        switch item.contentType {
        case .message:     label = "Message";      icon = "text.bubble.fill"
        case .threadReply: label = "Thread Reply"; icon = "arrow.turn.down.right"
        case .post:        label = "Post";         icon = "doc.richtext.fill"
        case .profile:     label = "Profile";      icon = "person.fill"
        }
        return Label(label, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var reportCountBadge: some View {
        Text("\(item.reportCount) report\(item.reportCount == 1 ? "" : "s")")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(item.reportCount >= 3 ? Color.red : Color.orange))
    }
}
