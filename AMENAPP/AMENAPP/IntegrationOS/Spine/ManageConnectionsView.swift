// ManageConnectionsView.swift — AMEN IntegrationOS
// SwiftUI list of connected providers with revoke capability.

import SwiftUI

struct ManageConnectionsView: View {
    @StateObject private var registry = ProviderRegistry.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var revokeTarget: String?
    @State private var showRevokeConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if registry.adapters.isEmpty {
                    ContentUnavailableView(
                        "No Active Connections",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text("Connect apps and services to expand AMEN's capabilities.")
                    )
                } else {
                    Section("Active Connections") {
                        ForEach(Array(registry.adapters.keys).sorted(), id: \.self) { providerId in
                            ConnectionRow(
                                providerId: providerId,
                                adapter: registry.adapters[providerId]
                            ) {
                                revokeTarget = providerId
                                showRevokeConfirm = true
                            }
                        }
                    }
                }

                Section {
                    NavigationLink("View Integration Health") {
                        IntegrationHealthDashboard()
                    }
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog(
                "Revoke \(revokeTarget?.capitalized ?? "Connection")?",
                isPresented: $showRevokeConfirm,
                titleVisibility: .visible
            ) {
                Button("Revoke Access", role: .destructive) {
                    guard let target = revokeTarget else { return }
                    Task {
                        if let adapter = registry.adapters[target] {
                            try? await adapter.revoke()
                        }
                        await MainActor.run { registry.unregister(providerId: target) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all permissions for this provider. You can reconnect later.")
            }
        }
    }
}

private struct ConnectionRow: View {
    let providerId: String
    let adapter: (any ProviderAdapter)?
    let onRevoke: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(providerId.capitalized)
                    .font(.subheadline.weight(.semibold))
                if let caps = adapter?.capabilities {
                    Text(capsDescription(caps))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onRevoke()
            } label: {
                Text("Revoke")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func capsDescription(_ caps: ProviderCapabilitySet) -> String {
        var parts: [String] = []
        if caps.contains(.maps)      { parts.append("Maps") }
        if caps.contains(.calendar)  { parts.append("Calendar") }
        if caps.contains(.contacts)  { parts.append("Contacts") }
        if caps.contains(.media)     { parts.append("Media") }
        if caps.contains(.health)    { parts.append("Health") }
        if caps.contains(.messaging) { parts.append("Messaging") }
        if caps.contains(.events)    { parts.append("Events") }
        if caps.contains(.transport) { parts.append("Transport") }
        if caps.contains(.knowledge) { parts.append("Knowledge") }
        if caps.contains(.career)    { parts.append("Career") }
        return parts.joined(separator: ", ")
    }
}
