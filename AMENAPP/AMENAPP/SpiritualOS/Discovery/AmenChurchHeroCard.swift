import SwiftUI

// MARK: - Church Hero Data

struct AmenChurchHeroData: Identifiable {
    let id: String
    let name: String
    let city: String
    let state: String
    let denomination: String
    let rating: Double
    let distanceMiles: Double
    let memberCount: Int?
    let sizeRange: String?          // display string e.g. "500–1000"
    let serviceLengthMinutes: Int?
    let services: [ChurchHeroService]
    let pastor: String?
    let atmosphere: [String]
    let aiSummary: String?
    let aiMatchReasons: [String]
    let badges: [String]            // max 3 shown as floating pills on image
    let heroImageURL: URL?
    let hasKids: Bool
    let hasYouth: Bool
    let hasLivestream: Bool

    var distanceLabel: String { String(format: "%.1f mi", distanceMiles) }

    var memberLabel: String {
        guard let n = memberCount else { return sizeRange ?? "—" }
        return n >= 1000 ? "\(n / 1000)K Members" : "\(n) Members"
    }

    var serviceLengthLabel: String {
        guard let m = serviceLengthMinutes else { return "—" }
        return "\(m) min"
    }
}

struct ChurchHeroService: Identifiable {
    let id = UUID()
    let time: String
}

// MARK: - Church Hero Card

struct AmenChurchHeroCard: View {
    let church: AmenChurchHeroData
    var onPlanVisit: () -> Void = {}
    var onDirections: () -> Void = {}
    var onSave: () -> Void = {}
    var onShare: () -> Void = {}

    var body: some View {
        AmenUniversalHeroCard(
            heroURL: church.heroImageURL,
            title: church.name,
            subtitle: "\(church.city), \(church.state)",
            ctaLabel: "Plan Visit",
            badges: church.badges,
            onCTA: onPlanVisit
        ) {
            expandedBody
        }
    }

    // MARK: - Expanded content

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerRow
            actionRow
            Divider()
            servicesSection
            amenitiesRow
            Divider()
            statsRow
            if let p = church.pastor {
                pastorRow(p)
            }
            if let sr = church.sizeRange {
                churchSizeRow(sr)
            }
            if !church.atmosphere.isEmpty {
                atmosphereSection
            }
            if let summary = church.aiSummary {
                aiSummarySection(summary)
            }
            if !church.aiMatchReasons.isEmpty {
                aiMatchSection
            }
        }
    }

    // MARK: Header — denomination, rating, distance

    private var headerRow: some View {
        HStack(spacing: 0) {
            Label(church.denomination, systemImage: "building.columns")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text(String(format: "%.1f", church.rating))
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.trailing, 12)

            HStack(spacing: 3) {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(church.distanceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Action row — Directions | Save | Share

    private var actionRow: some View {
        HStack(spacing: 10) {
            ChurchActionPill(label: "Directions", icon: "arrow.triangle.turn.up.right.circle", action: onDirections)
            ChurchActionPill(label: "Save", icon: "bookmark", action: onSave)
            ChurchActionPill(label: "Share", icon: "square.and.arrow.up", action: onShare)
        }
    }

    // MARK: Services

    @ViewBuilder
    private var servicesSection: some View {
        if !church.services.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sunday Services")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(church.services) { service in
                        Text(service.time)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: Amenities — Kids / Youth / Livestream

    private var amenitiesRow: some View {
        HStack(spacing: 8) {
            if church.hasKids {
                AmenityTag(label: "Kids Available", icon: "figure.and.child.holdinghands")
            }
            if church.hasYouth {
                AmenityTag(label: "Youth Available", icon: "person.3")
            }
            if church.hasLivestream {
                AmenityTag(label: "Livestream", icon: "dot.radiowaves.right")
            }
            Spacer()
        }
    }

    // MARK: Stats row — Distance | Size | Service Length

    private var statsRow: some View {
        HStack(spacing: 0) {
            HeroStatCell(value: church.distanceLabel, label: "Distance")
            Divider().frame(height: 32)
            HeroStatCell(value: church.memberLabel, label: "Size")
            Divider().frame(height: 32)
            HeroStatCell(value: church.serviceLengthLabel, label: "Service")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Pastor

    private func pastorRow(_ name: String) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pastor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.subheadline.weight(.medium))
                }
            } icon: {
                Image(systemName: "person.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Church size

    private func churchSizeRow(_ range: String) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Church Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(range)
                        .font(.subheadline.weight(.medium))
                }
            } icon: {
                Image(systemName: "person.2.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Atmosphere tags

    private var atmosphereSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Atmosphere", systemImage: "theatermasks")
                .font(.subheadline.weight(.semibold))
            ChurchTagFlow(tags: church.atmosphere)
        }
    }

    // MARK: AI Summary

    private func aiSummarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What To Expect", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: AI Match

    private var aiMatchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Why This Matches You", systemImage: "brain")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(church.aiMatchReasons.prefix(4), id: \.self) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
    }
}

// MARK: - Supporting Components

private struct ChurchActionPill: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground), in: Capsule())
        }
    }
}

