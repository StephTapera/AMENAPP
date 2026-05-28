import SwiftUI

struct AmenConnectedAppsView: View {
    @StateObject private var service = AmenIntegrationsService()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(spacing: 12) {
                    ForEach(service.accountCards) { account in
                        AmenIntegrationConnectionCard(
                            account: account,
                            isLoading: service.isLoading,
                            onConnect: { Task { await service.connect(provider: account.provider) } },
                            onDisconnect: { Task { await service.revoke(account: account) } }
                        )
                    }
                }

                AmenIntegrationContinuityPanel()

                if let errorMessage = service.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(surfaceBackground(cornerRadius: 18))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("Connected Apps")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await service.refreshAccounts() }
                } label: {
                    Image(systemName: service.isLoading ? "hourglass" : "arrow.clockwise")
                }
                .accessibilityLabel("Refresh integrations")
            }
        }
        .task { await service.refreshAccounts() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Amen Integrations Platform", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Connect meeting, calendar, and ministry tools so AMEN can coordinate gatherings without exposing provider tokens on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceBackground(cornerRadius: 24))
    }

    @ViewBuilder
    private func surfaceBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(reduceTransparency ? Color(.secondarySystemBackground) : Color.white.opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(reduceMotion ? 0.04 : 0.08), radius: reduceMotion ? 8 : 18, x: 0, y: 8)
    }
}

private struct AmenIntegrationConnectionCard: View {
    let account: AmenIntegrationAccountSummary
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isConnected: Bool { account.status == .connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: account.provider.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.primary.opacity(0.06)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(account.provider.title)
                        .font(.headline)
                    Text(account.workspaceName ?? account.provider.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(account.status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isConnected ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill((isConnected ? Color.green : Color.secondary).opacity(0.12)))
            }

            HStack(spacing: 10) {
                if isConnected {
                    Button(role: .destructive, action: onDisconnect) {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onConnect) {
                        Label("Connect", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(scopeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reduceTransparency ? Color(.secondarySystemBackground) : Color.white.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .disabled(isLoading)
        .accessibilityElement(children: .combine)
    }

    private var scopeSummary: String {
        if account.scopes.isEmpty { return "Server-managed OAuth. No provider secrets live on-device." }
        return account.scopes.prefix(3).joined(separator: ", ")
    }
}

private struct AmenIntegrationContinuityPanel: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Spiritual continuity", systemImage: "sparkles.rectangle.stack")
                .font(.headline)
            Text("Meeting links, calendar events, reminders, and follow-up records are created through AMEN's server boundary. Berean can suggest agendas and follow-ups only from verified AMEN meeting context.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                AmenIntegrationCapabilityPill(title: "Prayer groups", symbol: "hands.sparkles")
                AmenIntegrationCapabilityPill(title: "Bible studies", symbol: "book.closed")
                AmenIntegrationCapabilityPill(title: "Follow-up", symbol: "checklist")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(reduceTransparency ? Color(.secondarySystemBackground) : Color.white.opacity(0.70))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private struct AmenIntegrationCapabilityPill: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

#Preview {
    NavigationStack {
        AmenConnectedAppsView()
    }
}
