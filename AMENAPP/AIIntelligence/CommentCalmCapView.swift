// CommentCalmCapView.swift
// AMENAPP — Smart Comments Wave 3
//
// CalmCap mode indicator and controls. Inline banners/chips — not floating glass.
// Non-coercive throughout: all nudges are informational; posting is always available.
//
// Liquid Glass rules:
//   - Opaque chips/banners (inline modifiers, not floating controls)
//   - NO .ultraThinMaterial here — these are content-level indicators, not chrome

import SwiftUI
import Foundation

struct CommentCalmCapView: View {

    let settings: CalmCapSettings
    let isPosting: Bool
    let onKindnessAccepted: () -> Void

    @State private var kindnessNudgeDismissed = false

    // MARK: - Guard

    var body: some View {
        guard AMENFeatureFlags.shared.commentCalmCapEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(content)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Slow mode banner
            if settings.slowModeEnabled {
                slowModeBanner
            }

            // Sabbath mode indicator
            if settings.sabbathModeEnabled {
                sabbathModeBanner
            }

            // Kindness nudge — shown when about to post and not yet dismissed
            if settings.kindnessNudgeEnabled && isPosting && !kindnessNudgeDismissed {
                kindnessNudge
            }
        }
    }

    // MARK: - Slow Mode Banner

    private var slowModeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
            Text("Slow mode · Reflect before posting")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.orange)
            if let delay = settings.slowModeDelaySeconds, delay > 0 {
                Spacer(minLength: 0)
                Text("\(delay)s")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.orange.opacity(0.7))
            }
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

    // MARK: - Sabbath Mode Banner

    private var sabbathModeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.stars")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.indigo)
            Text("Quiet reflection mode")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.indigo)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.indigo.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.indigo.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Kindness Nudge

    // Non-preachy. The "Send anyway" option is always available and equally accessible.
    private var kindnessNudge: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Does this reflect how you'd say it in person?")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                // Send anyway — always available; not hidden, not demoted to disabled state
                Button(action: {
                    kindnessNudgeDismissed = true
                    onKindnessAccepted()
                }) {
                    Text("Send anyway")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(uiColor: .systemGray6))
                        )
                }
                .buttonStyle(.plain)

                // Revise — encourage reflection; secondary placement
                Button(action: {
                    kindnessNudgeDismissed = true
                }) {
                    Text("Revise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(uiColor: .systemGray5))
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        )
    }
}
