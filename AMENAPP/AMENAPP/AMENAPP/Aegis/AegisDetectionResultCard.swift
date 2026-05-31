// AegisDetectionResultCard.swift
// AMENAPP — Aegis/
//
// Reusable card displaying a single AegisDetectionResult inside the
// pre-post review sheet. Non-punitive, pastoral tone throughout.
//
// Design contracts honoured:
//   - .amenGlass(.regular) for the glass surface
//   - AmenTheme color tokens only (no system blue)
//   - Motion.adaptive(_:) with reduce-motion env check
//   - AMENFont type scale
//   - Full VoiceOver label combining capability + severity + action

import SwiftUI

// MARK: - AegisDetectionResultCard

struct AegisDetectionResultCard: View {

    let result: AegisDetectionResult
    var isAcknowledged: Bool = false
    var onAcknowledge: (() -> Void)? = nil

    // MARK: Environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    // MARK: Computed helpers

    private var severityIcon: String {
        switch result.severity {
        case .info:    return "info.circle"
        case .caution: return "exclamationmark.triangle"
        case .warn:    return "exclamationmark.triangle.fill"
        case .block:   return "xmark.octagon.fill"
        }
    }

    private var severityColor: Color {
        switch result.severity {
        case .info:    return AmenTheme.Colors.amenBlue
        case .caution: return AmenTheme.Colors.amenGold
        case .warn:    return .orange
        case .block:   return .red
        }
    }

    private var severityLabel: String {
        switch result.severity {
        case .info:    return "Info"
        case .caution: return "Caution"
        case .warn:    return "Warning"
        case .block:   return "Blocked"
        }
    }

    private var confidenceText: String {
        let pct = Int((result.confidence * 100).rounded())
        return "\(pct)% confidence"
    }

    // MARK: Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // ── Left: severity icon ──────────────────────────────────
            severityIconView

            // ── Right: content column ────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                // Capability name
                Text(result.capabilityId.displayName)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                // Suggested action
                Text(result.suggestedAction)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Confidence percentage
                Text(confidenceText)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)

                // First care resource (if any)
                if let firstResource = result.careResources.first {
                    careResourceLink(firstResource)
                        .padding(.top, 2)
                }

                // Acknowledge button
                if let acknowledge = onAcknowledge {
                    acknowledgeButton(acknowledge)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        // Acknowledged tint + glass
        .background {
            acknowledgedBackground
        }
        .amenGlass(.regular, cornerRadius: 14)
        .overlay {
            if isAcknowledged {
                acknowledgedOverlay
            }
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.14)
                : Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.8)),
            value: isAcknowledged
        )
        // MARK: Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Sub-views

    private var severityIconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(severityColor.opacity(isAcknowledged ? 0.12 : 0.15))
                .frame(width: 36, height: 36)

            Image(systemName: isAcknowledged ? "checkmark" : severityIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isAcknowledged ? Color.green : severityColor)
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.14) : Motion.adaptive(Motion.popToggle),
                    value: isAcknowledged
                )
        }
    }

    @ViewBuilder
    private var acknowledgedBackground: some View {
        if isAcknowledged {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.07))
        }
    }

    @ViewBuilder
    private var acknowledgedOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.green.opacity(0.40), lineWidth: 1)
    }

    private func careResourceLink(_ resource: AegisCareResource) -> some View {
        Button {
            if let urlString = resource.actionUrl, let url = URL(string: urlString) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: careResourceIcon(resource.resourceType))
                    .font(.system(size: 11, weight: .medium))
                Text(resource.title)
                    .font(AMENFont.semiBold(12))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
        .buttonStyle(.plain)
        .disabled(resource.actionUrl == nil)
        .accessibilityLabel("Resource: \(resource.title)")
    }

    private func acknowledgeButton(_ action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(action: action) {
                HStack(spacing: 6) {
                    if isAcknowledged {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(isAcknowledged ? "Understood" : "I understand")
                        .font(AMENFont.semiBold(13))
                }
                .foregroundStyle(isAcknowledged ? Color.green : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(isAcknowledged ? Color.green.opacity(0.18) : AmenTheme.Colors.amenBlue)
                }
            }
            .buttonStyle(AmenPressStyle(scale: 0.95))
            .accessibilityLabel(isAcknowledged ? "Understood" : "I understand this notice")
        }
    }

    // MARK: Helpers

    private func careResourceIcon(_ type: AegisCareResource.AegisCareResourceType) -> String {
        switch type {
        case .pastoralGuidance: return "hands.sparkles"
        case .crisisLine:       return "phone.fill"
        case .legalInfo:        return "doc.text"
        case .externalLink:     return "link"
        case .inAppAction:      return "arrow.right.circle"
        }
    }

    private var accessibilityLabel: String {
        var parts = [
            result.capabilityId.displayName,
            "\(severityLabel) severity",
            result.suggestedAction
        ]
        if isAcknowledged {
            parts.append("Acknowledged")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Detection Cards") {
    ScrollView {
        VStack(spacing: 12) {
            AegisDetectionResultCard(
                result: .make(
                    capability: .pauseBeforePosting,
                    severity: .caution,
                    confidence: 0.78,
                    action: "Take a breath before sharing — this post could affect others.",
                    care: [
                        AegisCareResource(
                            id: "r1",
                            title: "Pastoral Guidance",
                            body: "Speaking with a pastor can help.",
                            actionLabel: "Learn more",
                            actionUrl: "https://amen.app/pastoral",
                            resourceType: .pastoralGuidance
                        )
                    ]
                ),
                isAcknowledged: false,
                onAcknowledge: {}
            )

            AegisDetectionResultCard(
                result: .make(
                    capability: .childMinorPresence,
                    severity: .warn,
                    confidence: 0.91,
                    action: "This image may include a minor. Review before posting."
                ),
                isAcknowledged: true,
                onAcknowledge: {}
            )

            AegisDetectionResultCard(
                result: .make(
                    capability: .donationFraud,
                    severity: .block,
                    confidence: 0.97,
                    action: "We can't share this content as written. Please revise."
                )
            )

            AegisDetectionResultCard(
                result: .make(
                    capability: .hiddenPublicMetrics,
                    severity: .info,
                    confidence: 0.60,
                    action: "Engagement counts are hidden for your wellbeing."
                )
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
#endif
