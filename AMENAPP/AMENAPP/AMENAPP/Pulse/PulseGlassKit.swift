//
//  PulseGlassKit.swift
//  AMEN — Amen Pulse (Liquid Glass redesign)
//
//  The bright-ivory editorial Liquid Glass surface kit for Amen Pulse. Replaces the
//  dark-adaptive `systemGroupedBackground` look with a warm white canvas, soft glass
//  cards, an Amen-blue accent system, and the hero-card design language.
//
//  All components render from the FROZEN Pulse contracts (PulseCard / PulseDigest);
//  none of them mutate the model. Safety rails are preserved by the surface, not here:
//  this file is presentation only.
//
//  Design tokens live in `PulseInk`. Glass recipe lives in `.pulseGlassCard(...)`.
//

import SwiftUI

// MARK: - Design tokens

/// The Amen Pulse ivory-glass palette + metrics. One source of truth so every
/// component reads identically (no glass-on-glass drift).
enum PulseInk {
    static let canvasTop    = Color(hex: "FFFEFA")   // warm ivory
    static let canvasBottom = Color(hex: "F6F4EE")
    static let ink          = Color(hex: "1C1C1E")   // charcoal
    static let inkSoft      = Color(hex: "3C3C43").opacity(0.62)
    static let inkFaint     = Color(hex: "8A8A8E")
    static let amenBlue     = Color(hex: "3473F2")   // labels / chips / accent rail
    static let amenBlueSoft = Color(hex: "3473F2").opacity(0.10)
    static let gold         = Color(hex: "D4A85C")   // sparing spiritual emphasis
    static let hairline     = Color.white.opacity(0.6)

    static let cardCorner: CGFloat = 30
    static let heroCorner: CGFloat = 38
    static let chipCorner: CGFloat = 22
}

// MARK: - Glass recipe

private struct PulseGlassCard: ViewModifier {
    var corner: CGFloat
    var elevated: Bool

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(PulseInk.hairline, lineWidth: 0.75)
            )
            .overlay(alignment: .top) {
                // Inner top highlight for the "lit glass" read.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                            startPoint: .top, endPoint: .center
                        )
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(elevated ? 0.10 : 0.06),
                    radius: elevated ? 24 : 14, x: 0, y: elevated ? 14 : 8)
    }
}

extension View {
    /// The canonical Amen Pulse glass surface. Use for every card so depth stays consistent.
    func pulseGlassCard(corner: CGFloat = PulseInk.cardCorner, elevated: Bool = false) -> some View {
        modifier(PulseGlassCard(corner: corner, elevated: elevated))
    }
}

// MARK: - Button styles

/// Primary CTA pill ("Begin", "View Pulse"). Soft glass with a gentle press depth.
struct PulseGlassPillStyle: ButtonStyle {
    var filled: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.systemScaled(14.5, weight: .semibold))
            .foregroundStyle(filled ? Color.white : PulseInk.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                if filled {
                    Capsule().fill(PulseInk.amenBlue)
                } else {
                    Capsule().fill(Color.white.opacity(0.72))
                        .background(Capsule().fill(.ultraThinMaterial))
                }
            }
            .overlay(Capsule().stroke(PulseInk.hairline, lineWidth: filled ? 0 : 0.5))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Small circular glass icon button (settings, info, bookmark).
struct PulseGlassIconStyle: ButtonStyle {
    var diameter: CGFloat = 38
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.systemScaled(15, weight: .semibold))
            .foregroundStyle(PulseInk.ink)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color.white.opacity(0.7)))
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().stroke(PulseInk.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Borderless text action used in card action rows (Save / Share / Study / Listen).
struct PulseTextActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.systemScaled(13.5, weight: .semibold))
            .foregroundStyle(PulseInk.amenBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(PulseInk.amenBlueSoft))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}

// MARK: - Header

