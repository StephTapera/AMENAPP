// AILabelPill.swift
// AMENAPP
//
// Phase 2 — Truthful AI Label System.
//
// Compact pill that surfaces a server-issued AI disclosure label
// (AI Assisted / AI Edited / AI Generated / AI Translated / etc).
// Tap to expand into the AIDisclosureSheet bottom sheet.
//
// CRITICAL: this view never invents a label. The label string + explanation
// MUST come from a server-issued AIDisclosureRecord (see TrustSpineService.
// getAIDisclosureDetails). Showing a client-guessed label is a violation of
// the non-negotiable trust rules.

import SwiftUI

// MARK: - AILabelPill

/// Liquid Glass disclosure pill. Single glass layer, restrained motion,
/// adapts to Reduce Transparency / Reduce Motion / Increase Contrast.
struct AILabelPill: View {
    let disclosure: AIDisclosureRecord
    var onTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isPressed: Bool = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                Text(disclosure.userVisibleLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(.primary)
            .background(pillBackground)
            .overlay(
                Capsule()
                    .strokeBorder(
                        contrast == .increased ? Color.primary.opacity(0.6) : Color.primary.opacity(0.08),
                        lineWidth: contrast == .increased ? 1.0 : 0.5
                    )
            )
            .clipShape(Capsule())
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.85), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("\(disclosure.userVisibleLabel). Tap for details.")
        .accessibilityHint(disclosure.userVisibleExplanation)
    }

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            // Reduce Transparency fallback: solid material per accessibility rules.
            Capsule().fill(Color(.secondarySystemBackground))
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }

    private var iconName: String {
        switch disclosure.actionType {
        case "ai_generated":          return "sparkles"
        case "ai_edited":             return "wand.and.stars"
        case "ai_translated":         return "character.bubble"
        case "ai_summarized":         return "text.append"
        case "ai_enhanced_audio":     return "waveform"
        case "ai_enhanced_lighting":  return "sun.max"
        case "ai_suggested_caption":  return "text.cursor"
        case "ai_safety_reviewed":    return "checkmark.shield"
        case "ai_alt_text":           return "accessibility"
        default:                      return "wand.and.stars"
        }
    }
}

// MARK: - AILabelPillRow

/// Convenience row that renders all server disclosure records for a media
/// item as a horizontal row of pills. Empty array → renders nothing.
struct AILabelPillRow: View {
    let disclosures: [AIDisclosureRecord]
    var onSelect: ((AIDisclosureRecord) -> Void)? = nil

    var body: some View {
        if disclosures.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(disclosures) { disclosure in
                        AILabelPill(disclosure: disclosure) {
                            onSelect?(disclosure)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(disclosures.count) AI disclosure label\(disclosures.count == 1 ? "" : "s")")
        }
    }
}

// MARK: - AIDisclosureSheet

/// Bottom sheet that explains the AI disclosure in plain language.
/// Liquid Glass header + solid readable body (per design directive).
struct AIDisclosureSheet: View {
    let disclosure: AIDisclosureRecord
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            // Solid body so text-heavy content stays readable.
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    explanationCard
                    metadataCard
                    disclaimerCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(disclosure.userVisibleLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("AI disclosure")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Close AI disclosure")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(
            reduceTransparency
                ? AnyView(Color(.secondarySystemBackground))
                : AnyView(Rectangle().fill(.ultraThinMaterial))
        )
    }

    @ViewBuilder
    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What happened")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(disclosure.userVisibleExplanation)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(label: "Action", value: disclosure.actionType.replacingOccurrences(of: "_", with: " ").capitalized)
            if !disclosure.modelProvider.isEmpty {
                row(label: "Provider", value: disclosure.modelProvider)
            }
            if !disclosure.purpose.isEmpty {
                row(label: "Purpose", value: disclosure.purpose)
            }
            row(label: "Confidence", value: "\(Int(disclosure.confidence * 100))%")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var disclaimerCard: some View {
        Text("AI disclosures are recorded server-side and cannot be modified after the post is created. Amen's trust system, not the creator, determines what label is shown.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func row(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - View modifier

extension View {
    /// Presents an AIDisclosureSheet when the binding contains a non-nil record.
    func aiDisclosureSheet(record: Binding<AIDisclosureRecord?>) -> some View {
        self.sheet(isPresented: Binding(
            get: { record.wrappedValue != nil },
            set: { newValue in if !newValue { record.wrappedValue = nil } }
        )) {
            if let r = record.wrappedValue {
                AIDisclosureSheet(disclosure: r) {
                    record.wrappedValue = nil
                }
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(24)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AI Label Pill — single") {
    AILabelPill(
        disclosure: AIDisclosureRecord(
            id: "d1",
            postId: "p1",
            mediaId: "m1",
            ownerUid: "u1",
            actionType: "ai_translated",
            modelProvider: "Amen AI",
            purpose: "Translated caption for international audience",
            userVisibleLabel: "AI Translated",
            userVisibleExplanation: "AI provided a translation. The original wording is preserved.",
            confidence: 0.95
        )
    )
    .padding()
}

#Preview("AI Disclosure Sheet") {
    AIDisclosureSheet(
        disclosure: AIDisclosureRecord(
            id: "d1",
            postId: "p1",
            mediaId: "m1",
            ownerUid: "u1",
            actionType: "ai_alt_text",
            modelProvider: "Amen AI",
            purpose: "Accessibility description for vision-impaired viewers",
            userVisibleLabel: "Alt Text Assisted",
            userVisibleExplanation: "AI generated an accessibility description. The creator can edit it.",
            confidence: 0.92
        ),
        onDismiss: {}
    )
}
#endif