private struct AmenityTag: View {
    let label: String
    let icon: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemBackground), in: Capsule())
    }
}

// Wrapping tag row using Layout API (iOS 16+)
private struct ChurchTagFlow: View {
    let tags: [String]

    var body: some View {
        AmenFlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
            }
        }
    }
}

// MARK: - Flow Layout

struct AmenFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let gap = rowWidth > 0 ? spacing : 0
            if rowWidth + gap + size.width > width {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Church Model Bridge

extension AmenChurchHeroData {
    /// Bridges the lightweight `Church` model from FindChurchView into a hero card.
    /// Fields absent from `Church` (rating, members, pastor, AI data) default to nil/empty
    /// and can be enriched with a subsequent Firestore fetch.
    init(from church: Church) {
        let parts = church.address.components(separatedBy: ",")
        let city = parts.count >= 2
            ? parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
            : church.address
        let stateZip = parts.last?.trimmingCharacters(in: .whitespaces) ?? ""
        let state = stateZip.components(separatedBy: " ").first ?? stateZip

        self.init(
            id: church.id.uuidString,
            name: church.name,
            city: city,
            state: state,
            denomination: church.denomination,
            rating: 0.0,
            distanceMiles: church.distanceValue / 1609.34,
            memberCount: nil,
            sizeRange: nil,
            serviceLengthMinutes: nil,
            services: [ChurchHeroService(time: church.serviceTime)],
            pastor: nil,
            atmosphere: [],
            aiSummary: nil,
            aiMatchReasons: [],
            badges: church.denomination.isEmpty ? [] : [church.denomination],
            heroImageURL: nil,
            hasKids: false,
            hasYouth: false,
            hasLivestream: false
        )
    }
}

// MARK: - Preview

#Preview("Church Hero Card — Expanded") {
    ScrollView {
        AmenChurchHeroCard(
            church: AmenChurchHeroData(
                id: "crosspoint",
                name: "Crosspoint Church",
                city: "Phoenix",
                state: "Arizona",
                denomination: "Non-Denominational",
                rating: 4.8,
                distanceMiles: 3.2,
                memberCount: 850,
                sizeRange: "500–1000",
                serviceLengthMinutes: 75,
                services: [
                    ChurchHeroService(time: "9:00 AM"),
                    ChurchHeroService(time: "11:00 AM")
                ],
                pastor: nil,
                atmosphere: ["Family", "Worship", "Bible Teaching", "Young Adults"],
                aiSummary: "Contemporary worship, strong kids ministry, active young adult community, casual dress environment.",
                aiMatchReasons: [
                    "Matches your interest in Bible study",
                    "Active young adults community",
                    "Strong community groups",
                    "Contemporary worship style"
                ],
                badges: ["Young Adults", "Kids", "Bible Focused"],
                heroImageURL: nil,
                hasKids: true,
                hasYouth: true,
                hasLivestream: true
            )
        )
        .padding()
    }
}
