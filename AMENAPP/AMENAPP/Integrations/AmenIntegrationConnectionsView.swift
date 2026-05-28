// AmenIntegrationConnectionsView.swift
// Connected Apps screen — shows all provider cards + connection management
// Feature-gated: amenIntegrationsEnabled must be true

import SwiftUI

struct AmenIntegrationConnectionsView: View {
    @StateObject private var vm = AmenIntegrationViewModel()
    @EnvironmentObject private var flags: AMENFeatureFlags
    @State private var showOAuthFor: AmenIntegrationProvider?

    var body: some View {
        Group {
            if !flags.amenIntegrationsEnabled {
                unavailableView
            } else {
                contentView
            }
        }
        .navigationTitle("Connected Apps")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.loadConnections() }
        .refreshable { await vm.loadConnections() }
        .sheet(item: $showOAuthFor) { provider in
            AmenIntegrationOAuthView(provider: provider, viewModel: vm)
        }
        .confirmationDialog(
            disconnectTitle,
            isPresented: $vm.showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    if let p = vm.providerToDisconnect { await vm.disconnect(provider: p) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the connection from AMEN. You can reconnect at any time.")
        }
    }

    // MARK: - Main Content

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let error = vm.error {
                    errorBanner(error)
                        .padding(.horizontal)
                        .padding(.top, 16)
                }

                headerSection
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                LazyVStack(spacing: 12) {
                    ForEach(vm.sortedProviders) { provider in
                        AmenIntegrationProviderCard(
                            provider: provider,
                            status: vm.status(for: provider),
                            connection: vm.connection(for: provider),
                            isActionInProgress: vm.actionInProgress == provider,
                            onConnect: { showOAuthFor = provider },
                            onReconnect: { showOAuthFor = provider },
                            onDisconnect: { vm.confirmDisconnect(provider: provider) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if vm.isLoading && vm.connections.isEmpty {
                loadingOverlay
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect your tools")
                .font(.headline)
            Text("Link Microsoft 365, Zoom, or Slack to schedule gatherings, send meeting links, and notify your ministry team — without leaving AMEN.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBanner(_ error: AmenIntegrationClientError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(error.errorDescription ?? "Something went wrong.")
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Button { vm.clearError() } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.errorDescription ?? "")")
    }

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading connections…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Loading connections")
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "Integrations Coming Soon",
            systemImage: "puzzlepiece.extension.fill",
            description: Text("Connect Microsoft 365, Zoom, and Slack to AMEN. This feature will be available soon.")
        )
    }

    private var disconnectTitle: String {
        guard let provider = vm.providerToDisconnect else { return "Disconnect" }
        return "Disconnect \(provider.displayName)?"
    }
}

#Preview {
    NavigationStack {
        AmenIntegrationConnectionsView()
            .environmentObject(AMENFeatureFlags.shared)
    }
}
