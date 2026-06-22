// AmenTrustedContactService.swift
// AMENAPP
// Manages the user's trusted contact network for safety escalations.

import Foundation
import Combine

@MainActor
final class AmenTrustedContactService: ObservableObject {
    static let shared = AmenTrustedContactService()

    @Published private(set) var contacts: [TrustedContact] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let core = AmenSocialSafetyService.shared

    func loadContacts() async {
        guard AMENFeatureFlags.shared.trustedContactEscalationEnabled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            contacts = try await core.fetchTrustedContacts()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(_ contact: TrustedContact) async throws {
        try await core.addTrustedContact(contact)
        contacts.append(contact)
    }

    func remove(contactId: String) async throws {
        try await core.removeTrustedContact(contactId: contactId)
        contacts.removeAll { $0.id == contactId }
    }

    func hasHighPriorityContact() -> Bool {
        contacts.contains { $0.notificationLevel == .emergencyOnly || $0.notificationLevel == .alerts }
    }
}
