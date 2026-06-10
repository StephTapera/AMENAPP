// AILTouchTargetCalibrationView.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Interaction Surface (A5)
//
// On-device touch-target calibration. The user taps a few sample targets at
// different sizes and chooses the one that feels most comfortable. The ONLY thing
// that ever leaves this view is the chosen size PREFERENCE, written via
// AILProfileService.shared.setTouchTargets(...).
//
// ┌──────────────────────────── IRON RULE C9 (privacy) ────────────────────────────┐
// │ NO raw tap timing, tap COORDINATES, dwell time, MISS RATES, retry counts, or    │
// │ any other motor/input metric is ever measured, stored, logged, or transmitted.  │
// │ This flow is purely a comfort PREVIEW: the user looks at sized targets and picks │
// │ a size. The output is a single enum value (.off / .large / .xl) — nothing else.  │
// │ There is deliberately no gesture analytics, no timer, no coordinate capture here.│
// └─────────────────────────────────────────────────────────────────────────────────┘
//
// No tier checks. No force-unwraps. 4-space indent.

import SwiftUI

// MARK: - Touch target sizing

/// Point dimensions for each preference. 44pt is Apple's minimum; large/xl grow
/// the hit area for users who need bigger targets.
extension A11yProfile.TouchTargets {
    var minimumDimension: CGFloat {
        switch self {
        case .off:   return 44
        case .large: return 52
        case .xl:    return 60
        }
    }

    /// Plain-language label for the calibration choice.
    var comfortLabel: String {
        switch self {
        case .off:   return "Standard"
        case .large: return "Large"
        case .xl:    return "Extra large"
        }
    }
}

// MARK: - View extension

extension View {
    /// Apply a minimum hit area driven by the user's saved touch-target preference.
    /// off = 44pt, large = 52pt, xl = 60pt. Expands the tappable rectangle without
    /// altering visual content. Reads the live profile so changes apply app-wide.
    func ailTouchTarget() -> some View {
        let dimension = AILProfileService.shared.profile.largerTouchTargets.minimumDimension
        return self
            .frame(minWidth: dimension, minHeight: dimension)
            .contentShape(Rectangle())
    }
}

// MARK: - Calibration flow

struct AILTouchTargetCalibrationView: View {

    /// Called once the user confirms a choice (host can dismiss/advance).
    var onDone: () -> Void = {}

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The size the user is currently previewing. Local @State ONLY — this is a
    /// preference choice, never a derived measurement. Nothing here is persisted
    /// until the user explicitly confirms.
    @State private var selection: A11yProfile.TouchTargets =
        AILProfileService.shared.profile.largerTouchTargets

    private let options: [A11yProfile.TouchTargets] = A11yProfile.TouchTargets.allCases

    var body: some View {
        VStack(spacing: 28) {
            header

            // Sample tap targets at the previewed size. Tapping a sample just sets
            // the previewed selection — there is NO timing or accuracy measurement.
            sampleTargets

            sizeChoices

            confirmButton
        }
        .padding(24)
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 8) {
            Text("Comfortable tap size")
                .font(.title2.weight(.semibold))
            Text("Try the buttons below and pick the size that feels easiest to tap. You can change this anytime.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var sampleTargets: some View {
        HStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { index in
                Button {
                    // Preview only — no coordinate/timing capture.
                } label: {
                    Image(systemName: "hand.tap")
                        .font(.title3)
                        .frame(
                            minWidth: selection.minimumDimension,
                            minHeight: selection.minimumDimension
                        )
                        .background(sampleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sample button \(index + 1)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var sizeChoices: some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack {
                        Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                        Text(option.comfortLabel)
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("\(Int(option.minimumDimension)) pt")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(choiceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.comfortLabel)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }

    private var confirmButton: some View {
        Button {
            // The ONLY thing persisted: the chosen size preference.
            AILProfileService.shared.setTouchTargets(selection)
            onDone()
        } label: {
            Text("Use \(selection.comfortLabel)")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: Backgrounds (Reduce Transparency honored)

    @ViewBuilder
    private var sampleBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var choiceBackground: some View {
        if reduceTransparency {
            Color(.secondarySystemBackground)
        } else {
            Rectangle().fill(.thinMaterial)
        }
    }
}
