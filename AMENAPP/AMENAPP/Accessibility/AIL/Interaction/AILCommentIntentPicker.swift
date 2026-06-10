// AILCommentIntentPicker.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Interaction Surface (A5)
//
// A horizontal chip row of plain-language comment intents. Picking an intent lets
// a user who finds the blank reply box hard to start signal HOW they want to
// respond (encourage, ask, pray, support, disagree kindly, save) before any words.
//
// LIQUID GLASS / ACCESSIBILITY:
//   • Chips use a glass material but COLLAPSE to an opaque fill when the user has
//     Reduce Transparency on (@Environment(\.accessibilityReduceTransparency)).
//   • Each chip is a single accessibility element with a plain-language label.
//   • No vendor names. No tier checks. No force-unwraps. 4-space indent.

import SwiftUI

/// The set of plain-language comment intents a user can pick before replying.
enum AILCommentIntent: String, CaseIterable, Sendable, Identifiable {
    case encourage
    case ask
    case pray
    case support
    case disagreeKindly
    case save

    var id: String { rawValue }

    /// Plain-language label shown on the chip and read by VoiceOver.
    var label: String {
        switch self {
        case .encourage:      return "Encourage"
        case .ask:            return "Ask"
        case .pray:           return "Pray"
        case .support:        return "Support"
        case .disagreeKindly: return "Disagree kindly"
        case .save:           return "Save"
        }
    }

    /// SF Symbol paired with the label.
    var systemImage: String {
        switch self {
        case .encourage:      return "hands.clap"
        case .ask:            return "questionmark.circle"
        case .pray:           return "hands.sparkles"
        case .support:        return "heart"
        case .disagreeKindly: return "hand.raised"
        case .save:           return "bookmark"
        }
    }
}

/// Horizontal, scrollable row of intent chips. Calls `onSelect` with the picked
/// intent — the host owns what happens next (seed a reply, open Berean, save, …).
struct AILCommentIntentPicker: View {

    let onSelect: (AILCommentIntent) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(onSelect: @escaping (AILCommentIntent) -> Void) {
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(AILCommentIntent.allCases) { intent in
                    Button {
                        onSelect(intent)
                    } label: {
                        chip(for: intent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(intent.label)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func chip(for intent: AILCommentIntent) -> some View {
        HStack(spacing: 6) {
            Image(systemName: intent.systemImage)
                .font(.callout.weight(.semibold))
            Text(intent.label)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)               // comfortable hit area regardless of size class
        .foregroundStyle(.primary)
        .background(chipBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Capsule())
    }

    /// Glass when transparency is allowed; opaque fallback when Reduce Transparency
    /// is on (iron rule: never force translucency on a user who turned it off).
    @ViewBuilder
    private var chipBackground: some View {
        if reduceTransparency {
            Capsule().fill(Color(.secondarySystemBackground))
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }
}
