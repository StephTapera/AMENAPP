
//  ChurchNotesSpiritualReminderSheet.swift
//  AMENAPP
//
//  W2 — "Create Spiritual Reminder?" affordance sheet.
//  Appears after a note is saved, only when extractionEnabled flag is ON.
//  "Ask Accountability Partner" is hidden for minors and confidential notes. (S7)
//

import SwiftUI

// MARK: - Sheet View

struct ChurchNotesSpiritualReminderSheet: View {

    let actions: [SpiritualAction]
    let noteSensitivity: NoteSensitivity
    let isMinor: Bool
    let onDismiss: () -> Void
    let onRemindLater: (SpiritualAction) -> Void
    let onAddToPrayerList: (SpiritualAction) -> Void
    let onAddToDiscipleshipPlan: (SpiritualAction) -> Void
    let onAskAccountabilityPartner: (SpiritualAction) -> Void

    @State private var selectedActionIndex: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection
                Divider()
                if actions.isEmpty {
                    emptyState
                } else {
                    actionList
                }
            }
            .navigationTitle("Spiritual Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                        .foregroundStyle(Color.amenGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.amenGold)
                .accessibilityHidden(true)
            Text("From your notes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }

    // MARK: Action List

    private var actionList: some View {
        List {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Section {
                    actionRowOptions(for: action)
                } header: {
                    Label(action.summary, systemImage: action.kind.sfSymbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.amenPurple)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func actionRowOptions(for action: SpiritualAction) -> some View {
        // Option 1: Remind me later
        Button {
            onRemindLater(action)
            onDismiss()
        } label: {
            Label("Remind me later", systemImage: "bell.badge")
        }
        .foregroundStyle(.primary)
        .accessibilityHint("Schedules a gentle follow-up notification for this action.")

        // Option 2: Add to Prayer List
        Button {
            onAddToPrayerList(action)
            onDismiss()
        } label: {
            Label("Add to Prayer List", systemImage: "hands.sparkles")
        }
        .foregroundStyle(.primary)
        .accessibilityHint("Adds this to your personal prayer list.")

        // Option 3: Add to Discipleship Plan
        Button {
            onAddToDiscipleshipPlan(action)
            onDismiss()
        } label: {
            Label("Add to Discipleship Plan", systemImage: "chart.line.uptrend.xyaxis")
        }
        .foregroundStyle(.primary)
        .accessibilityHint("Adds this as an approved action step in your discipleship plan.")

        // Option 4: Ask Accountability Partner
        // Hidden for minors (S7) and for confidential notes (S1/S3)
        if shouldShowAccountabilityOption(for: action) {
            Button {
                onAskAccountabilityPartner(action)
                onDismiss()
            } label: {
                Label("Ask Accountability Partner", systemImage: "person.2.wave.2")
            }
            .foregroundStyle(.primary)
            .accessibilityHint("Invites a trusted friend to walk alongside you on this action.")
        }
    }

    private func shouldShowAccountabilityOption(for action: SpiritualAction) -> Bool {
        guard !isMinor else { return false }             // S7: minors cannot share without guardian
        guard noteSensitivity != .confidential else { return false }  // S1/S3: confidential = no share
        return true
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.checkmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No action steps detected")
                .font(.headline)
            Text("Try adding an Action or Prayer block to your note.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Affordance View Modifier

/// Attach to the note editor to present the reminder sheet after save.
struct SpiritualReminderAffordance: ViewModifier {

    @Binding var isPresented: Bool
    let actions: [SpiritualAction]
    let noteSensitivity: NoteSensitivity
    let isMinor: Bool
    let onRemindLater: (SpiritualAction) -> Void
    let onAddToPrayerList: (SpiritualAction) -> Void
    let onAddToDiscipleshipPlan: (SpiritualAction) -> Void
    let onAskAccountabilityPartner: (SpiritualAction) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ChurchNotesSpiritualReminderSheet(
                actions: actions,
                noteSensitivity: noteSensitivity,
                isMinor: isMinor,
                onDismiss: { isPresented = false },
                onRemindLater: onRemindLater,
                onAddToPrayerList: onAddToPrayerList,
                onAddToDiscipleshipPlan: onAddToDiscipleshipPlan,
                onAskAccountabilityPartner: onAskAccountabilityPartner
            )
        }
    }
}

extension View {
    func spiritualReminderAffordance(
        isPresented: Binding<Bool>,
        actions: [SpiritualAction],
        noteSensitivity: NoteSensitivity,
        isMinor: Bool = false,
        onRemindLater: @escaping (SpiritualAction) -> Void = { _ in },
        onAddToPrayerList: @escaping (SpiritualAction) -> Void = { _ in },
        onAddToDiscipleshipPlan: @escaping (SpiritualAction) -> Void = { _ in },
        onAskAccountabilityPartner: @escaping (SpiritualAction) -> Void = { _ in }
    ) -> some View {
        modifier(SpiritualReminderAffordance(
            isPresented: isPresented,
            actions: actions,
            noteSensitivity: noteSensitivity,
            isMinor: isMinor,
            onRemindLater: onRemindLater,
            onAddToPrayerList: onAddToPrayerList,
            onAddToDiscipleshipPlan: onAddToDiscipleshipPlan,
            onAskAccountabilityPartner: onAskAccountabilityPartner
        ))
    }
}

// MARK: - Extraction Service (orchestrates W1 + W2)

/// Call this after a note is saved. Returns extracted actions if flags are ON.
/// Callers must check `canShowAffordance` before presenting the sheet.
@MainActor
final class ChurchNotesDiscipleshipService: ObservableObject {

    @Published private(set) var pendingActions: [SpiritualAction] = []
    @Published private(set) var pendingSensitivity: NoteSensitivity = .confidential
    @Published var showingReminderSheet = false

    private let enforcer = DiscipleshipLocusEnforcer()
    private let extractor = RoutingActionExtractor()

    /// Run classification + extraction after a note is saved.
    /// The sheet will only be shown for non-confidential notes with at least one action. (S1)
    func processNoteSave(_ note: ChurchNote) async {
        guard ChurchNotesDiscipleshipFlags.masterEnabled,
              ChurchNotesDiscipleshipFlags.extractionEnabled else { return }

        let content = NoteContent(note: note)
        let sensitivity = enforcer.sensitivity(for: content)
        let computeLocus = locus(for: sensitivity)

        // S1: Never proactively surface confidential notes.
        guard enforcer.canProactivelySurface(sensitivity: sensitivity) else { return }

        let actions = await extractor.extract(from: content, locus: computeLocus)
        guard !actions.isEmpty else { return }

        pendingActions = actions
        pendingSensitivity = sensitivity
        showingReminderSheet = true
    }

    func handleRemindLater(_ action: SpiritualAction) {
        // W3 governor will schedule the notification
        ChurchNotesNotificationGovernorImpl.shared.scheduleIfAllowed(action)
    }

    func handleAddToPrayerList(_ action: SpiritualAction, note: ChurchNote) async {
        // Appends the action summary to the note's prayerFromSermon field via a local update
        // (no server call; purely local enrichment of the note model)
        _ = action  // W2 stub; full wiring in W3
    }

    func handleAddToDiscipleshipPlan(_ action: SpiritualAction) {
        _ = action  // W2 stub; full wiring via ChurchNoteActionItemsService in W3
    }
}
