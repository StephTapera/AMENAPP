// AmenAIMediaDisclosureView.swift
// AMENAPP
// Badge / banner that discloses AI-generated, AI-assisted, or AI-enhanced media.

import SwiftUI

struct AmenAIMediaDisclosureView: View {
    enum DisclosureLevel {
        case generated, assisted, enhanced

        var subtitle: String {
            switch self {
            case .generated: return "This media was fully created by AI."
            case .assisted:  return "AI assisted in creating this content."
            case .enhanced:  return "AI tools were used to enhance this content."
            }
        }
    }

    let level: DisclosureLevel
    var compact: Bool = false

    var body: some View {
        guard AMENFeatureFlags.shared.aiMediaDisclosureEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(compact ? AnyView(pill) : AnyView(banner))
    }

    // MARK: Compact pill

    private var pill: some View {
        Text("✦ AI")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: 22)
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                    )
            )
            .accessibilityLabel("AI-generated content")
    }

    // MARK: Banner

    private var banner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI-Generated Media")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(level.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Learn more") {
                NotificationCenter.default.post(name: .openAIMediaEducation, object: nil)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI-Generated Media. \(level.subtitle)")
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let openAIMediaEducation = Notification.Name("openAIMediaEducation")
}

// MARK: - View extension

extension View {
    /// Overlays a compact AI disclosure pill at the top-trailing corner.
    func aiMediaDisclosure(_ level: AmenAIMediaDisclosureView.DisclosureLevel) -> some View {
        overlay(alignment: .topTrailing) {
            AmenAIMediaDisclosureView(level: level, compact: true)
                .padding(6)
        }
    }
}
