//
//  GuidedSelahSessionViewModel.swift
//  AMENAPP
//
//  Resumable Selah session state machine. Persists every step transition to
//  Firestore `guidedSessions/{id}` so the user can background and resume.
//
//  Step order: read → listen → understand → reflect → pray → apply → complete
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

// MARK: - Session Persistence Service

@MainActor
final class SelahFirestoreSessionService {
    static let shared = SelahFirestoreSessionService()
    private let db = Firestore.firestore()
    private init() {}

    func createSession(_ doc: GuidedSelahSessionDocument) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw GuidedSessionError.notAuthenticated
        }
        var data = sessionToDict(doc)
        data["ownerUid"] = uid
        try await db.collection("guidedSessions").document(doc.id).setData(data)
    }

    func updateSession(_ doc: GuidedSelahSessionDocument) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            throw GuidedSessionError.notAuthenticated
        }
        try await db.collection("guidedSessions").document(doc.id).setData(sessionToDict(doc), merge: true)
    }

    func fetchActiveSession(for verseId: String, translation: SelahTranslation) async throws -> GuidedSelahSessionDocument? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await db.collection("guidedSessions")
            .whereField("ownerUid", isEqualTo: uid)
            .whereField("verseId", isEqualTo: verseId)
            .whereField("translation", isEqualTo: translation.rawValue)
            .order(by: "updatedAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        return snap.documents.first.flatMap { docToSession($0.data(), id: $0.documentID) }
    }

    func fetchRecentSessions(limit: Int = 10) async throws -> [GuidedSelahSessionDocument] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snap = try await db.collection("guidedSessions")
            .whereField("ownerUid", isEqualTo: uid)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { docToSession($0.data(), id: $0.documentID) }
    }

    // MARK: - Private helpers

    private func sessionToDict(_ doc: GuidedSelahSessionDocument) -> [String: Any] {
        var d: [String: Any] = [
            "id": doc.id,
            "ownerUid": doc.ownerUid,
            "verseId": doc.verseId,
            "translation": doc.translation.rawValue,
            "currentStep": doc.currentStep.rawValue,
            "completedSteps": doc.completedSteps.map { $0.rawValue },
            "recentThemes": doc.recentThemes.map { $0.rawValue },
            "startedAt": Timestamp(date: doc.startedAt),
            "updatedAt": Timestamp(date: doc.updatedAt),
        ]
        if let rid = doc.reflectionId { d["reflectionId"] = rid }
        if let csk = doc.cachedStudySheetKey { d["cachedStudySheetKey"] = csk }
        if let ca = doc.completedAt { d["completedAt"] = Timestamp(date: ca) }
        return d
    }

    private func docToSession(_ d: [String: Any], id: String) -> GuidedSelahSessionDocument? {
        guard
            let verseId = d["verseId"] as? String,
            let translationRaw = d["translation"] as? String,
            let translation = SelahTranslation(rawValue: translationRaw),
            let stepRaw = d["currentStep"] as? String,
            let currentStep = GuidedSelahStep(rawValue: stepRaw),
            let ownerUid = d["ownerUid"] as? String
        else { return nil }

        let completedSteps = (d["completedSteps"] as? [String] ?? []).compactMap { GuidedSelahStep(rawValue: $0) }
        let recentThemes = (d["recentThemes"] as? [String] ?? []).compactMap { SelahSafetyTheme(rawValue: $0) }
        let startedAt = (d["startedAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (d["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        let completedAt = (d["completedAt"] as? Timestamp)?.dateValue()

        return GuidedSelahSessionDocument(
            id: id,
            ownerUid: ownerUid,
            verseId: verseId,
            translation: translation,
            currentStep: currentStep,
            completedSteps: completedSteps,
            reflectionId: d["reflectionId"] as? String,
            cachedStudySheetKey: d["cachedStudySheetKey"] as? String,
            recentThemes: recentThemes,
            startedAt: startedAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}

// MARK: - Error

enum GuidedSessionError: LocalizedError {
    case notAuthenticated
    case saveFailed(String)
    case stepOutOfOrder

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Sign in to save your session progress."
        case .saveFailed(let msg): return "Could not save progress: \(msg)"
        case .stepOutOfOrder: return "Steps must be completed in order."
        }
    }
}

// MARK: - ViewModel

@MainActor
final class GuidedSelahSessionViewModel: ObservableObject {

    // MARK: Published state

    @Published var session: GuidedSelahSessionDocument?
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    @Published var error: String?
    @Published var isComplete: Bool = false

    // Per-step supporting state
    @Published var studySheetViewModel = SelahLensViewModel()
    @Published var reflectionViewModel = SelahReflectionViewModel()
    @Published var prayerText: String = ""
    @Published var applyText: String = ""
    @Published var selectedCrossReference: String?

    // Input
    let verseId: String
    let verseText: String
    let translation: SelahTranslation
    let verseReference: String

    private let service = SelahFirestoreSessionService.shared
    private let functions = SelahFunctionsService.shared

    // MARK: Step ordering

    static let stepOrder: [GuidedSelahStep] = [.read, .listen, .understand, .reflect, .pray, .apply, .complete]

    var currentStep: GuidedSelahStep { session?.currentStep ?? .read }
    var completedSteps: Set<GuidedSelahStep> { Set(session?.completedSteps ?? []) }

    var canGoBack: Bool {
        guard let idx = Self.stepOrder.firstIndex(of: currentStep) else { return false }
        return idx > 0 && currentStep != .complete
    }

    var canSkip: Bool { currentStep != .apply && currentStep != .complete }

    var adaptiveIntroLine: String {
        guard let themes = session?.recentThemes, let dominant = themes.first else { return "Let's slow down and be present with Scripture." }
        switch dominant {
        case .anxiety, .grief: return "You've been in some heavy passages lately. Take your time — rest is here too."
        case .doubt: return "Wrestling with God is ancient and holy. Let's keep exploring together."
        case .addiction: return "One day, one verse, one step. You're here, and that matters."
        case .selfHarm, .abuse, .trafficking, .coercion: return "You are seen and loved. Let's stay in the Word together."
        case .neutral: return "Let's slow down and be present with Scripture."
        }
    }

    // MARK: Init

    init(verseId: String, verseText: String, translation: SelahTranslation, verseReference: String) {
        self.verseId = verseId
        self.verseText = verseText
        self.translation = translation
        self.verseReference = verseReference

        reflectionViewModel.verseId = verseId
        reflectionViewModel.translation = translation
    }

    // MARK: - Load or Create

    func loadOrCreateSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let existing = try await service.fetchActiveSession(for: verseId, translation: translation),
               existing.completedAt == nil {
                session = existing
                isComplete = existing.currentStep == .complete
                if existing.currentStep == .understand {
                    await loadStudySheetIfNeeded()
                }
            } else {
                let uid = Auth.auth().currentUser?.uid ?? "anonymous"
                let newSession = GuidedSelahSessionDocument(
                    id: UUID().uuidString,
                    ownerUid: uid,
                    verseId: verseId,
                    translation: translation,
                    currentStep: .read,
                    completedSteps: [],
                    reflectionId: nil,
                    cachedStudySheetKey: nil,
                    recentThemes: [],
                    startedAt: Date(),
                    updatedAt: Date(),
                    completedAt: nil
                )
                try await service.createSession(newSession)
                session = newSession
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Step Navigation

    func advance() async {
        guard let current = session else { return }
        let order = Self.stepOrder
        guard let idx = order.firstIndex(of: current.currentStep),
              idx + 1 < order.count else { return }
        let nextStep = order[idx + 1]
        await transitionTo(nextStep, completing: current.currentStep)
    }

    func goBack() async {
        guard let current = session else { return }
        let order = Self.stepOrder
        guard let idx = order.firstIndex(of: current.currentStep), idx > 0 else { return }
        let prevStep = order[idx - 1]
        var updated = current
        updated = GuidedSelahSessionDocument(
            id: updated.id, ownerUid: updated.ownerUid, verseId: updated.verseId,
            translation: updated.translation, currentStep: prevStep,
            completedSteps: updated.completedSteps, reflectionId: updated.reflectionId,
            cachedStudySheetKey: updated.cachedStudySheetKey, recentThemes: updated.recentThemes,
            startedAt: updated.startedAt, updatedAt: Date(), completedAt: nil
        )
        await persist(updated)
    }

    func skip() async {
        guard canSkip else { return }
        await advance()
    }

    func finishSession() async {
        guard let current = session else { return }
        let updated = GuidedSelahSessionDocument(
            id: current.id, ownerUid: current.ownerUid, verseId: current.verseId,
            translation: current.translation, currentStep: .complete,
            completedSteps: current.completedSteps + [.apply],
            reflectionId: current.reflectionId,
            cachedStudySheetKey: current.cachedStudySheetKey,
            recentThemes: current.recentThemes,
            startedAt: current.startedAt, updatedAt: Date(), completedAt: Date()
        )
        await persist(updated)
        isComplete = true
    }

    // MARK: - Step-specific side effects

    func onUnderstandStepAppear() async {
        await loadStudySheetIfNeeded()
        if let current = session, current.cachedStudySheetKey == nil,
           case .loaded(let themeResp) = studySheetViewModel.state {
            let cacheKey = "\(translation.rawValue)_\(verseId.replacingOccurrences(of: "/", with: "_"))_\(themeResp.promptVersion)"
            var updated = current
            updated = GuidedSelahSessionDocument(
                id: updated.id, ownerUid: updated.ownerUid, verseId: updated.verseId,
                translation: updated.translation, currentStep: updated.currentStep,
                completedSteps: updated.completedSteps, reflectionId: updated.reflectionId,
                cachedStudySheetKey: cacheKey, recentThemes: updated.recentThemes,
                startedAt: updated.startedAt, updatedAt: Date(), completedAt: nil
            )
            await persist(updated)
        }
    }

    func onReflectionSaved(reflectionId: String) async {
        guard let current = session else { return }
        let updated = GuidedSelahSessionDocument(
            id: current.id, ownerUid: current.ownerUid, verseId: current.verseId,
            translation: current.translation, currentStep: current.currentStep,
            completedSteps: current.completedSteps, reflectionId: reflectionId,
            cachedStudySheetKey: current.cachedStudySheetKey, recentThemes: current.recentThemes,
            startedAt: current.startedAt, updatedAt: Date(), completedAt: nil
        )
        await persist(updated)
    }

    func openCrossReference(_ verseId: String) {
        selectedCrossReference = verseId
    }

    // MARK: - Private helpers

    private func transitionTo(_ step: GuidedSelahStep, completing: GuidedSelahStep) async {
        guard let current = session else { return }
        var completedSteps = current.completedSteps
        if !completedSteps.contains(completing) { completedSteps.append(completing) }

        let updated = GuidedSelahSessionDocument(
            id: current.id, ownerUid: current.ownerUid, verseId: current.verseId,
            translation: current.translation, currentStep: step,
            completedSteps: completedSteps, reflectionId: current.reflectionId,
            cachedStudySheetKey: current.cachedStudySheetKey, recentThemes: current.recentThemes,
            startedAt: current.startedAt, updatedAt: Date(),
            completedAt: step == .complete ? Date() : nil
        )
        await persist(updated)
        if step == .complete { isComplete = true }
        if step == .understand { await loadStudySheetIfNeeded() }
    }

    private func persist(_ doc: GuidedSelahSessionDocument) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.updateSession(doc)
            session = doc
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadStudySheetIfNeeded() async {
        guard studySheetViewModel.studySheet == nil else { return }
        await studySheetViewModel.loadStudySheet(verseId: verseId, translation: translation, verseText: verseText)
    }
}
