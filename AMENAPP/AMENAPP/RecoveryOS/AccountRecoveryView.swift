// AccountRecoveryView.swift — AMEN RecoveryOS
// Account recovery: data export, deletion, ban appeals.
// Reachable from Settings → Account Recovery (2 taps from Settings root).
import SwiftUI
import FirebaseAuth

struct AccountRecoveryView: View {
    @StateObject private var service = AccountRecoveryService.shared
    @State private var showDeleteConfirm = false
    @State private var showAppealSheet = false
    @State private var appealText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        List {
            // MARK: Data & Privacy
            Section {
                Button {
                    Task { await requestExport() }
                } label: {
                    Label(service.isExportPending ? "Export Requested…" : "Request Data Export",
                          systemImage: "square.and.arrow.up")
                }
                .disabled(service.isExportPending || uid.isEmpty)
            } header: {
                Text("Data & Privacy")
            } footer: {
                Text("We'll email your full data archive within 72 hours (GDPR Art. 20).")
            }

            // MARK: Ban Appeals
            Section {
                Button {
                    showAppealSheet = true
                } label: {
                    Label(service.appealSubmitted ? "Appeal Submitted" : "Appeal a Suspension",
                          systemImage: "shield.badge.exclamationmark")
                }
                .disabled(service.appealSubmitted || uid.isEmpty)
            } header: {
                Text("Account Standing")
            } footer: {
                Text("Our team reviews all appeals within 5 business days.")
            }

            // MARK: Delete Account (App Store §5.1.1 — ≤3 taps from Settings)
            Section {
                if showDeleteConfirm {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Are you sure? Your account enters a 30-day deletion period. You can cancel by logging back in.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Cancel", role: .cancel) {
                                withAnimation { showDeleteConfirm = false }
                            }
                            .buttonStyle(.bordered)
                            Button("Delete My Account", role: .destructive) {
                                Task { await deleteAccount() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button(role: .destructive) {
                        withAnimation { showDeleteConfirm = true }
                    } label: {
                        Label("Delete Account", systemImage: "person.badge.minus")
                    }
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Deleting your account removes all your data from AMEN servers after a 30-day grace period.")
            }

            if let error = errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }
            if let success = successMessage {
                Section { Text(success).foregroundStyle(.green).font(.caption) }
            }
        }
        .navigationTitle("Account Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAppealSheet) {
            appealSheet
        }
        .disabled(isLoading)
        .overlay { if isLoading { ProgressView() } }
    }

    // MARK: - Appeal Sheet
    @ViewBuilder
    private var appealSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Describe why you believe the suspension was made in error.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $appealText)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                Button("Submit Appeal") {
                    Task { await submitAppeal() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Appeal Suspension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAppealSheet = false }
                }
            }
        }
    }

    // MARK: - Actions
    private func requestExport() async {
        isLoading = true; errorMessage = nil
        do {
            try await service.requestDataExport(uid: uid)
            successMessage = "Export requested — check your email within 72 hours."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func submitAppeal() async {
        isLoading = true; errorMessage = nil
        do {
            try await service.submitBanAppeal(uid: uid, reason: appealText)
            showAppealSheet = false
            successMessage = "Appeal submitted — we'll respond within 5 business days."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteAccount() async {
        isLoading = true; errorMessage = nil
        do {
            try await service.softDeleteAccount(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
