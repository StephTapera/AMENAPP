// AmenScamShieldAlertView.swift
// AMEN Connect + Spaces — Scam Shield Warning Banner
// Built 2026-06-02

import SwiftUI

// MARK: - Flag type → human text

private extension AmenScamFlagType {
    var humanReadableDescription: String {
        switch self {
        case .moneyRequest:
            return "This message appears to request money or payment."
        case .giftCardRequest:
            return "This message appears to ask for gift cards, which is a common scam pattern."
        case .cryptoRequest:
            return "This message appears to involve cryptocurrency, which is frequently used in scams."
        case .offPlatformPaymentRequest:
            return "This message appears to request payment outside the platform, which is a common scam pattern in faith communities."
        case .impersonation:
            return "This message may be from someone impersonating another person."
        case .suspiciousExternalLink:
            return "This message contains a suspicious external link."
        case .financialAdvice:
            return "This message contains unsolicited financial advice."
        }
    }

    var shortLabel: String {
        switch self {
        case .moneyRequest:            return "Payment Request"
        case .giftCardRequest:         return "Gift Card Request"
        case .cryptoRequest:           return "Crypto Request"
        case .offPlatformPaymentRequest: return "Off-Platform Payment"
        case .impersonation:           return "Possible Impersonation"
        case .suspiciousExternalLink:  return "Suspicious Link"
        case .financialAdvice:         return "Financial Advice"
        }
    }
}

// MARK: - Combined body text

private func combinedFlagDescription(_ flagTypes: [AmenScamFlagType]) -> String {
    if flagTypes.count == 1, let first = flagTypes.first {
        return first.humanReadableDescription
    }
    let items = flagTypes.prefix(3).map(\.shortLabel).joined(separator: ", ")
    return "This message exhibits multiple warning signs: \(items). This is a common pattern in faith community scams."
}

// MARK: - Alert view

struct AmenScamShieldAlertView: View {
    let flag: AmenScamShieldFlag
    let onReport: () -> Void
    let onDismiss: () -> Void

    private static let amber = Color(red: 1.0, green: 0.72, blue: 0.1)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Self.amber)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("This message may be unsafe")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(combinedFlagDescription(flag.flagTypes))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .padding(16)

            // Flag type chips
            if flag.flagTypes.count > 1 {
                flagChips
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider()
                .background(Self.amber.opacity(0.3))

            // Actions
            HStack(spacing: 0) {
                // Report button — gold outline
                Button(action: onReport) {
                    Text("Report")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "D9A441"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .trailing) {
                    Divider().background(Self.amber.opacity(0.25))
                }
                .accessibilityLabel("Report this message")

                // Dismiss — ghost
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss warning")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.14, green: 0.10, blue: 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Self.amber.opacity(0.45), lineWidth: 1)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Safety warning: \(combinedFlagDescription(flag.flagTypes))")
    }

    private var flagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(flag.flagTypes, id: \.self) { flagType in
                    Text(flagType.shortLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Self.amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(Self.amber.opacity(0.12))
                                .overlay {
                                    Capsule().strokeBorder(Self.amber.opacity(0.35), lineWidth: 1)
                                }
                        }
                        .accessibilityLabel(flagType.shortLabel)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Single flag") {
    AmenScamShieldAlertView(
        flag: AmenScamShieldFlag(
            id: "f1",
            messageId: "m1",
            authorId: "user123",
            flagTypes: [.offPlatformPaymentRequest],
            confidence: 0.91,
            surfaced: true,
            reviewedByHuman: false,
            flaggedAt: Date()
        ),
        onReport: {},
        onDismiss: {}
    )
    .padding()
    .background(Color(hex: "070607"))
    .preferredColorScheme(.dark)
}

#Preview("Multiple flags") {
    AmenScamShieldAlertView(
        flag: AmenScamShieldFlag(
            id: "f2",
            messageId: "m2",
            authorId: "user456",
            flagTypes: [.moneyRequest, .cryptoRequest, .offPlatformPaymentRequest],
            confidence: 0.97,
            surfaced: true,
            reviewedByHuman: false,
            flaggedAt: Date()
        ),
        onReport: {},
        onDismiss: {}
    )
    .padding()
    .background(Color(hex: "070607"))
    .preferredColorScheme(.dark)
}
