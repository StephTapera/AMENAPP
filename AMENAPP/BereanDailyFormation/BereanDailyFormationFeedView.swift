// BereanDailyFormationFeedView.swift
// AMENAPP — Berean Daily Formation Companion
//
// Morning feed: arc stack + full card list + crisis banner + why sheet.
// Crisis items appear above arc only; NEVER as arc or feed cards.

import SwiftUI
import FirebaseAuth

struct BereanDailyFormationFeedView: View {
    let userName: String
    let cards: [BereanFormationCard]
    let prayerList: [BereanPrayerItem]

    @State private var arcIndex: Int = 0
    @State private var whyCard: BereanFormationCard? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private var crisisItems: [BereanPrayerItem] {
        BereanFormationSafetyEngine.crisisItems(from: prayerList)
    }

    private var dateLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        return fmt.string(from: Date())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerView
                        .padding(.top, 56)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Crisis banner — above arc, never inside arc
                    if !crisisItems.isEmpty {
                        ForEach(crisisItems) { item in
                            BereanFormationCrisisCard(prayer: item)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                        }
                    }

                    // Arc card stack
                    if !cards.isEmpty {
                        BereanArcCardStackView(
                            cards: cards,
                            activeIndex: $arcIndex,
                            onWhyTapped: { whyCard = $0 }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }

                    // Briefing section label
                    if !cards.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.systemScaled(10)).foregroundStyle(Color.accentColor)
                            Text("YOUR BEREAN TODAY")
                                .font(.systemScaled(10, weight: .semibold))
                                .foregroundStyle(Color.accentColor).tracking(2)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 16)
                    }

                    // Full card list
                    VStack(spacing: 16) {
                        ForEach(cards) { card in
                            BereanFormationCardRenderer(card: card) {
                                whyCard = card
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 80)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())

            // WhySheet overlay
            if let card = whyCard {
                BereanWhySheet(card: card) { whyCard = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: whyCard == nil)
        .task(id: cards.map(\.id).joined()) {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            // A7-P1: streak counter removed — record completion without incrementing streakDay
            for card in cards {
                let kind: FormationCardKind
                switch card.cardType {
                case .verse, .plan, .memory, .study: kind = .scripture
                case .prayer: kind = .prayer
                case .sanctuary, .seasonal: kind = .reflection
                }
                var entry = BereanFormationEntry(uid: uid, cardKind: kind, streakDay: 0)
                entry.completedAt = Date().timeIntervalSince1970
                await FormationOSIntegrationService.shared.recordCardCompletion(uid: uid, entry: entry)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.systemScaled(10)).foregroundStyle(Color.accentColor)
                    Text("Berean")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(Color.accentColor).tracking(1.5)
                }
                Text("Good morning, \(userName).")
                    .font(.title2.bold())
                    .foregroundStyle(Color.primary)
                Text("\(dateLabel) · \(cards.count) card\(cards.count == 1 ? "" : "s") ready")
                    .font(.systemScaled(12)).foregroundStyle(Color.secondary)
            }
            Spacer()
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(22))
                    .foregroundStyle(Color.secondary)
            }
            .accessibilityLabel("Close Berean Daily Formation")
        }
    }
}

// MARK: - Empty state

private struct BereanEmptyFeedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle")
                .font(.systemScaled(36, weight: .ultraLight))
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text("Your Berean is being prepared overnight.")
                .font(.title2.bold())
                .foregroundStyle(Color.primary).multilineTextAlignment(.center).lineSpacing(4)
            Text("Come back in the morning.")
                .font(.systemScaled(13)).foregroundStyle(Color.secondary)
        }
        .padding(32).glassSurface(cornerRadius: 20).padding(.horizontal, 32)
    }
}

#Preview {
    let prefs = BereanFormationPrefs(selectedTopics: ["verse", "plan", "prayer", "sanctuary", "memory", "seasonal"], consents: [:])
    let cards = BereanFormationService.assembleCards(
        readingPlan: BereanMockData.readingPlan,
        prayerList: BereanMockData.prayerList,
        sanctuaries: BereanMockData.sanctuaries,
        highlights: BereanMockData.highlights,
        memoryVerses: BereanMockData.memoryVerses,
        seasonal: BereanMockData.seasonal,
        translationPref: "ESV",
        selectedTopics: prefs.selectedTopics
    )
    return BereanDailyFormationFeedView(
        userName: BereanMockUser.name,
        cards: cards,
        prayerList: BereanMockData.prayerList
    )
}
