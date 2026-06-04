// BereanArcCardStackView.swift
// AMENAPP — Berean Daily Formation Companion
//
// Horizontal paged arc stack for the morning formation cards.
// Dots animate: active dot widens to 20pt pill; inactive 6pt circle.

import SwiftUI

struct BereanArcCardStackView: View {
    let cards: [BereanFormationCard]
    @Binding var activeIndex: Int
    var onWhyTapped: ((BereanFormationCard) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $activeIndex) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    BereanArcMiniCard(card: card, onWhyTapped: { onWhyTapped?(card) })
                        .padding(.horizontal, 4)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 160)

            // Dot indicators
            HStack(spacing: 8) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    let isActive = idx == activeIndex
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                            activeIndex = idx
                        }
                    } label: {
                        Capsule()
                            .fill(isActive ? NotifGlassTokens.goldPrimary : Color.white.opacity(0.25))
                            .frame(width: isActive ? 20 : 6, height: 6)
                            .shadow(color: isActive ? NotifGlassTokens.goldPrimary.opacity(0.5) : .clear, radius: 4)
                    }
                    .buttonStyle(.plain)
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: activeIndex)
                    .accessibilityLabel("Card \(idx + 1) of \(cards.count)")
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
                }
            }
        }
    }
}

// MARK: - Mini arc preview card

private struct BereanArcMiniCard: View {
    let card: BereanFormationCard
    var onWhyTapped: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                // Type label row
                HStack(spacing: 6) {
                    Image(systemName: card.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(NotifGlassTokens.goldPrimary)
                    Text(card.typeLabel.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NotifGlassTokens.goldPrimary)
                        .tracking(1.5)
                    Spacer()
                }

                // Preview text
                Text(card.previewText)
                    .font(.custom("Georgia", size: 14).italic())
                    .foregroundStyle(Color(hex: "#F5F0E8"))
                    .lineSpacing(2)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                // Verse chip (if present)
                if let ref = card.verseChipRef {
                    BereanVerseChip(reference: ref)
                }
            }
            .padding(16)
            .glassSurface(cornerRadius: 18)
            .frame(maxHeight: 152)

            // Why button
            Button {
                onWhyTapped?()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.40))
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel("Why am I seeing this?")
        }
    }
}

// MARK: - Verse chip

struct BereanVerseChip: View {
    let reference: String
    var translation: String = "ESV"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "book.closed")
                .font(.system(size: 9))
                .foregroundStyle(NotifGlassTokens.goldPrimary)
            Text("\(reference) · \(translation)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotifGlassTokens.goldPrimary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(NotifGlassTokens.goldPrimary.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(NotifGlassTokens.goldPrimary.opacity(0.25), lineWidth: 0.5))
    }
}
