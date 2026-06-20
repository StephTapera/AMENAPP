//
//  ResourceGlassComponents.swift
//  AMENAPP
//
//  Wave 2 — Reusable production components for the white Liquid Glass Resources home.
//  Each is driven by the Wave 1 view models, degrades gracefully on missing data, and
//  carries accessibility labels. Glass is reserved for pills / hero overlay / search /
//  mini-player; content cards are opaque white (no-glass-on-glass).
//
//  Gated by AMENFeatureFlags.resourcesGlassHomeEnabled (default OFF).
//

import SwiftUI

// MARK: - Shared: artwork (AsyncImage for approved media thumbs, else calm placeholder)

struct RGArtwork: View {
    let imageRef: String?
    let icon: String
    let accent: Color
    var cornerRadius: CGFloat = RGInk.cardCorner

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.22), accent.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if let ref = imageRef, let url = URL(string: ref) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholderIcon: some View {
        Image(systemName: icon)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(accent.opacity(0.85))
    }
}

// MARK: - Shared: glass action pill (the ONE place glass meets media/actions)

struct RGGlassPill: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = RGInk.tan
    var filled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
                }
                Text(title).font(AMENFont.semiBold(13))
            }
            .foregroundStyle(filled ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if filled {
                    Capsule().fill(tint)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(0.30)))
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(ResourceCardPressStyle())
        .accessibilityLabel(Text(title))
    }
}

// MARK: - 1. Recommendation reason pill ("Why this?")

struct ResourceRecommendationReasonPill: View {
    let reason: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(RGInk.tan)
            Text(reason)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(RGInk.tan.opacity(0.10)))
        .overlay(Capsule().strokeBorder(RGInk.tan.opacity(0.22), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Why this resource: \(reason)"))
    }
}

// MARK: - 2. Section header

struct ResourceSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Capsule()
                .fill(RGInk.wine.opacity(0.85))
                .frame(width: 3, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AMENFont.bold(20))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(RGInk.tan)
                }
                .accessibilityLabel(Text("\(actionTitle), \(title)"))
            }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3. Hero banner — split image + glass overlay panel (Img 5, re-skinned white)

