// SyntheticDetectionPipeline.swift
// AMEN Trust Layer — T4 Trust Guardrails Views
// SyntheticDisclosureNotice + DefaultSyntheticDetectionHook

import SwiftUI
import Foundation

// MARK: - Synthetic Disclosure Notice

/// Prominent banner shown when media is confirmed or likely AI-generated.
/// Only visible when `syntheticDetectionEnabled` flag is true.
struct SyntheticDisclosureNotice: View {
    @ObservedObject private var flags = TrustAccessibilityFeatureFlags.shared

    var body: some View {
        if flags.syntheticDetectionEnabled {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI-Generated Content")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("This content was created or detected as AI-generated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AI-Generated Content. This content was created or detected as AI-generated.")
        }
    }
}

// MARK: - Default Synthetic Detection Hook

/// ViewModifier that runs synthetic detection on `.task` and overlays
/// `SyntheticDisclosureNotice` if the result is synthetic.
struct DefaultSyntheticDetectionHook: ViewModifier {
    let mediaId: String
    let mimeType: String

    @State private var detectionResult: SyntheticDetectionService.DetectionResult = .unverified

    func body(content: Content) -> some View {
        content
            .task {
                do {
                    let result = try await SyntheticDetectionService.shared.detect(
                        mediaId: mediaId,
                        mimeType: mimeType
                    )
                    detectionResult = result
                    if result.isSynthetic {
                        try await SyntheticDetectionService.shared.enforceDisclosure(
                            mediaId: mediaId,
                            result: result
                        )
                    }
                } catch {
                    // Detection errors are non-fatal; leave detectionResult as .unverified
                    print("[SyntheticDetectionPipeline] Detection error for mediaId \(mediaId): \(error)")
                }
            }
            .overlay(alignment: .top) {
                if detectionResult.isSynthetic {
                    SyntheticDisclosureNotice()
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.25), value: detectionResult.isSynthetic)
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches synthetic detection and disclosure overlay for a given media asset.
    func syntheticDetectionHook(mediaId: String, mimeType: String) -> some View {
        modifier(DefaultSyntheticDetectionHook(mediaId: mediaId, mimeType: mimeType))
    }
}
