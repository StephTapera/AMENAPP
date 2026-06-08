// ResourcesContentView.swift
// AMENAPP — Resources tab unique content rails
//
// Four horizontal rails specific to the Resources tab:
//   1. Bible Study Plans
//   2. Daily Devotionals
//   3. Prayer Guides
//   4. Church Resources (links to Find a Church)
//
// Design rules:
//   • Cards use .regularMaterial Liquid Glass background.
//   • Semantic colors only — no hardcoded Color.white or Color.black.
//   • All Text in fixed-size containers gets .minimumScaleFactor + .lineLimit.

import SwiftUI

// MARK: - Data Models

private struct ResourceRailCard: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
}

// MARK: - Static seed data

private let biblePlans: [ResourceRailCard] = [
    ResourceRailCard(icon: "book.fill",            title: "30-Day Psalms",        subtitle: "4 weeks · Praise & Lament",  accentColor: .indigo),
    ResourceRailCard(icon: "cross.fill",           title: "Life of Christ",        subtitle: "6 weeks · Gospel Survey",    accentColor: .blue),
    ResourceRailCard(icon: "star.fill",            title: "Proverbs Deep Dive",    subtitle: "3 weeks · Wisdom Writing",   accentColor: .orange),
    ResourceRailCard(icon: "flame.fill",           title: "Acts & the Church",     subtitle: "5 weeks · Early Church",     accentColor: .red),
    ResourceRailCard(icon: "leaf.fill",            title: "Romans Explained",      subtitle: "8 weeks · Paul's Gospel",    accentColor: .green),
]

private let devotionals: [ResourceRailCard] = [
    ResourceRailCard(icon: "sun.max.fill",         title: "Morning Light",         subtitle: "Daily · 5 min read",         accentColor: .yellow),
    ResourceRailCard(icon: "moon.stars.fill",      title: "Evening Reflection",    subtitle: "Daily · Rest & Gratitude",   accentColor: .purple),
    ResourceRailCard(icon: "heart.fill",           title: "Grace for Today",       subtitle: "Daily · 3 min",              accentColor: .pink),
    ResourceRailCard(icon: "waveform.path",        title: "Breath Prayers",        subtitle: "Daily · Centering",          accentColor: .teal),
    ResourceRailCard(icon: "text.book.closed.fill",title: "Weekly Lectionary",     subtitle: "Weekly · Liturgical",        accentColor: .brown),
    ResourceRailCard(icon: "sparkles",             title: "Advent Season",         subtitle: "Seasonal · 4 weeks",         accentColor: .mint),
]

private let prayerGuides: [ResourceRailCard] = [
    ResourceRailCard(icon: "hands.sparkles.fill",  title: "ACTS Method",           subtitle: "Adoration · Confession · …", accentColor: .purple),
    ResourceRailCard(icon: "person.2.fill",        title: "Praying for Others",    subtitle: "Intercession guide",         accentColor: .blue),
    ResourceRailCard(icon: "globe.americas.fill",  title: "Nations Prayer Map",    subtitle: "31-day world focus",         accentColor: .green),
    ResourceRailCard(icon: "house.fill",           title: "Household Prayers",     subtitle: "Family liturgy",             accentColor: .orange),
    ResourceRailCard(icon: "heart.text.square.fill",title: "Healing & Wholeness", subtitle: "Scripture-led prayer",       accentColor: .red),
]

private let churchResources: [ResourceRailCard] = [
    ResourceRailCard(icon: "mappin.and.ellipse",   title: "Find a Church",         subtitle: "Search near you",            accentColor: .green),
    ResourceRailCard(icon: "calendar",             title: "Church Events",         subtitle: "Upcoming gatherings",        accentColor: .blue),
    ResourceRailCard(icon: "music.note.list",      title: "Worship Sets",          subtitle: "Sunday resources",           accentColor: .purple),
    ResourceRailCard(icon: "person.badge.plus",    title: "Get Connected",         subtitle: "Join a small group",         accentColor: .orange),
]

// MARK: - ResourcesContentView

struct ResourcesContentView: View {

    // Callback so parent can handle navigation (e.g. push Find a Church)
    var onFindChurchTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            rail(
                title: "Bible Study Plans",
                icon: "book.closed.fill",
                cards: biblePlans
            )

            rail(
                title: "Daily Devotionals",
                icon: "sun.and.horizon.fill",
                cards: devotionals
            )

            rail(
                title: "Prayer Guides",
                icon: "hands.sparkles",
                cards: prayerGuides
            )

            churchResourcesRail
        }
        .padding(.top, 4)
    }

    // MARK: - Generic rail builder

    @ViewBuilder
    private func rail(title: String, icon: String, cards: [ResourceRailCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            railHeader(title: title, icon: icon)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(cards) { card in
                        ResourceRailCardView(card: card)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Church Resources rail (tappable Find a Church card)

    @ViewBuilder
    private var churchResourcesRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            railHeader(title: "Church Resources", icon: "building.columns.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(churchResources) { card in
                        if card.title == "Find a Church" {
                            Button { onFindChurchTap?() } label: {
                                ResourceRailCardView(card: card)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ResourceRailCardView(card: card)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Section header

    private func railHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - ResourceRailCardView

private struct ResourceRailCardView: View {
    let card: ResourceRailCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(card.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: card.icon)
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundStyle(card.accentColor)
            }

            // Title
            Text(card.title)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // Subtitle
            Text(card.subtitle)
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(width: 148, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.75)
        )
        .shadow(color: Color(.label).opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ResourcesContentView()
    }
    .background(Color(.systemGroupedBackground))
}
