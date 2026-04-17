// ChurchReflectionView.swift
// AMENAPP
//
// Post-service reflection screen. Warm, minimal, not homework.
// Prompts the user to capture one takeaway, application, prayer, and verse.
// AI assistance (Berean) is available on-demand — never forced.
// Midweek reminder is configurable from this screen.
//
// Design: single-question cards, one-tap transforms, optional AI,
//         3–5 primary choices max visible at once.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - ViewModel

@MainActor
final class ChurchReflectionViewModel: ObservableObject {

    @Published var reflection: ChurchReflection?
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var isComplete = false
    @Published var showMidweekReminderSheet = false
    @Published var showAISheet = false
    @Published var aiIsGenerating = false
    @Published var aiSummaryDraft: String = ""
    @Published var aiPrayerDraft: String = ""

    // Editable fields
    @Published var primaryTakeaway: String = ""
    @Published var applicationText: String = ""
    @Published var prayerText: String = ""
    @Published var verseToCarry: String = ""
    @Published var actionItems: [ReflectionActionItem] = []
    @Published var midweekReminderEnabled: Bool = false

    private let journeyId: String
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    init(journeyId: String) {
        self.journeyId = journeyId
        loadReflection()
    }

    // MARK: - Load

    func loadReflection() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Look for a reflection linked to this journey
        db.collection("churchReflections")
            .whereField("userId", isEqualTo: uid)
            .whereField("journeyId", isEqualTo: journeyId)
            .limit(to: 1)
            .getDocuments { [weak self] snapshot, _ in
                guard let self else { return }
                if let doc = snapshot?.documents.first,
                   let r = try? doc.data(as: ChurchReflection.self) {
                    self.reflection = r
                    self.primaryTakeaway = r.primaryTakeaway ?? ""
                    self.applicationText = r.applicationText ?? ""
                    self.prayerText = r.prayerText ?? ""
                    self.verseToCarry = r.verseToCarry ?? ""
                    self.actionItems = r.actionItems
                    self.midweekReminderEnabled = r.midweekReminderEnabled
                    self.aiSummaryDraft = r.aiSummary ?? ""
                    self.aiPrayerDraft = r.aiSuggestedPrayer ?? ""
                }
                self.isLoading = false
            }
    }

    // MARK: - Save

    func save() async {
        guard let reflectionId = reflection?.id else {
            await createNewReflection()
            return
        }
        isSaving = true

        // Only client-editable fields — never send server-owned fields
        let data: [String: Any] = [
            "primaryTakeaway": primaryTakeaway,
            "applicationText": applicationText,
            "prayerText": prayerText,
            "verseToCarry": verseToCarry,
            "actionItems": actionItems.map { ["id": $0.id, "text": $0.text, "completed": $0.completed] },
            "midweekReminderEnabled": midweekReminderEnabled,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        try? await db.collection("churchReflections").document(reflectionId).updateData(data)
        isSaving = false
    }

    func complete() async {
        await save()
        guard let reflectionId = reflection?.id else { return }
        try? await db.collection("churchReflections").document(reflectionId).updateData([
            "status": "completed",
            "updatedAt": FieldValue.serverTimestamp(),
        ])
        // Schedule midweek reminder if enabled
        if midweekReminderEnabled {
            await scheduleMidweekReminder(reflectionId: reflectionId)
        }
        isComplete = true
    }

    // MARK: - AI Assistance (on-demand only)

    func generateAISummary() async {
        guard let reflectionId = reflection?.id else { return }
        aiIsGenerating = true
        do {
            let result = try await functions.httpsCallable("generateReflectionSeedFromNotes").call([
                "noteSessionId": reflection?.noteSessionId as Any
            ])
            if let data = result.data as? [String: Any] {
                aiSummaryDraft = data["summary"] as? String ?? ""
            }
        } catch {
            // Graceful fallback — AI unavailable is not a failure
        }
        aiIsGenerating = false
    }

    func applyAISummary() {
        if !aiSummaryDraft.isEmpty { primaryTakeaway = aiSummaryDraft }
    }

    func applyAIPrayer() {
        if !aiPrayerDraft.isEmpty { prayerText = aiPrayerDraft }
    }

    // MARK: - Action items

    func addActionItem(text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        actionItems.append(ReflectionActionItem(text: text))
    }

    func toggleActionItem(_ item: ReflectionActionItem) {
        if let idx = actionItems.firstIndex(where: { $0.id == item.id }) {
            actionItems[idx].completed.toggle()
        }
    }

    func removeActionItem(_ item: ReflectionActionItem) {
        actionItems.removeAll { $0.id == item.id }
    }

    // MARK: - Private

    private func createNewReflection() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let journey = ChurchJourneyStore.shared.activeJourney else { return }
        isSaving = true
        let ref = db.collection("churchReflections").document()
        let data: [String: Any] = [
            "userId": uid,
            "churchId": journey.churchId,
            "journeyId": journeyId,
            "noteSessionId": journey.noteSessionId as Any,
            "primaryTakeaway": primaryTakeaway,
            "applicationText": applicationText,
            "prayerText": prayerText,
            "verseToCarry": verseToCarry,
            "actionItems": actionItems.map { ["id": $0.id, "text": $0.text, "completed": $0.completed] },
            "midweekReminderEnabled": midweekReminderEnabled,
            "status": "draft",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        try? await ref.setData(data)
        isSaving = false
    }

    private func scheduleMidweekReminder(reflectionId: String) async {
        _ = try? await functions.httpsCallable("scheduleMidweekReflectionReminder").call([
            "reflectionId": reflectionId,
            "reminderDayOffset": 3
        ])
    }
}

