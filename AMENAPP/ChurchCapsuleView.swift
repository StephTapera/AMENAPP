// ChurchCapsuleView.swift
// Liquid Glass church name capsule for notes, posts, reflections
// AMENAPP

import SwiftUI

// MARK: - ChurchCapsuleView

struct ChurchCapsuleView: View {

    let churchName: String
    let serviceDate: Date?
    let onTap: (() -> Void)?

    private var formattedDate: String? {
        guard let date = serviceDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"  // e.g. "Sun Apr 6"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "building.columns.fill")
                .font(.systemScaled(9, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(churchName)
                .font(AMENFont.semiBold(11))
                .foregroundStyle(.primary)

            if let dateStr = formattedDate {
                Text("· \(dateStr)")
                    .font(AMENFont.regular(10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
        }
        .contentShape(Capsule())
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        ChurchCapsuleView(
            churchName: "Antioch Church",
            serviceDate: Date(),
            onTap: {}
        )
        ChurchCapsuleView(
            churchName: "Grace Chapel",
            serviceDate: nil,
            onTap: nil
        )
    }
    .padding()
}
#endif
