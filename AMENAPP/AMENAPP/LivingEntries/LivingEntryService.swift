import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class LivingEntryService: ObservableObject {
    static let shared = LivingEntryService()

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    private init() {}

    deinit {
        listeners.forEach { $0.remove() }
    }

    func createEntry(_ entry: LivingEntry) async throws -> LivingEntry {
        let userId = try requireUserId(expected: entry.userId)
        var draft = entry
        let doc = db.collection("users").document(userId).collection("living_entries").document()
        draft.id = doc.documentID
        draft.userId = userId
        draft.createdAt = Date()
        draft.updatedAt = draft.createdAt
        try await doc.setData(clientWritableData(for: draft), merge: false)
        return draft
    }

    func updateEntry(_ entry: LivingEntry) async throws -> LivingEntry {
        let userId = try requireUserId(expected: entry.userId)
        guard let entryId = entry.id else {
            throw LivingEntryServiceError.missingEntryId
        }
        var updated = entry
        updated.updatedAt = Date()
        try await db.collection("users").document(userId).collection("living_entries").document(entryId).setData(clientWritableData(for: updated), merge: true)
        return updated
    }

    func completeEntry(_ entry: LivingEntry, reflectionAnswer: String? = nil) async throws -> LivingEntry {
        var updated = entry
        updated.state = reflectionAnswer == nil ? .completed : .needsReflection
        updated.completedAt = Date()
        updated.updatedAt = Date()
        updated.reflectionAnswer = reflectionAnswer
        return try await updateEntry(updated)
    }

    func deferEntry(_ entry: LivingEntry, until date: Date) async throws -> LivingEntry {
        var updated = entry
        updated.state = .deferred
        updated.deferredUntil = date
        updated.updatedAt = Date()
        return try await updateEntry(updated)
    }

    func archiveEntry(_ entry: LivingEntry) async throws -> LivingEntry {
        var updated = entry
        updated.state = .archived
        updated.updatedAt = Date()
        return try await updateEntry(updated)
    }

    func addReflection(
        entry: LivingEntry,
        answer: String,
        helpfulness: LivingEntryHelpfulness,
        aiLearningSummary: String? = nil,
        nextTriggerSuggestion: String? = nil
    ) async throws {
        let userId = try requireUserId(expected: entry.userId)
        guard let entryId = entry.id else {
            throw LivingEntryServiceError.missingEntryId
        }
        let reflectionRef = db.collection("users").document(userId).collection("living_entry_reflections").document()
        let reflection = LivingEntryReflection(
            id: reflectionRef.documentID,
            entryId: entryId,
            userId: userId,
            answer: answer,
            helpfulness: helpfulness,
            createdAt: Date(),
            aiLearningSummary: aiLearningSummary,
            nextTriggerSuggestion: nextTriggerSuggestion
        )
        try reflectionRef.setData(from: reflection, merge: false)

        var updated = entry
        updated.state = .completed
        updated.reflectionAnswer = answer
        updated.updatedAt = Date()
        _ = try await updateEntry(updated)
    }

    @discardableResult
    func observeEntries(onUpdate: @escaping ([LivingEntry]) -> Void) throws -> ListenerRegistration {
        let userId = try requireUserId()
        let listener = db.collection("users").document(userId).collection("living_entries")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let entries = snapshot?.documents.compactMap { try? $0.data(as: LivingEntry.self) } ?? []
                onUpdate(entries)
            }
        listeners.append(listener)
        return listener
    }

    @discardableResult
    func observeChurchEntries(churchId: String, onUpdate: @escaping ([LivingEntry]) -> Void) throws -> ListenerRegistration {
        let userId = try requireUserId()
        let listener = db.collection("users").document(userId).collection("living_entries")
            .whereField("churchId", isEqualTo: churchId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let entries = snapshot?.documents.compactMap { try? $0.data(as: LivingEntry.self) } ?? []
                onUpdate(entries)
            }
        listeners.append(listener)
        return listener
    }

    @discardableResult
    func observeTodayEntries(onUpdate: @escaping ([LivingEntry]) -> Void) throws -> ListenerRegistration {
        let userId = try requireUserId()
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? Date()
        let listener = db.collection("users").document(userId).collection("living_entries")
            .whereField("state", isEqualTo: LivingEntryState.active.rawValue)
            .whereField("dueAt", isGreaterThanOrEqualTo: start)
            .whereField("dueAt", isLessThan: end)
            .order(by: "dueAt")
            .addSnapshotListener { snapshot, _ in
                let entries = snapshot?.documents.compactMap { try? $0.data(as: LivingEntry.self) } ?? []
                onUpdate(entries)
            }
        listeners.append(listener)
        return listener
    }

    @discardableResult
    func observeNeedsReflection(onUpdate: @escaping ([LivingEntry]) -> Void) throws -> ListenerRegistration {
        let userId = try requireUserId()
        let listener = db.collection("users").document(userId).collection("living_entries")
            .whereField("state", isEqualTo: LivingEntryState.needsReflection.rawValue)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let entries = snapshot?.documents.compactMap { try? $0.data(as: LivingEntry.self) } ?? []
                onUpdate(entries)
            }
        listeners.append(listener)
        return listener
    }

    func upsertNoteDerivedEntries(from note: ChurchNote) async throws {
        guard let noteId = note.id else { return }
        let sourceTag = "source_note:\(noteId)"
        let userId = try requireUserId(expected: note.userId)
        let collection = db.collection("users").document(userId).collection("living_entries")

        let existingNoteEntry = try await collection
            .whereField("tags", arrayContains: sourceTag)
            .whereField("type", isEqualTo: LivingEntryType.churchNote.rawValue)
            .limit(to: 1)
            .getDocuments()
            .documents
            .first
            .flatMap { try? $0.data(as: LivingEntry.self) }

        let body = note.content.isEmpty ? (note.growthReflection ?? "") : note.content
        let baseContext = LivingEntryContextSnapshot.current(
            sourceSurface: .churchNotes,
            nearbyChurchId: note.churchId,
            recentChurchVisitId: note.churchId
        )
        let churchEntry = LivingEntry(
            id: existingNoteEntry?.id,
            userId: userId,
            type: .churchNote,
            intent: .sermonReflection,
            state: note.shouldRevisit ? .needsReflection : .active,
            title: note.title,
            body: body,
            churchId: note.churchId,
            churchName: note.churchName,
            sermonTitle: note.sermonTitle,
            scriptureRefs: note.scriptureReferences,
            tags: Array(Set(note.tags + [sourceTag, "church_note"])),
            dueAt: note.revisitDate,
            priorityScore: 0.62,
            gravityScore: 0.58,
            emotionalWeight: 0.45,
            regretRisk: 0.3,
            spiritualWeight: 0.82,
            triggerRules: churchNoteTriggers(from: note),
            contextSnapshot: baseContext,
            aiSummary: existingNoteEntry?.aiSummary,
            suggestedNextAction: note.actionStepThisWeek,
            reflectionPrompt: "What should you remember from this?"
        )
        _ = try await (existingNoteEntry == nil ? createEntry(churchEntry) : updateEntry(churchEntry))

        if let prayer = note.prayerFromSermon, !prayer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await upsertCompanionEntry(
                collection: collection,
                userId: userId,
                sourceTag: "\(sourceTag):prayer",
                type: .prayer,
                intent: .prayerCare,
                title: "Pray through \(note.title)",
                body: prayer,
                churchId: note.churchId,
                churchName: note.churchName,
                scriptureRefs: note.scriptureReferences,
                priorityScore: 0.56,
                gravityScore: 0.52,
                spiritualWeight: 0.85,
                dueAt: note.revisitDate,
                sourceSurface: .churchNotes
            )
        }

        if let actionStep = note.actionStepThisWeek, !actionStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await upsertCompanionEntry(
                collection: collection,
                userId: userId,
                sourceTag: "\(sourceTag):follow_up",
                type: .followUp,
                intent: .spiritualGrowth,
                title: "Follow up on \(note.title)",
                body: actionStep,
                churchId: note.churchId,
                churchName: note.churchName,
                scriptureRefs: note.scriptureReferences,
                priorityScore: 0.58,
                gravityScore: 0.6,
                spiritualWeight: 0.74,
                dueAt: note.revisitDate ?? Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                sourceSurface: .churchNotes
            )
        }
    }

    func removeAllObservers() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    private func upsertCompanionEntry(
        collection: CollectionReference,
        userId: String,
        sourceTag: String,
        type: LivingEntryType,
        intent: LivingEntryIntent,
        title: String,
        body: String,
        churchId: String?,
        churchName: String?,
        scriptureRefs: [String],
        priorityScore: Double,
        gravityScore: Double,
        spiritualWeight: Double,
        dueAt: Date?,
        sourceSurface: LivingEntrySourceSurface
    ) async throws {
        let existing = try await collection
            .whereField("tags", arrayContains: sourceTag)
            .whereField("type", isEqualTo: type.rawValue)
            .limit(to: 1)
            .getDocuments()
            .documents
            .first
            .flatMap { try? $0.data(as: LivingEntry.self) }

        let entry = LivingEntry(
            id: existing?.id,
            userId: userId,
            type: type,
            intent: intent,
            title: title,
            body: body,
            churchId: churchId,
            churchName: churchName,
            scriptureRefs: scriptureRefs,
            tags: [sourceTag, type.rawValue],
            dueAt: dueAt,
            priorityScore: priorityScore,
            gravityScore: gravityScore,
            emotionalWeight: 0.42,
            regretRisk: 0.28,
            spiritualWeight: spiritualWeight,
            triggerRules: [
                LivingEntryTriggerRule(type: .quietMoment, minQuietMinutes: 10),
                LivingEntryTriggerRule(type: .afterChurch, churchId: churchId)
            ],
            contextSnapshot: .current(sourceSurface: sourceSurface, nearbyChurchId: churchId, recentChurchVisitId: churchId),
            suggestedNextAction: existing?.suggestedNextAction,
            reflectionPrompt: type == .prayer ? "Keep praying, mark answered, or archive?" : "Did this change how you want to live this week?"
        )
        _ = try await (existing == nil ? createEntry(entry) : updateEntry(entry))
    }

    private func churchNoteTriggers(from note: ChurchNote) -> [LivingEntryTriggerRule] {
        var triggers = [
            LivingEntryTriggerRule(type: .afterChurch, churchId: note.churchId, afterEventMinutes: 120),
            LivingEntryTriggerRule(type: .quietMoment, minQuietMinutes: 12)
        ]
        if let revisitDate = note.revisitDate {
            triggers.append(LivingEntryTriggerRule(type: .time, scheduledAt: revisitDate))
        }
        if note.churchId != nil {
            triggers.append(LivingEntryTriggerRule(type: .churchProximity, locationRadiusMeters: 250, churchId: note.churchId))
        }
        return triggers
    }

    private func requireUserId(expected: String? = nil) throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw LivingEntryServiceError.unauthorized
        }
        if let expected, !expected.isEmpty, expected != userId {
            throw LivingEntryServiceError.userMismatch
        }
        return userId
    }

    private func clientWritableData(for entry: LivingEntry) throws -> [String: Any] {
        var data = try Firestore.Encoder().encode(entry)
        [
            "priorityScore",
            "gravityScore",
            "regretRisk",
            "aiSummary",
            "suggestedNextAction",
            "reflectionPrompt",
            "evolutionVersion"
        ].forEach { data.removeValue(forKey: $0) }
        return data
    }
}

enum LivingEntryServiceError: LocalizedError {
    case unauthorized
    case missingEntryId
    case userMismatch

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "You must be signed in to manage Living Entries."
        case .missingEntryId:
            return "This Living Entry is missing an identifier."
        case .userMismatch:
            return "The Living Entry user does not match the current account."
        }
    }
}
