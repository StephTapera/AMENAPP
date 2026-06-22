// IntegrationHealthDashboard.swift — AMEN IntegrationOS
// SwiftUI view showing health status of all registered providers.

import SwiftUI

struct IntegrationHealthDashboard: View {
    @StateObject private var registry = ProviderRegistry.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                if registry.healthReports.isEmpty {
                    ContentUnavailableView(
                        "No Providers Registered",
                        systemImage: "link.badge.plus",
                        description: Text("Connect integrations to see health status.")
                    )
                } else {
                    ForEach(registry.healthReports, id: \.id) { report in
                        HealthReportRow(report: report)
                    }
                }
            }
            .navigationTitle("Integration Health")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView().tint(.primary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .task { await refresh() }
        }
    }

    private func refresh() async {
        isRefreshing = true
        await registry.refreshHealth()
        isRefreshing = false
    }
}

private struct HealthReportRow: View {
    let report: ProviderHealthReport
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.providerId.capitalized)
                    .font(.subheadline.weight(.semibold))
                if let msg = report.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(report.status.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
                if let ms = report.latencyMs {
                    Text("\(ms)ms")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch report.status {
        case .healthy:      return .green
        case .degraded:     return .orange
        case .unavailable:  return .red
        case .unauthorized: return .yellow
        }
    }
}
