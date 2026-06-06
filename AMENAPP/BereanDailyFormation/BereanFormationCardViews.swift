// BereanFormationCardViews.swift
// AMENAPP — Berean Daily Formation Companion
//
// All 7 card types + dispatcher + WhySheet + CrisisCard.
// CrisisCard: NEVER contains AI reflection. Real crisis resources only.

import SwiftUI

// MARK: - Shared: Section label

private struct FormationSectionLabel: View {
    let icon: String    // SF symbol name
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Color.accentColor)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .tracking(1.5)
        }
    }
}

// MARK: - Shared: Verse block

private struct FormationVerseBlock: View {
    let text: String

    private var displayText: String {
        text.replacingOccurrences(of: #"\[MOCK — \w+\] "#, with: "", options: .regularExpression)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
                .clipShape(Capsule())
            Text(displayText)
                .font(.body.italic())
                .foregroundStyle(Color.primary)
                .lineSpacing(4)
                .padding(.leading, 14)
        }
    }
}

// MARK: - Shared: Strength bar

private struct FormationStrengthBar: View {
    let pct: Int
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(Color.secondary)
                Spacer()
                Text("\(pct)%").font(.system(size: 11)).foregroundStyle(Color.accentColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.separator).frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(pct) / 100, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Card 1: Verse & Reflection

struct BereanVerseReflectionCard: View {
    let card: BereanFormationCard

    var body: some View {
        guard case .verse(let verse, let passageRange) = card.data else { return AnyView(EmptyView()) }
        return AnyView(_verseCard(verse: verse, passageRange: passageRange))
    }

