// AmenIntegrationProviderCard.swift
// Provider connection card — white background, black type, native iOS controls

import SwiftUI

struct AmenIntegrationProviderCard: View {
    let provider: AmenIntegrationProvider
    let status: AmenIntegrationStatus
    let connection: AmenIntegrationConnection?
    let isActionInProgress: Bool
    let onConnect: () -> Void
    let onReconnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 12) {
                providerIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let email = connection?.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let workspace = connection?.workspaceName {
                        Text(workspace)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(provider.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                AmenIntegrationStatusPill(status: status)
            }
            .padding(16)

            // Capability chips
            if status == .connected {
                capabilityRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider()
                .padding(.horizontal, 16)

            // Action row
            actionRow
                .padding(16)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private var providerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
                .frame(width: 44, height: 44)
            Image(systemName: provider.systemIconFallback)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var capabilityRow: some View {
        HStack(spacing: 8) {
            if provider.supportsGatherings {
                capabilityChip(icon: "video.fill", label: "Meetings")
            }
            if provider.supportsNotifications {
                capabilityChip(icon: "bell.fill", label: "Notifications")
            }
            capabilityChip(icon: "calendar", label: "Calendar")
        }
    }

    private func capabilityChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6), in: Capsule())
    }

    @ViewBuilder
    private var actionRow: some View {
        if isActionInProgress {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Working…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Processing")
        } else {
            switch status {
            case .notConnected, .revoked:
                Button(action: onConnect) {
                    Label("Connect", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityLabel("Connect \(provider.displayName)")

            case .expired, .error:
                HStack {
                    Button(action: onReconnect) {
                        Label("Reconnect", systemImage: "arrow.clockwise.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.orange)
                    Spacer()
                    Button(action: onDisconnect) {
                        Text("Remove")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .contain)

            case .connected:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Active")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onDisconnect) {
                        Text("Disconnect")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

            case .pending:
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Connecting…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            AmenIntegrationProviderCard(
                provider: .microsoft,
                status: .connected,
                connection: AmenIntegrationConnection(
                    accountId: "uid_microsoft", provider: .microsoft,
                    status: .connected, isOrgLevel: false,
                    displayName: "Steph Tapera", email: "steph@example.com",
                    workspaceName: nil, connectedAt: nil, expiresAt: nil
                ),
                isActionInProgress: false,
                onConnect: {}, onReconnect: {}, onDisconnect: {}
            )
            AmenIntegrationProviderCard(
                provider: .zoom, status: .notConnected, connection: nil,
                isActionInProgress: false,
                onConnect: {}, onReconnect: {}, onDisconnect: {}
            )
            AmenIntegrationProviderCard(
                provider: .slack, status: .expired, connection: nil,
                isActionInProgress: false,
                onConnect: {}, onReconnect: {}, onDisconnect: {}
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
