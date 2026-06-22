// LinkPreviewCardView.swift
// AMENAPP — Smart Comments Wave 3
//
// Safe link preview card. Central safety rule: unknown or risky links MUST show
// a warning interstitial before navigation. No link opens silently.
//
// Liquid Glass rules:
//   - Opaque white card (no glass on link text)
//   - Reduce-transparency fallback: solid systemBackground

import SwiftUI
import Foundation

struct LinkPreviewCardView: View {

    let preview: LinkPreview

    @State private var showWarningInterstitial = false

    // MARK: - Guard

    var body: some View {
        guard AMENFeatureFlags.shared.commentLinkScannerEnabled else {
            return AnyView(plainUrlFallback)
        }
        return AnyView(cardContent)
    }

    // MARK: - Card Content

    private var cardContent: some View {
        Button(action: handleTap) {
            HStack(alignment: .top, spacing: 12) {
                // Domain favicon placeholder
                faviconPlaceholder

                VStack(alignment: .leading, spacing: 4) {
                    // Domain label
                    if let domain = preview.domain {
                        Text(domain)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Title
                    if let title = preview.title {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    } else {
                        Text(preview.resolvedUrl)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }

                    // Description excerpt
                    if let description = preview.description {
                        Text(description)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                // Safety badge
                safetyBadge
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showWarningInterstitial) {
            LinkWarningInterstitialView(
                preview: preview,
                onProceed: {
                    showWarningInterstitial = false
                    openURL()
                },
                onCancel: {
                    showWarningInterstitial = false
                }
            )
        }
    }

    // MARK: - Plain URL Fallback (flag OFF)

    private var plainUrlFallback: some View {
        Link(preview.resolvedUrl, destination: URL(string: preview.resolvedUrl) ?? URL(string: "about:blank")!)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.blue)
            .underline()
    }

    // MARK: - Favicon Placeholder

    private var faviconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(uiColor: .systemGray5))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - Safety Badge

    @ViewBuilder
    private var safetyBadge: some View {
        switch preview.safetyVerdict {
        case .safe:
            safeBadge(label: "Safe", icon: "checkmark.shield.fill", color: .green)
        case .unknown, .suspicious:
            safeBadge(label: "Unverified", icon: "exclamationmark.shield", color: .orange)
        case .phishing, .malware:
            safeBadge(label: "Not Safe", icon: "xmark.shield.fill", color: .red)
        case .adult:
            safeBadge(label: "Adult", icon: "exclamationmark.shield.fill", color: .orange)
        case .extremist:
            safeBadge(label: "Unsafe", icon: "xmark.shield.fill", color: .red)
        }
    }

    private func safeBadge(label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
        }
    }

    // MARK: - Card Background

    @ViewBuilder
    private var cardBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Color(uiColor: .systemBackground)
        } else {
            Color(uiColor: .systemBackground)
        }
    }

    // MARK: - Navigation

    private func handleTap() {
        if preview.requiresWarningInterstitial {
            showWarningInterstitial = true
        } else {
            openURL()
        }
    }

    private func openURL() {
        guard let url = URL(string: preview.resolvedUrl) else { return }
        UIApplication.shared.open(url)
    }
}
