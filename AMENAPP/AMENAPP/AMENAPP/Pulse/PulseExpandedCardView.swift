//
//  PulseExpandedCardView.swift
//  AMEN — Amen Pulse
//
//  Full-screen card morph (App-of-the-day expanding card). Hero band on top,
//  scrolling body below. Daily Brief carries the 30s / 3m / 10m segmented control.
//

import SwiftUI

struct PulseExpandedCardView: View {
    let card: PulseCard
    var namespace: Namespace.ID
    let onClose: () -> Void
    let onAction: (PulseCard) -> Void
    let onOpenWhatsNew: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var briefDuration: PulseBriefDuration = .threeMin
    @State private var appeared = false

    private var dark: Bool { card.hero.scrim == .dark }
    private var primaryText: Color { dark ? Color(hex: "EDEDF0") : Color(hex: "1C1C1E") }

    var body: some View {
        ZStack(alignment: .top) {
            (dark ? Color(hex: "0A0A0C") : Color.white).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroBand
                    body(for: card)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 60)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                }
            }

            closeButton
        }
        .matchedGeometryEffect(id: "card-\(card.id)", in: namespace, isSource: true)
        .clipShape(RoundedRectangle(cornerRadius: appeared ? 0 : 28, style: .continuous))
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82).delay(0.05)) {
                appeared = true
            }
        }
    }

    // MARK: Hero band

    private var heroBand: some View {
        ZStack(alignment: .bottomLeading) {
            PulseHeroBackdrop(hero: card.hero)
                .matchedGeometryEffect(id: "hero-\(card.id)", in: namespace, isSource: true)
                .frame(height: 320)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.eyebrow.uppercased())
                    .font(.system(size: 12, weight: .bold)).tracking(0.6)
                    .foregroundColor(dark ? .white.opacity(0.72) : Color(hex: "3C3C43").opacity(0.7))
                Text(card.title)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(dark ? .white : Color(hex: "1C1C1E"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .padding(.trailing, 60)
        }
        .frame(height: 320)
    }

    private var closeButton: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(hex: "787880").opacity(0.45)))
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 54)
    }

    // MARK: Body

    @ViewBuilder
    private func body(for card: PulseCard) -> some View {
        switch card.kind {
        case .dailyBriefHero:
            briefBody
        case .whatsNew:
            whatsNewBody
        default:
            standardBody
        }
        provenanceFooter
    }

    private var briefBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Brief length", selection: $briefDuration) {
                ForEach([PulseBriefDuration.thirtySec, .threeMin, .tenMin], id: \.self) { d in
                    Text(d.rawValue).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 20)

            ForEach(visibleSections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.heading.uppercased())
                        .font(.system(size: 13, weight: .bold)).tracking(0.4)
                        .foregroundColor(Color(hex: "8A8A8E"))
                    Text(section.body)
                        .font(.system(size: 16))
                        .foregroundColor(primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actionButton
        }
    }

    private var visibleSections: [PulseBriefSection] {
        (card.briefSections ?? []).filter { $0.minimumDuration.rank <= briefDuration.rank }
    }

    private var whatsNewBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.system(size: 16.5))
                    .foregroundColor(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }
            Button {
                onOpenWhatsNew(card.whatsNewStoryId ?? card.id)
            } label: {
                actionLabel(card.action.label.isEmpty ? String(localized: "See What’s New") : card.action.label,
                            icon: "sparkles")
            }
            .buttonStyle(.plain)
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.system(size: 16.5))
                    .foregroundColor(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }
            if let meta = card.meta, !meta.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(meta) { item in
                        Label {
                            Text(item.text).font(.system(size: 15, weight: .medium))
                        } icon: {
                            Image(systemName: item.systemImage).font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(primaryText)
                    }
                }
            }
            actionButton
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if card.action.kind != .none {
            Button {
                onAction(card)
            } label: {
                actionLabel(card.action.label, icon: "chevron.right", trailing: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(_ title: String, icon: String, trailing: Bool = false) -> some View {
        HStack(spacing: 7) {
            if !trailing { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
            Text(title).font(.system(size: 16.5, weight: .bold))
            if trailing { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundColor(dark ? .black : .white)
        .background(Capsule().fill(dark ? Color.white : Color(hex: "1C1C1E")))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    private var provenanceFooter: some View {
        Text(card.provenanceLabel ?? String(localized: "One action. Then close the app — Pulse will be here tomorrow."))
            .font(.system(size: 12.5))
            .foregroundColor(Color(hex: "8A8A8E"))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 16)
    }
}
