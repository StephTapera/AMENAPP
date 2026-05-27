import SwiftUI

// MARK: - ChurchVerificationView
// 6-digit church verification code entry flow.
// Trust point reward: church_connection_verified (+20 pts) granted server-side.

struct ChurchVerificationView: View {
    @State private var verifiedChurches: [VerifiedChurch] = []
    @State private var isLoading = true
    @State private var showVerifySheet = false
    @State private var errorMessage: String? = nil

    private let safety = AmenSafetyOSClientService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    churchList
                }
            }
            .navigationTitle("Church Verification")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showVerifySheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showVerifySheet) {
                ChurchVerificationEntrySheet { churchId, code in
                    await verifyChurch(churchId: churchId, code: code)
                }
            }
            .task { await loadStatus() }
            .alert("Verification Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var churchList: some View {
        List {
            if !verifiedChurches.isEmpty {
                Section("Verified Churches") {
                    ForEach(verifiedChurches) { church in
                        HStack(spacing: 12) {
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(church.churchName)
                                    .font(.body)
                                Text("Verified")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How it works")
                            .font(.subheadline.bold())
                        Text("Ask your church admin for a 6-digit verification code. Enter it here to confirm your membership and earn +20 trust points.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if verifiedChurches.isEmpty {
                ContentUnavailableView(
                    "No Verified Churches",
                    systemImage: "building.2",
                    description: Text("Tap + to verify your church membership.")
                )
            }
        }
    }

    private func loadStatus() async {
        isLoading = true
        do {
            let result = try await safety.getChurchVerificationStatus()
            verifiedChurches = result.verifiedChurches
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func verifyChurch(churchId: String, code: String) async {
        do {
            _ = try await safety.requestChurchVerification(churchId: churchId, verificationCode: code)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Code Entry Sheet

private struct ChurchVerificationEntrySheet: View {
    let onVerify: (String, String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var churchId = ""
    @State private var code = ""
    @State private var isVerifying = false
    @State private var verifyError: String? = nil
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Church") {
                    TextField("Church ID", text: $churchId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Verification Code") {
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { i in
                            CodeDigitBox(
                                digit: i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : "",
                                isActive: code.count == i
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture { codeFocused = true }
                    .overlay {
                        TextField("", text: $code)
                            .keyboardType(.numberPad)
                            .focused($codeFocused)
                            .opacity(0.01)
                            .onChange(of: code) { _, newValue in
                                code = String(newValue.filter(\.isNumber).prefix(6))
                            }
                    }
                }
                if let error = verifyError {
                    Section {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Enter Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isVerifying {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Verify") {
                            isVerifying = true
                            verifyError = nil
                            Task {
                                do {
                                    await onVerify(
                                        churchId.trimmingCharacters(in: .whitespacesAndNewlines),
                                        code
                                    )
                                    dismiss()
                                }
                                isVerifying = false
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(code.count != 6 || churchId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { codeFocused = true }
        }
    }
}

private struct CodeDigitBox: View {
    let digit: String
    let isActive: Bool

    var body: some View {
        Text(digit.isEmpty ? " " : digit)
            .font(.title2.bold())
            .frame(width: 44, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isActive ? 2 : 1)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            )
            .animation(.spring(response: 0.2), value: isActive)
    }
}
