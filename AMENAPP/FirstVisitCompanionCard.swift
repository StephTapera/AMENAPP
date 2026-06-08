// FirstVisitCompanionCard.swift
// Optional first-visit guidance card for church detail
// AMENAPP

import SwiftUI

// MARK: - ChurchMetadataRow

struct ChurchMetadataRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - FirstVisitCompanionCard

struct FirstVisitCompanionCard: View {

    let churchName: String
    let parkingInfo: String?
    let entranceInfo: String?
    let kidsCheckIn: Bool
    let expectedDurationMinutes: Int?
    let serviceStyle: String?
    let accessibilityFeatures: [String]

    // Guard: nothing to show — return EmptyView
    private var hasContent: Bool {
        parkingInfo != nil ||
        entranceInfo != nil ||
        kidsCheckIn ||
        expectedDurationMinutes != nil ||
        serviceStyle != nil ||
        !accessibilityFeatures.isEmpty
    }

    private var durationLabel: String? {
        guard let mins = expectedDurationMinutes else { return nil }
        if mins < 60 {
            return "\(mins) min service"
        } else {
            let hours = mins / 60
            let remaining = mins % 60
            return remaining > 0 ? "\(hours)h \(remaining)min" : "\(hours) hour service"
        }
    }

    private var accessibilityLabel: String? {
        guard !accessibilityFeatures.isEmpty else { return nil }
        return accessibilityFeatures.joined(separator: " · ")
    }

    var body: some View {
        if !hasContent {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("First Visit Guide")
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                }

                Divider()
                    .opacity(0.4)

                VStack(alignment: .leading, spacing: 12) {
                    if let parking = parkingInfo {
                        ChurchMetadataRow(icon: "car.fill", label: "Parking", value: parking)
                    }

                    if let entrance = entranceInfo {
                        ChurchMetadataRow(icon: "door.right.hand.open", label: "Entrance", value: entrance)
                    }

                    if kidsCheckIn {
                        ChurchMetadataRow(
                            icon: "figure.2.and.child.holdinghands",
                            label: "Kids",
                            value: "Kids check-in available"
                        )
                    }

                    if let duration = durationLabel {
                        ChurchMetadataRow(icon: "clock.fill", label: "Duration", value: duration)
                    }

                    if let style = serviceStyle {
                        ChurchMetadataRow(icon: "music.note", label: "Service Style", value: style)
                    }

                    if let accessibility = accessibilityLabel {
                        ChurchMetadataRow(icon: "figure.roll", label: "Accessibility", value: accessibility)
                    }
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
            }
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    FirstVisitCompanionCard(
        churchName: "Grace Chapel",
        parkingInfo: "Free parking on north side of building",
        entranceInfo: "Main entrance faces Oak Street",
        kidsCheckIn: true,
        expectedDurationMinutes: 75,
        serviceStyle: "Contemporary worship",
        accessibilityFeatures: ["Wheelchair accessible", "Hearing loop"]
    )
    .padding()
}
#endif
