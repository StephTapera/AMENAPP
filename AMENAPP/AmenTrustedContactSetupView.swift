// AmenTrustedContactSetupView.swift
// AMENAPP
// Lets the user add/manage trusted contacts for safety escalations.

import SwiftUI

struct TrustedContactSetupView: View {
    @StateObject private var service = AmenTrustedContactService.shared
    @State private var showAddSheet = false

    var body: some View {
        List {
            if service.contacts.isEmpty {
                ContentUnavailableView(
                    "No Trusted Contacts",
                    systemImage: "person.badge.shield.checkmark",
                    description: Text("Add trusted friends or family who can be notified if you need help.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(service.contacts) { contact in
                    SetupTrustedContactRow(contact: contact) {
                        Task { try? await service.remove(contactId: contact.id.uuidString) }
                    }
                }
            }
        }
        .navigationTitle("Trusted Contacts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            SetupAddTrustedContactSheet()
        }
        .task { await service.loadContacts() }
        .overlay {
            if service.isLoading {
                ProgressView()
            }
        }
    }
}

// MARK: - Row

private struct SetupTrustedContactRow: View {
    let contact: TrustedContact
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: contact.avatarURL.flatMap(URL.init)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.accentColor.opacity(0.2))
                    .overlay(
                        Text(contact.displayName.prefix(1).uppercased())
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.accentColor)
                    )
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body.bold())
                Text(contact.relationshipType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: contact.notificationLevel.icon)
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Sheet

private struct SetupAddTrustedContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedRelationship = TrustedContactRelationshipType.friend
    @State private var selectedNotificationLevel = TrustedContactNotificationLevel.alerts

    var body: some View {
        NavigationStack {
            Form {
                Section("Find Contact") {
                    TextField("Search by username\u{2026}", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Relationship") {
                    Picker("Type", selection: $selectedRelationship) {
                        ForEach(TrustedContactRelationshipType.allCases, id: \.self) { rel in
                            Text(rel.displayName).tag(rel)
                        }
                    }
                }

                Section("Notify Them") {
                    Picker("When", selection: $selectedNotificationLevel) {
                        ForEach(TrustedContactNotificationLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }
            }
            .navigationTitle("Add Trusted Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        // In production: resolve searchText → userId via Algolia/Firestore
                        dismiss()
                    }
                    .disabled(searchText.isEmpty)
                }
            }
        }
    }
}

// MARK: - Display helpers

private extension TrustedContactRelationshipType {
    var displayName: String {
        switch self {
        case .parent: return "Parent"
        case .guardian: return "Guardian"
        case .sibling: return "Sibling"
        case .friend: return "Friend"
        case .mentor: return "Mentor"
        case .pastor: return "Pastor"
        case .counselor: return "Counselor"
        case .spouse: return "Spouse"
        case .other: return "Other"
        }
    }
}

private extension TrustedContactNotificationLevel {
    var displayName: String {
        switch self {
        case .all: return "All activity"
        case .alerts: return "Safety alerts only"
        case .emergencyOnly: return "Emergencies only"
        }
    }

    var icon: String {
        switch self {
        case .all: return "bell.fill"
        case .alerts: return "exclamationmark.triangle"
        case .emergencyOnly: return "sos"
        }
    }
}
