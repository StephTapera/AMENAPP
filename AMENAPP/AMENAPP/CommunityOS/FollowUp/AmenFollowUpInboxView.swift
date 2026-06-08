// AmenFollowUpInboxView.swift
// AMEN App — CommunityOS / FollowUp
//
// Phase 2 — Agent A15 (Smart Follow-Up)
// Inbox view for private per-user follow-up threads.
//
// Design contract:
//   - White Liquid Glass card surface (systemBackground / secondarySystemGroupedBackground)
//   - Monochrome SF Symbols throughout — no colour used to imply urgency
//   - insetGrouped list style
//   - Large navigation title "Follow-Ups"
//   - Empty state: neutral ContentUnavailableView (no guilt, no streak)
//   - Swipe left → Snooze 7 days (gray)
//   - Swipe right → Mark Done (green)
//   - Accessibility: all interactive controls have .accessibilityLabel
//
// Anti-engagement rules:
//   ANTI-ENGAGEMENT: No streak count, no "you haven't checked in" language in empty state.
//   ANTI-ENGAGEMENT: No badge count display in navigation bar.
//   ANTI-ENGAGEMENT: Snooze defaults to 7 days — respects user's pace.

import SwiftUI

// MARK: - AmenFollowUpInboxView

struct AmenFollowUpInboxView: View {

    let userId: String

    @StateObject private var service = AmenFollowUpService()
    @State private var isLoading = false
    @State private var loadError: Error?
    @State private var editingNoteItem: AmenFollowUpItem?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading follow-ups")
                } else if service.activeItems.isEmpty {
                    // ANTI-ENGAGEMENT: Empty state is neutral and informational.
                    // No guilt, no empty-inbox streak, no "come back soon" language.
                    ContentUnavailableView(
                        "Nothing yet",
                        systemImage: "checkmark.circle",
                        description: Text(
                            "Tap Follow Up on any prayer, discussion, or opportunity to track it here."
                        )
                    )
                } else {
                    List {
                        ForEach(service.activeItems) { item in
                            AmenFollowUpRow(
                                item: item,
                                onResolve: {
                                    Task {
                                        try? await service.resolveFollowUp(
                                            id: item.id,
                                            userId: userId,
                                            note: nil
                                        )
                                    }
                                },
                                onSnooze: {
                                    Task {
                                        // ANTI-ENGAGEMENT: Default snooze is 7 days — no nagging.
                                        try? await service.snoozeFollowUp(
                                            id: item.id,
                                            userId: userId,
                                            days: 7
                                        )
                                    }
                                },
                                onDismiss: {
                                    Task {
                                        try? await service.dismissFollowUp(
                                            id: item.id,
                                            userId: userId
                                        )
                                    }
                                },
                                onEditNote: {
                                    editingNoteItem = item
                                }
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Follow-Ups")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                // Pull-to-refresh: user-initiated reload, not platform-initiated.
                try? await service.loadFollowUps(userId: userId)
            }
            .sheet(item: $editingNoteItem) { item in
                FollowUpNoteEditorSheet(
                    item: item,
                    userId: userId,
                    service: service
                )
            }
            .task {
                isLoading = true
                do {
                    try await service.loadFollowUps(userId: userId)
                } catch {
                    loadError = error
                }
                isLoading = false
            }
        }
    }
}

// MARK: - AmenFollowUpRow

struct AmenFollowUpRow: View {

    let item: AmenFollowUpItem
    var onResolve: () -> Void
    var onSnooze: () -> Void
    var onDismiss: () -> Void
    var onEditNote: () -> Void

    var body: some View {
        HStack(spacing: 12) {

            // Monochrome type icon — no colour to avoid urgency signalling.
            Image(systemName: item.itemType.systemImage)
                .font(.systemScaled(18, weight: .regular))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(width: 24)
                .accessibilityHidden(true)

            // Title + preview stack
            VStack(alignment: .leading, spacing: 3) {
                Text(item.objectTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)

                if let preview = item.objectPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(2)
                }

                // Snoozed badge
                if item.status == .snoozed, let until = item.snoozedUntil {
                    Text("Snoozed until \(until.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption2)
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }

                // Type label — small, secondary
                Text(item.itemType.displayName)
                    .font(.caption2.weight(.regular))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }

            Spacer(minLength: 0)

            // Trailing quick-action buttons
            HStack(spacing: 8) {

                // Note button (pencil)
                if item.userNote != nil {
                    Button(action: onEditNote) {
                        Image(systemName: "note.text")
                            .font(.systemScaled(14))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit private note")
                }

                // Resolve / Done checkmark
                Button(action: onResolve) {
                    Image(systemName: "checkmark.circle")
                        .font(.systemScaled(20, weight: .light))
                        .foregroundStyle(Color(uiColor: .systemGreen))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(item.objectTitle) as done")

                // Snooze (moon)
                Button(action: onSnooze) {
                    Image(systemName: "moon.zzz")
                        .font(.systemScaled(20, weight: .light))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Snooze \(item.objectTitle) for 7 days")
            }
        }
        .padding(.vertical, 4)
        // Swipe from leading edge → resolve (Done)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onResolve) {
                Label("Done", systemImage: "checkmark.circle")
            }
            .tint(.green)
            .accessibilityLabel("Mark as done")
        }
        // Swipe from trailing edge → snooze (7 days) + dismiss
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onDismiss) {
                Label("Dismiss", systemImage: "xmark.circle")
            }
            .tint(Color(uiColor: .systemRed))
            .accessibilityLabel("Dismiss follow-up")

            Button(action: onSnooze) {
                Label("Snooze", systemImage: "moon.zzz")
            }
            .tint(Color(uiColor: .systemGray))
            .accessibilityLabel("Snooze for 7 days")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.itemType.displayName): \(item.objectTitle)")
    }
}

// MARK: - FollowUpNoteEditorSheet

/// Private note editor. Notes are never transmitted off-device in plaintext;
/// they are written to the user's private Firestore subcollection only.
private struct FollowUpNoteEditorSheet: View {

    let item: AmenFollowUpItem
    let userId: String
    let service: AmenFollowUpService

    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String
    @State private var isSaving = false

    init(item: AmenFollowUpItem, userId: String, service: AmenFollowUpService) {
        self.item = item
        self.userId = userId
        self.service = service
        _noteText = State(initialValue: item.userNote ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {

                Text("Private note — only visible to you.")
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 4)

                TextEditor(text: $noteText)
                    .font(.body)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .accessibilityLabel("Private note for \(item.objectTitle)")

                Spacer()
            }
            .padding(20)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel editing note")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                            try? await service.updateNote(id: item.id, note: trimmed, userId: userId)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isSaving)
                    .accessibilityLabel("Save private note")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenFollowUpInboxView(userId: "previewUser")
}
#endif