/// Spacious morning header: eyebrow + sparkle, greeting, subtitle, trailing glass button.
struct AmenPulseHeader: View {
    let greeting: String
    let subtitle: String
    var onSettings: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.systemScaled(12, weight: .bold))
                        .foregroundStyle(PulseInk.amenBlue)
                        .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                    Text("AMEN PULSE")
                        .font(.systemScaled(12, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(PulseInk.amenBlue)
                }
                Text(greeting)
                    .font(.systemScaled(30, weight: .heavy))
                    .foregroundStyle(PulseInk.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(PulseInk.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(action: onSettings) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(PulseGlassIconStyle())
            .accessibilityLabel(Text("Customize Pulse"))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(greeting). \(subtitle)")
    }
}

// MARK: - Hero card

/// The editorial hero — the main object on the screen. Abstract light hero zone
/// (no photos, no stock), then headline, scripture preview, a metadata row, and
/// exactly one primary CTA. Renders a daily-brief or scripture PulseCard.
struct PulseHeroCard: View {
    let card: PulseCard
    var namespace: Namespace.ID?
    var onBegin: () -> Void = {}
    var onInfo: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    private var style: PulseHeroStyle { PulseHeroStyle.resolve(card.hero.style) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroZone
            cardBody
        }
        .pulseGlassCard(corner: PulseInk.heroCorner, elevated: true)
        .modifier(OptionalMatchedGeometry(id: "card-\(card.id)", namespace: namespace))
        .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
        .contentShape(RoundedRectangle(cornerRadius: PulseInk.heroCorner, style: .continuous))
        .simultaneousGesture(pressGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.eyebrow). \(card.title)")
        .accessibilityHint(card.action.label.isEmpty ? "" : card.action.label)
        .accessibilityAddTraits(.isButton)
    }

    private var heroZone: some View {
        ZStack(alignment: .topLeading) {
            // Abstract light wash sampled from the card's hero style — calm, no imagery.
            LinearGradient(
                colors: [style.tint.opacity(0.45), PulseInk.gold.opacity(0.12), Color.white.opacity(0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(colors: [Color.white.opacity(0.5), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 220)
            )
            Text(card.eyebrow.uppercased())
                .font(.systemScaled(12, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(PulseInk.amenBlue)
                .padding(20)
        }
        .frame(height: 132)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: PulseInk.heroCorner, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: PulseInk.heroCorner,
                style: .continuous
            )
        )
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title)
                .font(.systemScaled(30, weight: .heavy))
                .foregroundStyle(PulseInk.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(PulseInk.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let facts = card.facts, !facts.isEmpty {
                metaRow(facts)
            }

            HStack(spacing: 12) {
                if card.action.kind != .none {
                    Button(action: onBegin) { Text(card.action.label) }
                        .buttonStyle(PulseGlassPillStyle(filled: true))
                }
                Spacer(minLength: 0)
                Button(action: onInfo) { Image(systemName: "info.circle") }
                    .buttonStyle(PulseGlassIconStyle(diameter: 34))
                    .accessibilityLabel(Text("Why am I seeing this?"))
            }
            .padding(.top, 4)
        }
        .padding(22)
    }

    private func metaRow(_ facts: [PulseFact]) -> some View {
        HStack(spacing: 14) {
            ForEach(facts.prefix(3)) { fact in
                Label {
                    Text(fact.text).font(.systemScaled(12.5, weight: .semibold))
                } icon: {
                    Image(systemName: fact.systemImage).font(.systemScaled(11, weight: .semibold))
                }
                .foregroundStyle(PulseInk.inkSoft)
                .lineLimit(1)
            }
        }
        .padding(.top, 2)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                if reduceMotion { pressed = true }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pressed = true } }
            }
            .onEnded { _ in
                if reduceMotion { pressed = false }
                else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pressed = false } }
            }
    }
}

// MARK: - Status chips

/// A compact "what's waiting" chip — title + one-line status. Three of these sit
/// below the hero so the user can see the day's shape without scrolling.
struct PulseStatusChip: View {
    let title: String
    let status: String
    let systemImage: String
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: systemImage)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(PulseInk.amenBlue)
                Text(title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(PulseInk.ink)
                Text(status)
                    .font(.systemScaled(12, weight: .regular))
                    .foregroundStyle(PulseInk.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .pulseGlassCard(corner: PulseInk.chipCorner)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(status)")
        .accessibilityAddTraits(.isButton)
    }
}

struct PulseStatusRow: View {
    let verseStatus: String
    let prayerStatus: String
    let communityStatus: String
    var onVerse: () -> Void = {}
    var onPrayer: () -> Void = {}
    var onCommunity: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            PulseStatusChip(title: String(localized: "Verse"), status: verseStatus,
                            systemImage: "book.closed", onTap: onVerse)
            PulseStatusChip(title: String(localized: "Prayer"), status: prayerStatus,
                            systemImage: "hands.sparkles", onTap: onPrayer)
            PulseStatusChip(title: String(localized: "Community"), status: communityStatus,
                            systemImage: "person.2", onTap: onCommunity)
        }
    }
}

// MARK: - Daily Verse card

