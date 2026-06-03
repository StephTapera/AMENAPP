// BereanDailyFormationFeedView.swift
// AMENAPP — Berean Daily Formation Companion
//
// Morning feed: arc stack + full card list + crisis banner + why sheet.
// Crisis items appear above arc only; NEVER as arc or feed cards.

import SwiftUI

struct BereanDailyFormationFeedView: View {
    let userName: String
    let cards: [BereanFormationCard]
    let prayerList: [BereanPrayerItem]

    @State private var arcIndex: Int = 0
    @State private var whyCard: BereanFormationCard? = nil

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
                            BereanCrisisCard(prayer: item)
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
                                .font(.system(size: 10)).foregroundStyle(NotifGlassTokens.goldPrimary)
                            Text("YOUR BEREAN TODAY")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(NotifGlassTokens.goldPrimary).tracking(2)
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
            .background(
                LinearGradient(
                    colors: [Color(hex: "#0A0A0F"), Color(hex: "#111118")],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()
            )

            // WhySheet overlay
            if let card = whyCard {
                BereanWhySheet(card: card) { whyCard = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: whyCard == nil)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10)).foregroundStyle(NotifGlassTokens.goldPrimary)
                    Text("Berean")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotifGlassTokens.goldPrimary).tracking(1.5)
                }
                Text("Good morning, \(userName).")
                    .font(.custom("Georgia", size: 28).weight(.light))
                    .foregroundStyle(Color(hex: "#F5F0E8"))
                Text("\(dateLabel) · \(cards.count) card\(cards.count == 1 ? "" : "s") ready")
                    .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.35))
            }
            Spacer()
            // Gold emblem
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#C9A84C"), Color(hex: "#8A6F2E")],
                            center: UnitPoint(x: 0.38, y: 0.38),
                            startRadius: 0, endRadius: 20
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Color(hex: "#0A0A0F"))
            }
        }
    }
}

// MARK: - Empty state

private struct BereanEmptyFeedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(NotifGlassTokens.goldPrimary.opacity(0.6))
            Text("Your Berean is being prepared overnight.")
                .font(.custom("Georgia", size: 22))
                .foregroundStyle(Color(hex: "#F5F0E8")).multilineTextAlignment(.center).lineSpacing(4)
            Text("Come back in the morning.")
                .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.35))
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
