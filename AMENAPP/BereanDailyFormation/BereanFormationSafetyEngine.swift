// BereanFormationSafetyEngine.swift
// AMENAPP — Berean Daily Formation Companion — Safety layer
//
// HARD CONSTRAINTS:
// - Crisis items → CrisisCard only. Never AI reflection, never arc card.
// - whySeeingThis() is the single canonical provenance source.

import SwiftUI

enum BereanFormationSafetyEngine {

    // MARK: - Crisis routing

    static func crisisItems(from list: [BereanPrayerItem]) -> [BereanPrayerItem] {
        list.filter { $0.sensitivity == .crisis && $0.status == "active" }
    }

    // MARK: - "Why am I seeing this?" provenance

    static func whySeeingThis(_ card: BereanFormationCard) -> String {
        switch card.source {
        case "readingPlan":
            return "This comes from your reading plan \"\(card.sourceDetail)\". Berean ties each day's verse to where you actually are — not a random pick."
        case "prayerList":
            return "You added this to your prayer list. Berean brings it back so you remember to pray again, and so you can celebrate when it's answered."
        case "sanctuary":
            return "This comes from activity in your Sanctuary \"\(card.sourceDetail)\" — a community you chose to join."
        case "highlights":
            return "You highlighted and annotated this verse. Berean surfaced it so you can continue that thread of thought."
        case "memoryVerses":
            return "Your spaced-repetition schedule says this verse is due for review today. Reviewing it now builds long-term retention."
        case "liturgicalCalendar":
            return "The church calendar marks this as \(card.sourceDetail). You opted into seasonal prompts during onboarding."
        default:
            return "You selected this type of content in your Berean preferences."
        }
    }
}

// MARK: - Mock label view

struct BereanMockLabel: View {
    var body: some View {
        Text("Prototype — mock text. Real Scripture from YouVersion license only.")
            .font(.systemScaled(9))
            .foregroundStyle(Color.white.opacity(0.30))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Tender badge view

struct BereanTenderBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Text("🕊️")
            Text("Gentle")
                .font(.systemScaled(10, weight: .medium))
                .foregroundStyle(Color(hex: "#4A9ECC"))
                .tracking(0.5)
        }
        .padding(.horizontal, 9).padding(.vertical, 2)
        .background(Color(hex: "#4A9ECC").opacity(0.12))
        .overlay(
            Capsule().strokeBorder(Color(hex: "#4A9ECC").opacity(0.25), lineWidth: 0.5)
        )
        .clipShape(Capsule())
        .accessibilityLabel("Gentle — tender prayer request")
    }
}