struct ResourceHeroBanner: View {
    let content: ResourceHeroContent
    var compactProgress: CGFloat = 0     // 0 = full hero, 1 = collapsed glass header
    var onOpen: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat {
        let full: CGFloat = 188, collapsed: CGFloat = 96
        return full - (full - collapsed) * min(max(compactProgress, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RGArtwork(imageRef: content.imageRef,
                      icon: content.primary?.systemIcon ?? "sparkles",
                      accent: content.accent,
                      cornerRadius: RGInk.heroCorner)

            // Bottom scrim so overlay text always reads
            LinearGradient(
                colors: [.clear, .black.opacity(0.32)],
                startPoint: .center, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: RGInk.heroCorner, style: .continuous))
            .accessibilityHidden(true)

            // Glass overlay panel (one of the sanctioned glass surfaces)
            VStack(alignment: .leading, spacing: 8) {
                Text(content.eyebrow.uppercased())
                    .font(AMENFont.semiBold(11))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.92))
                Text(content.title)
                    .font(AMENFont.bold(19))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if compactProgress < 0.5, !content.chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(content.chips.prefix(3), id: \.self) { chip in
                            Text(chip)
                                .font(AMENFont.semiBold(11))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(.ultraThinMaterial))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.75))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: RGInk.heroCorner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.0)        // panel text sits on the scrim; keep glass for chips only
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: RGInk.heroCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RGInk.heroCorner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 20)
        .contentShape(RoundedRectangle(cornerRadius: RGInk.heroCorner, style: .continuous))
        .onTapGesture { onOpen?() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: compactProgress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(content.eyebrow). \(content.title)"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 4. Smart daily summary card (Img 6, re-skinned white)

struct SmartDailySummaryCard: View {
    let summary: ResourceDailySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RGInk.tan)
                Text(summary.greeting)
                    .font(AMENFont.bold(17))
                    .foregroundStyle(.primary)
            }
            Text(summary.line)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.stats.isEmpty {
                HStack(spacing: 8) {
                    ForEach(summary.stats) { stat in
                        HStack(spacing: 4) {
                            Text(stat.value).font(AMENFont.bold(13)).foregroundStyle(.primary)
                            Text(stat.label).font(AMENFont.regular(12)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous)
            .strokeBorder(RGInk.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(summary.greeting) \(summary.line)"))
    }
}

// MARK: - 5. Filter pill bar (matched-geometry selection)

struct ResourceFilterPillBar: View {
    @Binding var selection: ResourcesView.ResourceCategory
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ResourcesView.ResourceCategory.allCases, id: \.self) { category in
                    let isOn = selection == category
                    Button {
                        if reduceMotion {
                            selection = category
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                selection = category
                            }
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(category.rawValue)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(isOn ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if isOn {
                                    Capsule().fill(Color.primary)
                                        .matchedGeometryEffect(id: "rgPill", in: ns)
                                } else {
                                    Capsule().fill(Color(.secondarySystemBackground))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(category.rawValue))
                    .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - 6. Compact list row (Img 7 — type icon + dotted hairline)

struct ResourceCompactRow: View {
    let item: ResourceGlassItem
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(item.accent.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: item.systemIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.type.label)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                        if let duration = item.duration {
                            Text("· \(duration)")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                if let progress = item.progress {
                    RGProgressRing(progress: progress, tint: item.accent)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)
            if showDivider {
                RGDottedDivider().padding(.leading, 54)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.title), \(item.type.label)\(item.duration.map { ", \($0)" } ?? "")"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Dotted hairline divider (Img 7).
struct RGDottedDivider: View {
    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1.5, 4]))
            .foregroundStyle(RGInk.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// Calm completion ring (Personal Resource Plan + continue progress).
struct RGProgressRing: View {
    let progress: Double          // 0...1
    var tint: Color = RGInk.tan

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityLabel(Text("\(Int((max(0, min(1, progress))) * 100)) percent complete"))
    }
}

// MARK: - 7. Media card (Img 2 — artwork breaks above edge, play + progress)

struct ResourceMediaCard: View {
    let item: ResourceGlassItem
    var width: CGFloat = 220
    var onPlay: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Artwork breaking above the white card edge for depth
            ZStack(alignment: .bottomTrailing) {
                RGArtwork(imageRef: item.imageRef, icon: item.systemIcon, accent: item.accent)
                    .frame(width: width - 24, height: 120)
                    .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 6)
                    .padding(.horizontal, 12)
                if onPlay != nil {
                    Button { onPlay?() } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().fill(item.accent.opacity(0.85)))
                            .overlay(Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white))
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    }
                    .buttonStyle(ResourceCardPressStyle())
                    .padding(20)
                    .accessibilityLabel(Text("Play \(item.title)"))
                }
            }
            .offset(y: -14)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let progress = item.progress {
                    RGProgressBar(progress: progress, tint: item.accent)
                    if let remaining = item.duration {
                        Text("\(remaining) left")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.secondary)
                    }
                } else if let duration = item.duration {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.system(size: 10))
                        Text(duration).font(AMENFont.regular(11))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .frame(width: width, alignment: .leading)
        }
        .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous)
            .strokeBorder(RGInk.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.title), \(item.type.label)\(item.subtitle.map { ", \($0)" } ?? "")"))
    }
}

/// Gentle progress bar for media resume state.
struct RGProgressBar: View {
    let progress: Double
    var tint: Color = RGInk.tan

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: 4)
        .accessibilityLabel(Text("\(Int(max(0, min(1, progress)) * 100)) percent watched"))
    }
}

// MARK: - 8. Continue carousel (parallax, reduce-motion aware)

struct ContinueResourceCarousel: View {
    let items: [ResourceGlassItem]
    var onOpen: (ResourceGlassItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    Button { onOpen(item) } label: {
                        ResourceMediaCard(item: item, onPlay: { onOpen(item) })
                    }
                    .buttonStyle(ResourceCardPressStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)   // room for the artwork that breaks above the edge
            .padding(.bottom, 6)
        }
    }
}

// MARK: - 9. Bundle stack card (Img 1/3 — notched tab + counts + fan on touch)

