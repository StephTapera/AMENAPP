import SwiftUI

// MARK: - GuardianDashboardView
// Parent/guardian dashboard for family mode.
// Lets guardians view their linked minor accounts and manage connections.

struct GuardianDashboardView: View {
    @State private var showConnectSheet = false

    private let safety = AmenSafetyOSClientService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FamilyModeInfoBanner()
                }
                Section("Guardian Actions") {
                    Button {
                        showConnectSheet = true
                    } label: {
                        Label("Link a Minor Account", systemImage: "person.badge.plus")
                    }
                }
                Section {
                    NavigationLink {
                        GuardianConnectionsView()
                    } label: {
                        Label("Manage Connections", systemImage: "person.2.fill")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Family Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showConnectSheet) {
                RequestGuardianConnectionSheet { minorUid in
                    await requestConnection(minorUid: minorUid)
                }
            }
        }
    }

    private func requestConnection(minorUid: String) async {
        _ = try? await safety.requestGuardianConnection(minorUid: minorUid)
    }
}

// MARK: - Guardian Connections View

private struct GuardianConnectionsView: View {
    var body: some View {
        ContentUnavailableView(
            "No Linked Accounts",
            systemImage: "person.2",
            description: Text("Use the dashboard to link a minor account.")
        )
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Family Mode Info Banner

private struct FamilyModeInfoBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "house.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Family Mode")
                    .font(.subheadline.bold())
                Text("Family mode provides a parent-linked, youth-safe environment. Minor accounts require guardian approval for certain interactions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Request Guardian Connection Sheet

private struct RequestGuardianConnectionSheet: View {
    let onRequest: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minorUid = ""
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Minor's Account") {
                    TextField("User ID", text: $minorUid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("The minor will receive a request notification. Both parties must confirm the connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Link Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isRequesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Send Request") {
                            isRequesting = true
                            Task {
                                await onRequest(minorUid.trimmingCharacters(in: .whitespacesAndNewlines))
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(minorUid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}
