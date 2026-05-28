// SensitiveContentInterruptionView.swift
// AMENAPP
//
// Full-screen safety gate shown before content that may require trauma-awareness,
// grief sensitivity, or other pastoral care. Presents three paths: continue,
// skip this item, or end the session entirely.
//
// Design:
//   - Dark scrim overlay (black, 0.75 opacity)
//   - Centered white card with rounded corners
//   - SF Symbol shield with category tint
//   - Reduce Motion: entry animation suppressed
//
// Gated by AMENFeatureFlags.shared.mediaWellbeingControlsEnabled

import SwiftUI

struct SensitiveContentInterruptionView: View {

    // MARK: Inputs

    let contentWarning: ContentWarning
    let onProceed: () -> Void
    let onSkip: () -> Void
    let onEndSession: () -> Void

    // MARK: Nested Types

    struct ContentWarning {
        let title: String
        let description: String
        let category: WarningCategory

        enum WarningCategory {
            case grief
            case trauma
            case anxiety
            case matureThemes
            case intensiveTestimony
            case triggerWarning
        }
    }

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: State

    @State private var cardVisible = false

    // MARK: Body

    var body: some View {
        ZStack {
            // Scrim
            Color.black
                .opacity(0.75)
                .ignoresSafeArea()

            // Card
            VStack(spacing: 0) {
                shieldIcon
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                warningText
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                Divider()
                    .opacity(0.3)

                actionButtons
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
            )
            .padding(.horizontal, 28)
            .opacity(cardVisible ? 1 : 0)
            .scaleEffect(cardVisible ? 1 : (reduceMotion ? 1 : 0.92))
        }
        .onAppear {
            if reduceMotion {
                cardVisible = true
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    cardVisible = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Shield Icon

    private var shieldIcon: some View {
        ZStack {
            Circle()
                .fill(categoryColor.opacity(0.12))
                .frame(width: 72, height: 72)
            Image(systemName: "shield.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(categoryColor)
        }
        .accessibilityHidden(true)
    }

    // MARK: Warning Text

    private var warningText: some View {
        VStack(spacing: 8) {
            Text(contentWarning.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(contentWarning.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            // Primary: Continue with awareness
            Button(action: onProceed) {
                Text("Continue with awareness")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(categoryColor)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(categoryColor, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue with awareness")

            // Secondary: Skip this item
            Button(action: onSkip) {
                Text("Skip this item")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip this item")

            // Destructive: End session
            Button(action: onEndSession) {
                Text("End session")
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemRed))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End media session")
        }
    }

    // MARK: Category Color

    private var categoryColor: Color {
        switch contentWarning.category {
        case .grief:               return Color(.systemPurple)
        case .trauma:              return Color(.systemOrange)
        case .anxiety:             return Color(.systemBlue)
        case .matureThemes:        return Color(.systemYellow)
        case .intensiveTestimony:  return Color(.systemIndigo)
        case .triggerWarning:      return Color(.systemRed)
        }
    }
}