struct ResourceBundleStackCard: View {
    let bundle: ResourceGlassBundle
    var onPreview: (() -> Void)? = nil

    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fanned backing cards (settle when not touched)
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous)
                        .fill(bundle.accent.opacity(0.12 - Double(i) * 0.04))
                        .frame(height: 116)
                        .padding(.horizontal, CGFloat(10 + i * 6))
                        .rotationEffect(.degrees(reduceMotion ? 0 : (pressed ? Double(i + 1) * 3.0 : Double(i + 1) * 1.2)))
                        .offset(y: CGFloat(-(i + 1) * 6))
                }
                RGArtwork(imageRef: bundle.imageRef, icon: bundle.systemIcon, accent: bundle.accent)
                    .frame(height: 116)
                if bundle.previewCount > 0 {
                    Text("\(bundle.previewCount)")
                        .font(AMENFont.bold(12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Circle().fill(RGInk.wine).opacity(0.92))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(12)
                        .accessibilityHidden(true)
                }
            }

            // Body with the notched folder tab
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bundle.title)
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let subtitle = bundle.subtitle {
                            Text(subtitle)
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if bundle.isOfficial {
                        RGOfficialBadge()
                    }
                }
                if !bundle.counts.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(bundle.counts) { c in
                            HStack(spacing: 4) {
                                Text(c.value).font(AMENFont.bold(13)).foregroundStyle(.primary)
                                Text(c.label).font(AMENFont.regular(12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RGNotchedTopShape(cornerRadius: RGInk.cardCorner, notchWidth: 64, notchDepth: 12)
                    .fill(RGInk.card)
            )
            .offset(y: -10)
        }
        .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous)
            .strokeBorder(RGInk.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 6)
        .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
        .onTapGesture { onPreview?() }
        ._rgPressEvents(pressed: $pressed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(bundle.title) bundle\(bundle.isOfficial ? ", official" : "")"))
        .accessibilityHint(Text("Preview bundle"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Top shape with a folder-tab notch (Img 1).
struct RGNotchedTopShape: Shape {
    var cornerRadius: CGFloat = 24
    var notchWidth: CGFloat = 64
    var notchDepth: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = cornerRadius
        let nx = rect.minX + 18
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + notchDepth + r))
        // notch tab on the top-left
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + notchDepth))
        p.addLine(to: CGPoint(x: nx, y: rect.minY + notchDepth))
        p.addLine(to: CGPoint(x: nx + 10, y: rect.minY))
        p.addLine(to: CGPoint(x: nx + notchWidth, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Verified / official content badge.
struct RGOfficialBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 10, weight: .bold))
            Text("Official").font(AMENFont.semiBold(10))
        }
        .foregroundStyle(RGInk.tan)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(RGInk.tan.opacity(0.12)))
        .accessibilityLabel(Text("Official content"))
    }
}

// MARK: - 10. Search glass bar + suggestion pills (Img 4)

struct ResourceSearchGlassBar: View {
    @Binding var text: String
    var isSearching: Bool = false
    var suggestions: [String] = []
    var onSubmit: () -> Void
    var onSuggestion: (String) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Search resources, scripture, speakers…", text: $text)
                    .font(AMENFont.regular(15))
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(Text("Search resources"))
                if isSearching {
                    ProgressView().controlSize(.small)
                } else if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("Clear search"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.75))
            .overlay(Capsule().strokeBorder(RGInk.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)

            if text.isEmpty, !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { onSuggestion(s) } label: {
                                HStack(spacing: 5) {
                                    Text(s).font(AMENFont.regular(13)).foregroundStyle(.primary)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(RGInk.tan)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(.ultraThinMaterial))
                                .overlay(Capsule().strokeBorder(RGInk.hairline, lineWidth: 1))
                            }
                            .buttonStyle(ResourceCardPressStyle())
                            .accessibilityLabel(Text("Suggested search: \(s)"))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 11. Mini player (glass surface)

struct ResourceMiniPlayer: View {
    let item: ResourceGlassItem
    var isPlaying: Bool = true
    var onToggle: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RGArtwork(imageRef: item.imageRef, icon: item.systemIcon, accent: item.accent,
                      cornerRadius: 10)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(AMENFont.semiBold(13)).foregroundStyle(.primary).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(AMENFont.regular(11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel(Text(isPlaying ? "Pause" : "Play"))
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("Close player"))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Press-events helper (fan + scale on touch, reduce-motion handled by caller)

private struct RGPressEvents: ViewModifier {
    @Binding var pressed: Bool
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pressed = true } } }
                .onEnded { _ in withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pressed = false } }
        )
    }
}

extension View {
    func _rgPressEvents(pressed: Binding<Bool>) -> some View {
        modifier(RGPressEvents(pressed: pressed))
    }
}
