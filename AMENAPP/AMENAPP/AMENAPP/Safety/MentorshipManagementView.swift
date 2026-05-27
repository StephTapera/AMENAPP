import SwiftUI

// MARK: - MentorshipManagementView
// Lets users view, request, approve, and end mentorship connections.

struct MentorshipManagementView: View {
    @State private var connections: [MentorshipConnection] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var showRequestSheet = false
    @State private var actionError: String? = nil

    private let safety = AmenSafetyOSClientService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading mentorships…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ContentUnavailableView(
                        "Couldn't Load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if connections.isEmpty {
                    emptyState
                } else {
                    connectionList
                }
            }
            .navigationTitle("Mentorship")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRequestSheet = true
                    } label: {
                        Label("Request", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showRequestSheet) {
                RequestMentorshipSheet { mentorUid, context in
                    await requestMentorship(mentorUid: mentorUid, context: context)
                }
            }
            .task { await loadConnections() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Mentorships Yet",
            systemImage: "figure.wave",
            description: Text("Connect with a trusted mentor or offer guidance to someone new in the faith.")
        )
    }

    private var connectionList: some View {
        List {
            let active = connections.filter { $0.status == "active" }
            let pending = connections.filter { $0.status == "pending" }

            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { connection in
                        MentorshipConnectionRow(connection: connection) {
                            await endMentorship(connectionId: connection.id)
                        } onApprove: {
                            await approveMentorship(connectionId: connection.id)
                        }
                    }
                }
            }
            if !pending.isEmpty {
                Section("Pending Approval") {
                    ForEach(pending) { connection in
                        MentorshipConnectionRow(connection: connection) {
                            await endMentorship(connectionId: connection.id)
                        } onApprove: {
                            await approveMentorship(connectionId: connection.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func loadConnections() async {
        isLoading = true
        loadError = nil
        do {
            let result = try await safety.getMyMentorships()
            connections = result.connections
        } catch {
            loadError = "Couldn't load connections. Please try again."
        }
        isLoading = false
    }

    private func requestMentorship(mentorUid: String, context: String?) async {
        do {
            _ = try await safety.requestMentorship(mentorUid: mentorUid, context: context)
            await loadConnections()
        } catch {
            actionError = "Couldn't send request. Please try again."
        }
    }

    private func approveMentorship(connectionId: String) async {
        do {
            _ = try await safety.approveMentorship(connectionId: connectionId)
            await loadConnections()
        } catch {
            actionError = "Couldn't approve. Please try again."
        }
    }

    private func endMentorship(connectionId: String) async {
        do {
            _ = try await safety.endMentorship(connectionId: connectionId)
            await loadConnections()
        } catch {
            actionError = "Couldn't end connection. Please try again."
        }
    }
}

// MARK: - Row

private struct MentorshipConnectionRow: View {
    let connection: MentorshipConnection
    let onEnd: () async -> Void
    let onApprove: () async -> Void

    @State private var isActing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.status == "pending" ? "Request Pending" : "Active Connection")
                        .font(.subheadline.bold())
                    Text(connection.mentorUid == connection.menteeUid ? "Self" :
                         "With: \(connection.mentorUid.prefix(12))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }
            if let context = connection.context, !context.isEmpty {
                Text(context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if connection.status == "pending" {
                    Button("Approve") {
                        isActing = true
                        Task {
                            await onApprove()
                            isActing = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isActing)
                }
                Button("End") {
                    isActing = true
                    Task {
                        await onEnd()
                        isActing = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)
                .disabled(isActing)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(connection.status.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(connection.status == "active" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15),
                        in: Capsule())
            .foregroundStyle(connection.status == "active" ? .green : .orange)
    }
}

// MARK: - Request Sheet

private struct RequestMentorshipSheet: View {
    let onRequest: (String, String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mentorUid = ""
    @State private var context = ""
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mentor") {
                    TextField("Mentor's user ID", text: $mentorUid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Context (optional)") {
                    TextEditor(text: $context)
                        .frame(minHeight: 80)
                }
                Section {
                    Text("Mentorship is a two-way commitment. Your request will be sent to the mentor for approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Request Mentorship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isRequesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Send") {
                            isRequesting = true
                            Task {
                                await onRequest(mentorUid.trimmingCharacters(in: .whitespacesAndNewlines),
                                                context.isEmpty ? nil : context)
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(mentorUid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}
