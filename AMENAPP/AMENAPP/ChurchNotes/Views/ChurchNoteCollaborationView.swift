import SwiftUI

struct ChurchNoteCollaborationView: View {
    let noteId: String
    let currentRole: ChurchNoteCollaboratorRole
    @ObservedObject var service: ChurchNotesCollaborationService
    @Environment(\.dismiss) private var dismiss

    @State private var collaboratorUid = ""
    @State private var selectedRole: ChurchNoteCollaboratorRole = .viewer

    private var canManage: Bool { currentRole == .owner }

    var body: some View {
        NavigationStack {
            List {
                Section("Presence") {
                    if service.presence.isEmpty {
                        Text("No one else is viewing this note.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(service.presence) { person in
                            HStack {
                                Image(systemName: person.isEditing ? "pencil.circle.fill" : "eye.circle.fill")
                                    .foregroundStyle(person.isEditing ? .green : .secondary)
                                VStack(alignment: .leading) {
                                    Text(person.displayName)
                                    Text(person.role.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(person.displayName), \(person.role.displayName)")
                        }
                    }
                }

                Section("Collaborators") {
                    if service.isLoading {
                        ProgressView("Loading collaborators")
                    } else if service.collaborators.isEmpty {
                        ContentUnavailableView("No collaborators", systemImage: "person.2", description: Text("Share this note to add trusted people."))
                    } else {
                        ForEach(service.collaborators) { collaborator in
                            collaboratorRow(collaborator)
                        }
                    }
                }

                Section("Add Collaborator") {
                    TextField("User ID", text: $collaboratorUid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(!canManage || service.isLoading)
                    Picker("Role", selection: $selectedRole) {
                        ForEach(ChurchNoteCollaboratorRole.allCases.filter { $0 != .owner }) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    Button {
                        Task {
                            await service.share(noteId: noteId, collaboratorUid: collaboratorUid, role: selectedRole)
                            collaboratorUid = ""
                        }
                    } label: {
                        Label("Share Note", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!canManage || collaboratorUid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isLoading)
                }

                if let error = service.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if !canManage {
                    Section {
                        Label("Only the owner can manage collaborators.", systemImage: "lock")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Collaboration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .background(Color(.systemBackground))
        }
    }

    private func collaboratorRow(_ collaborator: ChurchNoteCollaborator) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(collaborator.displayName)
                Text(collaborator.uid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if canManage {
                Menu {
                    ForEach(ChurchNoteCollaboratorRole.allCases.filter { $0 != .owner }) { role in
                        Button(role.displayName) {
                            Task { await service.updateRole(noteId: noteId, collaboratorUid: collaborator.uid, role: role) }
                        }
                    }
                    Button("Remove", role: .destructive) {
                        Task { await service.remove(noteId: noteId, collaboratorUid: collaborator.uid) }
                    }
                } label: {
                    Label(collaborator.role.displayName, systemImage: "chevron.up.chevron.down")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(service.isLoading)
            } else {
                Text(collaborator.role.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collaborator.displayName), \(collaborator.role.displayName)")
    }
}
