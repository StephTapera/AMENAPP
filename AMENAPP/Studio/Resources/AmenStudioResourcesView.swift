import SwiftUI

struct AmenStudioResourcesView: View {
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared

    private let quickStarts: [AmenStudioQuickStart] = [
        AmenStudioQuickStart(title: "Sermon Clip", subtitle: "Auto-captions + trim", accent: "Clip"),
        AmenStudioQuickStart(title: "Event Flyer", subtitle: "Ready in minutes", accent: "Flyer"),
        AmenStudioQuickStart(title: "Testimony Pack", subtitle: "Story + quote", accent: "Pack"),
        AmenStudioQuickStart(title: "Verse Graphic", subtitle: "Quiet, clean", accent: "Verse")
    ]

    private let resourceSections: [AmenStudioResourceSection] = [
        AmenStudioResourceSection(title: "Prayer", items: ["Morning Peace", "Focus Set", "Healing Night", "Family Calm"]),
        AmenStudioResourceSection(title: "Church", items: ["Sunday Promo", "Service Recap", "Youth Night", "Prayer Night"]),
        AmenStudioResourceSection(title: "Creator", items: ["Testimony Reel", "Story Pack", "Quote Card", "Announcement"])
    ]

    private let recentWork: [AmenStudioRecentWork] = [
        AmenStudioRecentWork(title: "Easter Invite", kind: "Flyer", time: "2h ago"),
        AmenStudioRecentWork(title: "Sunday Reflection", kind: "Clip", time: "Yesterday"),
        AmenStudioRecentWork(title: "Prayer Walk", kind: "Story Pack", time: "3d ago")
    ]

    var body: some View {
        ZStack {
            AmenStudioResourcesBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    quickStartCarousel
                    browseSection
                    recentSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }

            bottomBar
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AMEN Studio")
                .font(AMENFont.bold(32))
                .foregroundStyle(.primary)

            Text("Resources")
                .font(AMENFont.semiBold(18))
                .foregroundStyle(.secondary)

            AmenStudioSearchBar(placeholder: "Search templates, packs, songs")

            if featureFlags.studioEnabled {
                NavigationLink(destination: AMENCreatorHomeView()) {
                    Text("Open Creator")
                        .font(AMENFont.semiBold(14))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.amenGlass(role: .primary, size: .regular, shape: .capsule))
            }
        }
        .padding(16)
        .amenGlassSurface(shape: .rounded(28), background: .balanced, placement: .inline)
    }

    private var quickStartCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick starts")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quickStarts) { quickStart in
                        AmenStudioQuickStartCard(quickStart: quickStart)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Browse resources")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Open library") {}
                    .buttonStyle(.amenGlass(role: .utility, size: .compact, shape: .capsule))
            }

            VStack(spacing: 12) {
                ForEach(resourceSections) { section in
                    AmenStudioResourceSectionCard(section: section)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent work")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("View all") {}
                    .buttonStyle(.amenGlass(role: .utility, size: .compact, shape: .capsule))
            }

            VStack(spacing: 12) {
                ForEach(recentWork) { item in
                    AmenStudioRecentCard(item: item)
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack {
            Spacer()
            AmenStudioBottomBar()
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
    }
}

private struct AmenStudioResourcesBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.white,
                Color.white,
                Color(red: 0.95, green: 0.95, blue: 0.94)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(0.9), Color.clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 220
            )
        )
        .ignoresSafeArea()
    }
}

private struct AmenStudioSearchBar: View {
    let placeholder: String
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .font(AMENFont.medium(14))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .amenGlassSurface(shape: .rounded(18), background: .quiet, placement: .inline)
    }
}

private struct AmenStudioQuickStartCard: View {
    let quickStart: AmenStudioQuickStart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(quickStart.accent.uppercased())
                .font(AMENFont.semiBold(11))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .amenGlassSurface(shape: .capsule, background: .quiet, placement: .inline)

            Text(quickStart.title)
                .font(AMENFont.semiBold(18))
                .foregroundStyle(.primary)

            Text(quickStart.subtitle)
                .font(AMENFont.medium(12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 180)
        .amenGlassSurface(shape: .rounded(26), background: .balanced, placement: .inline)
    }
}

private struct AmenStudioResourceSectionCard: View {
    let section: AmenStudioResourceSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title.uppercased())
                .font(AMENFont.semiBold(11))
                .tracking(2)
                .foregroundStyle(.tertiary)

            AmenStudioFlowLayout(spacing: 8) {
                ForEach(section.items, id: \.self) { item in
                    Text(item)
                        .font(AMENFont.medium(13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .amenGlassSurface(shape: .capsule, background: .quiet, placement: .inline)
                }
            }
        }
        .padding(14)
        .amenGlassSurface(shape: .rounded(24), background: .balanced, placement: .inline)
    }
}

private struct AmenStudioRecentCard: View {
    let item: AmenStudioRecentWork

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)

                Text("\(item.kind) · \(item.time)")
                    .font(AMENFont.medium(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Resume") {}
                .buttonStyle(.amenGlass(role: .primary, size: .compact, shape: .capsule))
        }
        .padding(14)
        .amenGlassSurface(shape: .rounded(22), background: .balanced, placement: .inline)
    }
}

private struct AmenStudioBottomBar: View {
    private let items: [(String, String)] = [
        ("Home", "house"),
        ("Projects", "square.grid.2x2"),
        ("Create", "plus"),
        ("Resources", "sparkles"),
        ("Profile", "person")
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                VStack(spacing: 6) {
                    Image(systemName: item.1)
                        .font(.system(size: 16, weight: .semibold))
                    Text(item.0)
                        .font(AMENFont.medium(10))
                }
                .foregroundStyle(index == 3 ? Color.white : Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .amenGlassSurface(
                    role: index == 3 ? .primary : .neutral,
                    shape: .rounded(20),
                    background: .balanced,
                    placement: .floating,
                    isSelected: index == 3
                )
            }
        }
        .padding(10)
        .amenGlassSurface(shape: .rounded(30), background: .balanced, placement: .floating)
    }
}

private struct AmenStudioQuickStart: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let accent: String
}

private struct AmenStudioResourceSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

private struct AmenStudioRecentWork: Identifiable {
    let id = UUID()
    let title: String
    let kind: String
    let time: String
}

private struct AmenStudioFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth == 0 ? 0 : spacing) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)

        return CGSize(width: maxWidth == 0 ? totalWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: origin, proposal: ProposedViewSize(width: size.width, height: size.height))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    AmenStudioResourcesView()
}
