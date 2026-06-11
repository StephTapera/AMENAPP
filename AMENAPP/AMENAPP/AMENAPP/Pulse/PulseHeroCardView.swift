//
//  PulseHeroCardView.swift
//  AMEN — Amen Pulse
//
//  App Store "Today" edge-to-edge story card. Photo (or gradient) hero, scrim,
//  eyebrow, title, optional fact/meta rows, and exactly ONE primary action pill.
//

import SwiftUI

// MARK: - Shared hero backdrop (image or gradient + scrim)

struct PulseHeroBackdrop: View {
    let hero: PulseHero

    private var style: PulseHeroStyle { PulseHeroStyle.resolve(hero.style) }
    private var scrim: PulseScrim { hero.scrim }

    var body: some View {
        ZStack {
            if let urlString = hero.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        style.background()
                    }
                }
            } else {
                style.background()
            }
            PulseScrimOverlay(scrim: scrim)
        }
        .clipped()
    }
}

// MARK: - Card

struct PulseHeroCardView: View {
    let card: PulseCard
    var namespace: Namespace.ID
    var isSourceForMorph: Bool
    var isHidden: Bool
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    private var dark: Bool { card.hero.scrim == .dark }

    private var height: CGFloat {
        switch card.kind {
        case .dailyBriefHero: return 460
        case .whatsNew:       return 440
        case .churchEvent:    return 410
        case .prayerFollowup: return 370
        default:              return 350
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PulseHeroBackdrop(hero: card.hero)
                .matchedGeometryEffect(id: "hero-\(card.id)", in: namespace, isSource: isSourceForMorph)

            content
                .padding(20)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .matchedGeometryEffect(id: "card-\(card.id)", in: namespace, isSource: isSourceForMorph)
        .shadow(color: .black.opacity(0.13), radius: 14, x: 0, y: 10)
        .scaleEffect(pressed ? 0.97 : 1)
        .opacity(isHidden ? 0 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: onOpen)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        if reduceMotion { pressed = true }
                        else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pressed = true } }
                    }
                }
                .onEnded { _ in
                    if reduceMotion { pressed = false }
                    else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pressed = false } }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.eyebrow). \(card.title)")
        .accessibilityHint(card.action.label)
        .accessibilityAddTraits(.isButton)
    }

    private var primaryText: Color { dark ? .white : Color(hex: "1C1C1E") }
    private var secondaryText: Color { dark ? Color.white.opacity(0.75) : Color(hex: "3C3C43").opacity(0.72) }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)

            Text(card.eyebrow.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.6)
                .foregroundColor(dark ? Color.white.opacity(0.72) : Color(hex: "3C3C43").opacity(0.65))

            Text(card.title)
                .font(.system(size: card.kind == .dailyBriefHero ? 34 : 26, weight: .heavy))
                .foregroundColor(primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: dark ? .black.opacity(0.25) : .clear, radius: 12, y: 1)

            if let facts = card.facts, !facts.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(facts) { fact in
                        Label {
                            Text(fact.text).font(.system(size: 14.5, weight: .medium))
                        } icon: {
                            Image(systemName: fact.systemImage).font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(primaryText.opacity(0.85))
                    }
                }
                .padding(.top, 2)
            }

            if let meta = card.meta, !meta.isEmpty {
                HStack(spacing: 14) {
                    ForEach(meta) { item in
                        Label {
                            Text(item.text).font(.system(size: 13.5, weight: .semibold))
                        } icon: {
                            Image(systemName: item.systemImage).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(primaryText.opacity(0.9))
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 14) {
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if card.action.kind != .none {
                    actionPill
                }
            }
            .padding(.top, 2)
        }
    }

    private var actionPill: some View {
        Text(card.action.label)
            .font(.system(size: 14.5, weight: .bold))
            .foregroundColor(dark ? .white : Color(hex: "1C1C1E"))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(dark ? Color(hex: "3C3C43").opacity(0.45) : Color.white.opacity(0.72))
                    .background(Capsule().fill(.ultraThinMaterial))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