    private func _verseCard(verse: BereanVerse, passageRange: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FormationSectionLabel(icon: "sparkle", text: "Daily Verse")

            Text(passageRange)
                .font(.system(size: 11)).foregroundStyle(Color.secondary).tracking(1)

            FormationVerseBlock(text: verse.text)

            HStack(spacing: 8) {
                if let ref = card.verseChipRef {
                    BereanVerseChip(reference: ref)
                }
                BereanMockLabel()
            }

            VStack(alignment: .leading, spacing: 8) {
                FormationSectionLabel(icon: "quote.bubble", text: "A moment to consider")
                Text("What does it look like to seek first — before the list, the inbox, the plans? Not as a task, but as an orientation. Where does your attention go first today?")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineSpacing(3)
                Text("This reflection is an invitation, not instruction. It does not represent any doctrinal position.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineSpacing(2)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
            )
        }
        .padding(20)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Card 2: Reading Plan

struct BereanReadingPlanCard: View {
    let card: BereanFormationCard

    var body: some View {
        guard case .plan(let plan) = card.data else { return AnyView(EmptyView()) }
        return AnyView(_planCard(plan: plan))
    }

    private func _planCard(plan: BereanReadingPlan) -> some View {
        let pct = Int(plan.progress * 100)
        let remaining = plan.totalDays - plan.currentDay

        return VStack(alignment: .leading, spacing: 16) {
            FormationSectionLabel(icon: "book", text: "Reading Plan")

            Text(plan.name)
                .font(.title2.bold())
                .foregroundStyle(Color.primary)

            Text("Day \(plan.currentDay) of \(plan.totalDays) — today's passage")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)

            FormationStrengthBar(pct: pct, label: "\(pct)% complete · \(remaining) days remaining")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's reading")
                        .font(.system(size: 10)).foregroundStyle(Color.secondary)
                    BereanVerseChip(reference: plan.todayPassageRange)
                }
                Spacer()
                Button {
                    // Open reading
                } label: {
                    Text("Read now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.separator, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
            )
        }
        .padding(20)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Card 3: Prayer Follow-up

struct BereanPrayerCard: View {
    let card: BereanFormationCard
    @State private var action: String? = nil

    var body: some View {
        guard case .prayer(let prayer) = card.data else { return AnyView(EmptyView()) }
        return AnyView(_prayerCard(prayer: prayer))
    }

    private func _prayerCard(prayer: BereanPrayerItem) -> some View {
        let daysSince: Int = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            guard let then = fmt.date(from: prayer.prayedOn) else { return 0 }
            return Calendar.current.dateComponents([.day], from: then, to: Date()).day ?? 0
        }()

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                FormationSectionLabel(icon: "hands.clap", text: "Prayer Follow-up")
                if prayer.sensitivity == .tender { Spacer(); BereanTenderBadge() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(prayer.subject)
                    .font(.title3.bold())
                    .foregroundStyle(Color.primary)
                    .lineSpacing(2)
                Text("For \(prayer.forWhom) · \(daysSince == 0 ? "today" : "\(daysSince) day\(daysSince == 1 ? "" : "s") ago")")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
            }

            if prayer.sensitivity == .tender {
                Text("This is a tender request. Berean is holding it gently. Consider reaching out to \(prayer.forWhom), or sharing this with your pastor or a trusted friend in community.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#4A9ECC"))
                    .lineSpacing(2)
                    .padding(12)
                    .background(Color(hex: "#4A9ECC").opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(hex: "#4A9ECC").opacity(0.25), lineWidth: 0.5)
                    )
            }

            if let confirmed = action {
                Text(confirmed == "prayed" ? "✓ Marked as prayed today."
                     : confirmed == "answered" ? "✓ Celebrated as answered. Glory be."
                     : "✓ Reminder added to check in.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#3DAA6E"))
                    .padding(12)
                    .background(Color(hex: "#3DAA6E").opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                HStack(spacing: 10) {
                    prayerActionButton("Pray again",    id: "prayed",   primary: true)
                    prayerActionButton("Mark answered", id: "answered", primary: false)
                    prayerActionButton("Check in",      id: "checkin",  primary: false)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(prayer.sensitivity == .tender ? Color(hex: "#4A9ECC").opacity(0.05) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(prayer.sensitivity == .tender ? Color(hex: "#4A9ECC").opacity(0.30) : Color.separator, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func prayerActionButton(_ label: String, id: String, primary: Bool) -> some View {
        Button { action = id } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(primary ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(primary ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card 4: Sanctuary

struct BereanSanctuaryCard: View {
    let card: BereanFormationCard

    var body: some View {
        guard case .sanctuary(let s) = card.data else { return AnyView(EmptyView()) }
        return AnyView(_sanctuaryCard(s: s))
    }

    private func _sanctuaryCard(s: BereanSanctuary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FormationSectionLabel(icon: "building.columns", text: "Sanctuary")

            Text(s.name)
                .font(.title2.bold())
                .foregroundStyle(Color.primary)

            Text(verbatim: "\u{201C}" + s.recentActivity + "\u{201D}")
                .font(.subheadline.italic())
                .foregroundStyle(Color.secondary)
                .lineSpacing(2)

            HStack(spacing: 12) {
                sanctuaryStatBox(label: "Open prayer requests", value: "\(s.openPrayerRequests)")
                sanctuaryStatBox(label: "Active threads",        value: "\(s.activeThreads)")
            }

            Button {
                // Navigate to sanctuary
            } label: {
                Text("Visit Sanctuary")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.separator, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassSurface(cornerRadius: 20)
    }

    private func sanctuaryStatBox(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.bold())
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
        )
    }
}

// MARK: - Card 5: Study

struct BereanStudyCard: View {
    let card: BereanFormationCard

    var body: some View {
        guard case .study(let h, let verse) = card.data else { return AnyView(EmptyView()) }
        return AnyView(_studyCard(h: h, verse: verse))
    }

    private func _studyCard(h: BereanHighlight, verse: BereanVerse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FormationSectionLabel(icon: "magnifyingglass", text: "Open Study")

            FormationVerseBlock(text: verse.text)

            HStack(spacing: 8) {
                BereanVerseChip(reference: h.verseRef)
                BereanMockLabel()
            }

            if !h.note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your note · \(h.savedOn)")
                        .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.25))
                    Text(verbatim: "\u{201C}" + h.note + "\u{201D}")
                        .font(.custom("Georgia", size: 15).italic())
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineSpacing(3)
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(hex: "#C9A84C").opacity(0.18), lineWidth: 0.5)
                )
            }

            Button {
                // Continue studying
            } label: {
                Text("Continue studying")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#F5F0E8"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Card 6: Memory verse

struct BereanMemoryCard: View {
    let card: BereanFormationCard
    @State private var revealed = false

    var body: some View {
        guard case .memory(let mv, let verse) = card.data else { return AnyView(EmptyView()) }
        return AnyView(_memoryCard(mv: mv, verse: verse))
    }

    private func _memoryCard(mv: BereanMemoryVerse, verse: BereanVerse) -> some View {
        let pct = Int(mv.strength * 100)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                FormationSectionLabel(icon: "brain", text: "Memory Verse")
                Spacer()
                Text("🔥 \(mv.streak)-day streak")
                    .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.30))
            }

            Text(mv.verseRef)
                .font(.custom("Georgia", size: 20))
                .foregroundStyle(Color(hex: "#F5F0E8"))

            FormationStrengthBar(pct: pct, label: "Memory strength")

            if !revealed {
                VStack(spacing: 12) {
                    Text("Try to recall this verse before revealing it.")
                        .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.45))
                    Button { withAnimation { revealed = true } } label: {
                        Text("Reveal verse")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "#0A0A0F"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(NotifGlassTokens.primaryButtonGradient)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    FormationVerseBlock(text: verse.text)
                    HStack(spacing: 8) {
                        BereanVerseChip(reference: mv.verseRef)
                        BereanMockLabel()
                    }
                    HStack(spacing: 10) {
                        Button {} label: {
                            Text("✓ I remembered it")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: "#0A0A0F"))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(NotifGlassTokens.primaryButtonGradient)
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                        Button { withAnimation { revealed = false } } label: {
                            Text("Practice again")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: "#F5F0E8"))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                        }.buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(20)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Card 7: Seasonal

struct BereanSeasonalCard: View {
    let card: BereanFormationCard

    var body: some View {
        guard case .seasonal(let s) = card.data else { return AnyView(EmptyView()) }
        return AnyView(_seasonalCard(s: s))
    }

    private func _seasonalCard(s: BereanSeasonalRhythm) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FormationSectionLabel(icon: "leaf", text: "Seasonal Rhythm")
            Text(s.liturgicalSeason)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "#3DAA6E"))
                .tracking(1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(hex: "#3DAA6E").opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color(hex: "#3DAA6E").opacity(0.25), lineWidth: 0.5))
            Text(verbatim: "\u{201C}" + s.prompt + "\u{201D}")
                .font(.custom("Georgia", size: 20).italic())
                .foregroundStyle(Color(hex: "#F5F0E8"))
                .lineSpacing(4)
        }
        .padding(20)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Card dispatcher

struct BereanFormationCardRenderer: View {
    let card: BereanFormationCard
    var onWhyTapped: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            cardBody
            // "Why am I seeing this?" link on every card
            Button {
                onWhyTapped?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle").font(.system(size: 10))
                    Text("Why am I seeing this?").font(.system(size: 10))
                }
                .foregroundStyle(Color.white.opacity(0.28))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Why am I seeing this?")
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        switch card.cardType {
        case .verse:     BereanVerseReflectionCard(card: card)
        case .plan:      BereanReadingPlanCard(card: card)
        case .prayer:    BereanPrayerCard(card: card)
        case .sanctuary: BereanSanctuaryCard(card: card)
        case .study:     BereanStudyCard(card: card)
        case .memory:    BereanMemoryCard(card: card)
        case .seasonal:  BereanSeasonalCard(card: card)
        }
    }
}

// MARK: - Crisis Card

struct BereanFormationCrisisCard: View {
    let prayer: BereanPrayerItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "shield.fill").font(.system(size: 10)).foregroundStyle(Color(hex: "#D93025"))
                Text("YOU'RE NOT ALONE")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "#D93025")).tracking(1.5)
            }

            Text("You've been carrying something heavy. Berean can't carry it with you — but people can.")
                .font(.custom("Georgia", size: 19))
                .foregroundStyle(Color(hex: "#F5F0E8"))
                .lineSpacing(3)

            Text("If you're in crisis, please reach out to someone who loves you — your pastor, a trusted friend, or a professional counselor. You don't have to be alone in this.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.50))
                .lineSpacing(3)

            VStack(spacing: 8) {
                crisisResourceButton(title: "988 Suicide & Crisis Lifeline", subtitle: "Call or text 988 — US only")
                crisisResourceButton(title: "Crisis Text Line", subtitle: "Text HOME to 741741")
            }

            // One verse anchor — MOCK LABELED — not AI reflection
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Rectangle().fill(Color(hex: "#8A6F2E")).frame(width: 3).clipShape(Capsule())
                    Text("\"Casting all your anxieties on him, because he cares for you.\"")
                        .font(.custom("Georgia", size: 15).italic())
                        .foregroundStyle(NotifGlassTokens.goldLight)
                        .lineSpacing(3)
                        .padding(.leading, 12)
                }
                HStack(spacing: 8) {
                    BereanVerseChip(reference: "1 Peter 5:7")
                    BereanMockLabel()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "#D93025").opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(hex: "#D93025"), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(hex: "#D93025").opacity(0.12), radius: 20, x: 0, y: 4)
    }

    private func crisisResourceButton(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: "#F5F0E8"))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.35))
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(hex: "#D93025").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(hex: "#D93025").opacity(0.20), lineWidth: 0.5)
        )
    }
}

// MARK: - Why Sheet

struct BereanWhySheet: View {
    let card: BereanFormationCard
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb").font(.system(size: 10)).foregroundStyle(NotifGlassTokens.goldPrimary)
                    Text("WHY AM I SEEING THIS?")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(NotifGlassTokens.goldPrimary).tracking(1.5)
                }

                Text(card.typeLabel)
                    .font(.custom("Georgia", size: 22))
                    .foregroundStyle(Color(hex: "#F5F0E8"))

                Text(BereanFormationSafetyEngine.whySeeingThis(card))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineSpacing(4)

                HStack { Spacer()
                    Button { onClose() } label: {
                        Text("Close")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(hex: "#F5F0E8"))
                            .padding(.horizontal, 24).padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    }.buttonStyle(.plain)
                }
            }
            .padding(24)
            .glassSurface(cornerRadius: 28)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea()
    }
}