/// Refined white verse card with a blue accent rail and Save / Share / Study / Listen.
/// "Study" hands off to Berean; "Listen" reads the verse aloud (wired by the surface).
struct DailyVerseCard: View {
    let reference: String
    let verse: String
    let translationChip: String
    var isSaved: Bool = false
    var onSave: () -> Void = {}
    var onShare: () -> Void = {}
    var onStudy: () -> Void = {}
    var onListen: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(PulseInk.amenBlue)
                .frame(width: 3)
                .clipShape(Capsule())
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Daily Verse"))
                    .font(.systemScaled(12, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(PulseInk.amenBlue)
                Text(reference)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(PulseInk.inkSoft)
                Text(verse)
                    .font(.systemScaled(20, weight: .semibold))
                    .foregroundStyle(PulseInk.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(translationChip)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(PulseInk.amenBlue)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(PulseInk.amenBlueSoft))

                HStack(spacing: 8) {
                    Button(action: onSave) {
                        Label(isSaved ? String(localized: "Saved") : String(localized: "Save"),
                              systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(PulseTextActionStyle())
                    Button(action: onShare) { Label(String(localized: "Share"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(PulseTextActionStyle())
                    Button(action: onStudy) { Label(String(localized: "Study"), systemImage: "text.book.closed") }
                        .buttonStyle(PulseTextActionStyle())
                    Button(action: onListen) { Label(String(localized: "Listen"), systemImage: "waveform") }
                        .buttonStyle(PulseTextActionStyle())
                }
                .labelStyle(.titleAndIcon)
                .padding(.top, 2)
            }
            .padding(.leading, 16)
            .padding(.vertical, 18)
            .padding(.trailing, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseGlassCard()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Reflection card

/// "A Moment to Consider" — an AI-assisted reflection PROMPT, explicitly labeled as a
/// reflection aid (not doctrine). Follow-up verbs guide rather than instruct.
struct PulseReflectionCard: View {
    let prompt: String
    var onReflect: () -> Void = {}
    var onPray: () -> Void = {}
    var onJournal: () -> Void = {}
    var onDiscuss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.systemScaled(12, weight: .bold))
                Text(String(localized: "A Moment to Consider").uppercased())
                    .font(.systemScaled(12, weight: .bold))
                    .tracking(0.6)
            }
            .foregroundStyle(PulseInk.gold)

            Text(prompt)
                .font(.systemScaled(17, weight: .regular))
                .foregroundStyle(PulseInk.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onReflect) { Label(String(localized: "Reflect"), systemImage: "leaf") }
                    .buttonStyle(PulseTextActionStyle())
                Button(action: onPray) { Label(String(localized: "Pray"), systemImage: "hands.sparkles") }
                    .buttonStyle(PulseTextActionStyle())
                Button(action: onJournal) { Label(String(localized: "Journal"), systemImage: "square.and.pencil") }
                    .buttonStyle(PulseTextActionStyle())
                Button(action: onDiscuss) { Label(String(localized: "Discuss"), systemImage: "bubble.left.and.bubble.right") }
                    .buttonStyle(PulseTextActionStyle())
            }
            .labelStyle(.titleAndIcon)

            Text(String(localized: "A reflection aid — an invitation, not instruction. It does not represent any doctrinal position."))
                .font(.systemScaled(11, weight: .regular))
                .foregroundStyle(PulseInk.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseGlassCard()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Community Pulse card

/// Bridges Pulse into the social side WITHOUT leaking private content: every line is a
/// count or a non-private signal, and one CTA leads into the full Pulse/community feed.
struct CommunityPulseLine: Identifiable {
    let id = UUID()
    let systemImage: String
    let text: String
}

struct CommunityPulseCard: View {
    let lines: [CommunityPulseLine]
    var onViewPulse: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.wave.2")
                    .font(.systemScaled(12, weight: .bold))
                Text(String(localized: "Community Pulse").uppercased())
                    .font(.systemScaled(12, weight: .bold))
                    .tracking(0.6)
            }
            .foregroundStyle(PulseInk.amenBlue)

            if lines.isEmpty {
                Text(String(localized: "All quiet in your groups right now."))
                    .font(.systemScaled(14, weight: .regular))
                    .foregroundStyle(PulseInk.inkSoft)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        Label {
                            Text(line.text).font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(PulseInk.ink)
                        } icon: {
                            Image(systemName: line.systemImage)
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(PulseInk.amenBlue)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button(action: onViewPulse) { Text(String(localized: "View Pulse")) }
                .buttonStyle(PulseGlassPillStyle())
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseGlassCard()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - matchedGeometry helper (optional namespace)

private struct OptionalMatchedGeometry: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Pulse Glass Kit") {
    ZStack {
        LinearGradient(colors: [PulseInk.canvasTop, PulseInk.canvasBottom],
                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        ScrollView {
            VStack(spacing: 18) {
                AmenPulseHeader(greeting: "Good morning, Friend.",
                                subtitle: "Thursday, June 18 · Your daily rhythm is ready.")
                if let hero = PulseDigest.previewSeed.cards.first {
                    PulseHeroCard(card: hero, namespace: nil)
                }
                PulseStatusRow(verseStatus: "Ready", prayerStatus: "1 prompt", communityStatus: "3 updates")
                DailyVerseCard(reference: "Matthew 6:25–34",
                               verse: "But seek first the kingdom of God and his righteousness, and all these things will be added to you.",
                               translationChip: "Matthew 6:33 · KJV")
                PulseReflectionCard(prompt: "What does it look like to seek first — before the list, the inbox, the plans?")
                CommunityPulseCard(lines: [
                    .init(systemImage: "hands.sparkles", text: "2 prayer requests from your groups"),
                    .init(systemImage: "envelope", text: "1 message needs a thoughtful reply"),
                    .init(systemImage: "bubble.left.and.bubble.right", text: "New discussion in Bible Study")
                ])
            }
            .padding(18)
        }
    }
}
#endif
