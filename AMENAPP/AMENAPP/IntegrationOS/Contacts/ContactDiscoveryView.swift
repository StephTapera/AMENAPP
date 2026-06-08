// ContactDiscoveryView.swift — AMEN IntegrationOS
// SwiftUI view for contact-hashed friend discovery.

import SwiftUI
import Contacts

@MainActor
final class ContactDiscoveryViewModel: ObservableObject {
    @Published var matches: [ContactMatch] = []
    @Published var isLoading = false
    @Published var hasContactAccess = false
    @Published var errorMessage: String?
    @Published var pendingIntros: [IntroductionRequest] = []

    private let discoveryService = ContactDiscoveryService.shared
    private let introService = SafeIntroductionService.shared

    func checkAndDiscover() async {
        isLoading = true
        errorMessage = nil
        do {
            try await discoveryService.requestAccess()
            hasContactAccess = true
            matches = try await discoveryService.discoverContacts()
            pendingIntros = (try? await introService.fetchPendingIntroductions()) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ContactDiscoveryView: View {
    @StateObject private var viewModel = ContactDiscoveryViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasContactAccess {
                    permissionPrompt
                } else if viewModel.isLoading {
                    ProgressView("Finding friends…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    matchList
                }
            }
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.checkAndDiscover() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.circle.fill")
                .font(.systemScaled(56))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Find Friends on AMEN")
                    .font(.title2.weight(.bold))
                Text("Your contacts are hashed locally. AMEN never sees your contacts list — only cryptographic fingerprints are compared.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                Task { await viewModel.checkAndDiscover() }
            } label: {
                Text("Find Friends")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private var matchList: some View {
        List {
            if !viewModel.pendingIntros.isEmpty {
                Section("Pending Introductions (\(viewModel.pendingIntros.count))") {
                    ForEach(viewModel.pendingIntros) { intro in
                        PendingIntroRow(intro: intro)
                    }
                }
            }

            Section("People You May Know") {
                if viewModel.matches.isEmpty {
                    Text("No matches found yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.matches) { match in
                        ContactMatchRow(match: match)
                    }
                }
            }
        }
        .refreshable { await viewModel.checkAndDiscover() }
    }
}

private struct ContactMatchRow: View {
    let match: ContactMatch
    @Environment(\.colorScheme) private var colorScheme
    @State private var requested = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(match.displayName.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(match.displayName)
                    .font(.subheadline.weight(.semibold))
                if match.mutualConnectionCount > 0 {
                    Text("\(match.mutualConnectionCount) mutual connection\(match.mutualConnectionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !match.alreadyFollowing {
                Button {
                    requested = true
                } label: {
                    Text(requested ? "Requested" : "Connect")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(requested ? Color(.systemGray5) : Color.accentColor)
                        .foregroundStyle(requested ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white))
                        .clipShape(Capsule())
                }
                .disabled(requested)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PendingIntroRow: View {
    let intro: IntroductionRequest
    @State private var responded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Introduction Request")
                .font(.subheadline.weight(.semibold))
            if let msg = intro.message {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
            if !responded {
                HStack(spacing: 12) {
                    Button("Accept") {
                        Task {
                            try? await SafeIntroductionService.shared.respond(requestId: intro.id, accept: true)
                            responded = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Decline", role: .destructive) {
                        Task {
                            try? await SafeIntroductionService.shared.respond(requestId: intro.id, accept: false)
                            responded = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Text("Response sent").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