// MARK: - View

struct ChurchReflectionView: View {

    let journeyId: String
    @StateObject private var vm: ChurchReflectionViewModel
    @Environment(\.dismiss) private var dismiss

    init(journeyId: String) {
        self.journeyId = journeyId
        _vm = StateObject(wrappedValue: ChurchReflectionViewModel(journeyId: journeyId))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading reflection…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.isComplete {
                    completedState
                } else {
                    reflectionContent
                }
            }
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.save() }
                    } label: {
                        if vm.isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                        }
                    }
                    .accessibilityLabel("Save reflection")
                }
            }
        }
    }

    // MARK: - Reflection Content

    private var reflectionContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                // AI Summary card — appears first if available
                if !vm.aiSummaryDraft.isEmpty {
                    aiSuggestionCard(
                        title: "From your notes",
                        body: vm.aiSummaryDraft,
                        applyLabel: "Use as takeaway"
                    ) {
                        vm.applyAISummary()
                    }
                }

                takeawayCard
                applicationCard
                verseCard
                prayerCard
                actionItemsCard
                midweekReminderCard
                completeButton
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Takeaway Card

    private var takeawayCard: some View {
        ReflectionCard(
            question: "What stood out most?",
            icon: "star"
        ) {
            TextEditor(text: $vm.primaryTakeaway)
                .font(.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Primary takeaway from service")
                .overlay(alignment: .topLeading) {
                    if vm.primaryTakeaway.isEmpty {
                        Text("One sentence is enough…")
                            .foregroundStyle(Color(.placeholderText))
                            .font(.body)
                            .padding(4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

            if !vm.aiSummaryDraft.isEmpty && vm.primaryTakeaway.isEmpty {
                Button("Use AI suggestion") { vm.applyAISummary() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Apply AI-suggested takeaway")
            }
        }
    }

    // MARK: - Application Card

    private var applicationCard: some View {
        ReflectionCard(
            question: "What is one thing you want to apply?",
            icon: "checkmark.circle"
        ) {
            TextEditor(text: $vm.applicationText)
                .font(.body)
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Application from service")
                .overlay(alignment: .topLeading) {
                    if vm.applicationText.isEmpty {
                        Text("Something small is fine…")
                            .foregroundStyle(Color(.placeholderText))
                            .font(.body)
                            .padding(4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
    }

    // MARK: - Verse Card

    private var verseCard: some View {
        ReflectionCard(
            question: "A verse to carry this week?",
            icon: "book.closed"
        ) {
            TextField("e.g. John 3:16", text: $vm.verseToCarry)
                .font(.body)
                .accessibilityLabel("Verse to remember this week")

            if let reflection = vm.reflection,
               let verse = reflection.verseToCarry, !verse.isEmpty {
                HStack {
                    Text("From notes: \(verse)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use") { vm.verseToCarry = verse }
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Use verse from notes: \(verse)")
                }
            }
        }
    }

    // MARK: - Prayer Card

    private var prayerCard: some View {
        ReflectionCard(
            question: "Want to turn any note into a prayer?",
            icon: "hands.sparkles"
        ) {
            TextEditor(text: $vm.prayerText)
                .font(.body)
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Prayer from service")
                .overlay(alignment: .topLeading) {
                    if vm.prayerText.isEmpty {
                        Text("Optional — your own words…")
                            .foregroundStyle(Color(.placeholderText))
                            .font(.body)
                            .padding(4)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

            if !vm.aiPrayerDraft.isEmpty && vm.prayerText.isEmpty {
                Button("Use AI prayer suggestion") { vm.applyAIPrayer() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Apply AI-suggested prayer")
            }
        }
    }

    // MARK: - Action Items Card

    private var actionItemsCard: some View {
        ReflectionCard(
            question: "Any action steps?",
            icon: "list.bullet"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(vm.actionItems) { item in
                    HStack {
                        Button {
                            vm.toggleActionItem(item)
                        } label: {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.completed ? .secondary : .primary)
                        }
                        .accessibilityLabel(item.completed ? "Mark incomplete" : "Mark complete")

                        Text(item.text)
                            .font(.subheadline)
                            .strikethrough(item.completed)
                            .foregroundStyle(item.completed ? .secondary : .primary)

                        Spacer()

                        Button {
                            vm.removeActionItem(item)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .accessibilityLabel("Remove action: \(item.text)")
                    }
                }

                AddActionItemRow { text in
                    vm.addActionItem(text: text)
                }
            }
        }
    }

    // MARK: - Midweek Reminder Card

    private var midweekReminderCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remind me midweek")
                    .font(.subheadline.weight(.medium))
                Text("A gentle nudge Wednesday to revisit this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $vm.midweekReminderEnabled)
                .labelsHidden()
                .accessibilityLabel("Enable midweek reminder")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Complete Button

    private var completeButton: some View {
        Button {
            Task { await vm.complete() }
        } label: {
            Text("Save Reflection")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.primary)
                .foregroundStyle(Color(.systemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("Save and complete reflection")
    }

    // MARK: - AI Suggestion Card

    private func aiSuggestionCard(
        title: String,
        body: String,
        applyLabel: String,
        apply: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(4)

            HStack(spacing: 8) {
                Button(applyLabel) { apply() }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .accessibilityLabel(applyLabel)

                Text("Edit before using")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Completed State

    private var completedState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Reflection saved")
                    .font(.title3.weight(.semibold))
                if vm.midweekReminderEnabled {
                    Text("We'll remind you midweek.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Done") { dismiss() }
                .font(.body.weight(.medium))
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemFill))
                .clipShape(Capsule())
                .padding(.top, 8)
                .accessibilityLabel("Close reflection")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Reflection Card Component

private struct ReflectionCard<Content: View>: View {
    let question: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(question)
                    .font(.subheadline.weight(.semibold))
            }
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Add Action Item Row

private struct AddActionItemRow: View {
    let onAdd: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Image(systemName: "plus.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Add an action step", text: $text)
                .font(.subheadline)
                .focused($focused)
                .onSubmit {
                    onAdd(text)
                    text = ""
                }
                .accessibilityLabel("New action step")
        }
    }
}
