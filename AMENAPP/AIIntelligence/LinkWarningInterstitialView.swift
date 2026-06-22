// LinkWarningInterstitialView.swift
// AMENAPP — Smart Comments Wave 3
//
// Warning sheet shown before navigating to risky or unknown links.
// Cancel is always the primary action. Phishing/malware links have a disabled proceed button.
//
// Liquid Glass rules:
//   - Sheet background: .ultraThinMaterial (floating control)
//   - Warning card inside: opaque, high-contrast

import SwiftUI
import Foundation

struct LinkWarningInterstitialView: View {

    let preview: LinkPreview
    let onProceed: () -> Void
    let onCancel: () -> Void

    // MARK: - Derived Properties

    private var isBlockedVerdict: Bool {
        switch preview.safetyVerdict {
        case .phishing, .malware: return true
        default: return false
        }
    }

    private var title: String {
        isBlockedVerdict
            ? "This link may be unsafe"
            : "Proceed with caution"
    }

    private var verdictExplanation: String {
        switch preview.safetyVerdict {
        case .phishing:
            return "This link has been identified as a phishing attempt. It may try to steal your personal information or account credentials."
        case .malware:
            return "This link has been identified as potentially containing malware. Visiting it could harm your device."
        case .adult:
            return "This link points to adult content. Make sure you are in an appropriate setting before continuing."
        case .extremist:
            return "This link may lead to content that promotes harmful or extremist views."
        case .suspicious:
            return "We found some unusual signals associated with this link. We couldn't confirm it's safe."
        case .unknown:
            return "We couldn't verify this link is safe. It may be a new or private site."
        case .safe:
            return "This link appears safe."
        }
    }

    private var warningColor: Color {
        isBlockedVerdict ? .red : .orange
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Sheet background — ultraThinMaterial (floating control per Liquid Glass rules)
            if UIAccessibility.isReduceTransparencyEnabled {
                Color(uiColor: .systemBackground).ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer()

                // Opaque warning card
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: isBlockedVerdict ? "xmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(warningColor)
                            Text(title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                        }

                        // Resolved URL — shown prominently
                        Text(preview.resolvedUrl)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    // Explanation — plain English, no jargon
                    Text(verdictExplanation)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Recommendation chip for blocked verdicts
                    if isBlockedVerdict {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                            Text("We recommend not opening this link")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                            Text("We couldn't verify this link is safe")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                    }

                    // Action buttons — Cancel is primary
                    VStack(spacing: 10) {
                        // Cancel (primary)
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.primary)
                                )
                        }

                        // Proceed (secondary — disabled for blocked verdicts)
                        Button(action: { if !isBlockedVerdict { onProceed() } }) {
                            Text("Open anyway")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(isBlockedVerdict ? .secondary : warningColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(uiColor: .systemGray6))
                                )
                        }
                        .disabled(isBlockedVerdict)
                        .opacity(isBlockedVerdict ? 0.4 : 1.0)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}
