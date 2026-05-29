// ContextualExperienceViewModel.swift
// AMENAPP — Multi-Tenant Contextual Experience System
//
// @MainActor view model that bridges ContextualExperienceService to views.
// Uses the real service method signatures defined in ContextualExperienceService.swift.

import SwiftUI
import FirebaseFirestore

// MARK: - ContextualExperienceViewModel

@MainActor
final class ContextualExperienceViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var experiences: [ContextualExperience] = []
    @Published private(set) var selectedExperience: ContextualExperience?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasJoined = false
    @Published private(set) var analytics: ExperienceAnalytics?

    // MARK: - Private

    private let service = ContextualExperienceService.shared
    private var listener: ListenerRegistration?

    // MARK: - Load org experiences

    func loadOrgExperiences(orgId: String, status: ContextualExperienceStatus? = nil) async {
        isLoading = true
        error = nil
        do {
            experiences = try await service.listOrgExperiences(orgId: orgId, status: status)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Load single experience

    func loadExperience(id: String) async {
        isLoading = true
        error = nil
        do {
            selectedExperience = try await service.getExperience(id: id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Join

    func join(experienceId: String) async {
        do {
            try await service.joinExperience(id: experienceId)
            hasJoined = true
            // participantCount is server-owned (let); real count refreshes via listener
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Leave

    func leave(experienceId: String) async {
        do {
            try await service.leaveExperience(id: experienceId)
            hasJoined = false
            // participantCount is server-owned (let); real count refreshes via listener
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Admin: Publish

    func publish(experienceId: String) async {
        do {
            try await service.publishExperience(id: experienceId)
            if let idx = experiences.firstIndex(where: { $0.id == experienceId }) {
                var updated = experiences[idx]
                updated.status = .published
                experiences[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Admin: Unpublish

    func unpublish(experienceId: String) async {
        do {
            try await service.unpublishExperience(id: experienceId)
            if let idx = experiences.firstIndex(where: { $0.id == experienceId }) {
                var updated = experiences[idx]
                updated.status = .draft
                experiences[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Admin: Archive

    func archive(experienceId: String) async {
        do {
            try await service.archiveExperience(id: experienceId)
            if let idx = experiences.firstIndex(where: { $0.id == experienceId }) {
                var updated = experiences[idx]
                updated.status = .archived
                experiences[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Admin: Delete

    func delete(experienceId: String) async {
        do {
            try await service.deleteExperience(id: experienceId)
            experiences.removeAll { $0.id == experienceId }
            if selectedExperience?.id == experienceId { selectedExperience = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Analytics

    func loadAnalytics(experienceId: String) async {
        do {
            analytics = try await service.getAnalytics(experienceId: experienceId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Real-time listener

    func startListening(orgId: String) {
        stopListening()
        listener = service.startListeningToOrgExperiences(orgId: orgId) { [weak self] updated in
            Task { @MainActor [weak self] in
                self?.experiences = updated
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
