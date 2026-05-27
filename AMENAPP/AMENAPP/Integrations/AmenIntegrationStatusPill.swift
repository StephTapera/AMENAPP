// AmenIntegrationStatusPill.swift
// Connection status pill — white background, black typography, Liquid Glass not used here

import SwiftUI

struct AmenIntegrationStatusPill: View {
    let status: AmenIntegrationStatus

    var body: some View {
        Text(status.displayLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel("Connection status: \(status.displayLabel)")
    }

    private var foregroundColor: Color {
        switch status {
        case .connected: return Color(red: 0.08, green: 0.50, blue: 0.22) // dark green
        case .expired, .error: return Color(red: 0.80, green: 0.20, blue: 0.10) // dark red
        case .pending: return Color(red: 0.45, green: 0.35, blue: 0.80)
        case .revoked, .notConnected: return .secondary
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .connected: return Color(red: 0.90, green: 0.97, blue: 0.92)
        case .expired, .error: return Color(red: 0.98, green: 0.91, blue: 0.90)
        case .pending: return Color(red: 0.93, green: 0.90, blue: 0.98)
        case .revoked, .notConnected: return Color(.systemGray6)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AmenIntegrationStatusPill(status: .connected)
        AmenIntegrationStatusPill(status: .expired)
        AmenIntegrationStatusPill(status: .notConnected)
        AmenIntegrationStatusPill(status: .pending)
    }
    .padding()
}
