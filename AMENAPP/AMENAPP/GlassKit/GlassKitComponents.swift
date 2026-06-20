//  GlassKitComponents.swift
//  AMEN GlassKit — Liquid Glass card system (spec §2). Shared by Connect AND Spaces.
//  Built once; both surfaces adopt. Presentation only — never mutates a model.
//
//  NEW FILE — needs target membership added in Xcode (see report). Gate adoption behind
//  AMENFeatureFlags.glasskitCardSystemEnabled (default OFF) at the call site.
//
//  DESIGN LAW (spec §2): cards are OPAQUE WHITE (`.glassCardSurface`). Glass is reserved for
//  the action pill ON MEDIA (`GlassMediaPillStyle`), floating controls, and sheets. Hero / thumb
//  media is supplied by the CALL SITE via a ViewBuilder so MEDIA-GATE stays enforced upstream
//  (a ref that isn't approved simply isn't passed in). Motion respects reduce-motion.

import SwiftUI

// MARK: - Public data shapes (GlassKit-local; Connect maps its contracts onto these)

struct GlassStatColumn: Identifiable {
    let id = UUID()
    let value: String          // bold
    let caption: String        // gray
    init(value: String, caption: String) { self.value = value; self.caption = caption }
}

enum GlassFactStatus { case ok, warn }

struct GlassFact: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let status: GlassFactStatus?
    init(label: String, value: String, status: GlassFactStatus? = nil) {
        self.label = label; self.value = value; self.status = status
    }
}

struct GlassPillAction: Identifiable {
    let id = UUID()
    let label: String
    let action: () -> Void
    init(label: String, action: @escaping () -> Void) { self.label = label; self.action = action }
}

struct GlassMediaCardModel {
    let title: String
    let subtitle: String?
    let actionPillLabel: String?      // glass pill ON media; nil → no pill
    let metaLine: String?             // expanded: "Hard · 1886 by …" → church analog
    let stats: [GlassStatColumn]      // expanded: up to 3 columns
    let description: String?          // expanded: 1–2 paragraphs

    init(title: String, subtitle: String? = nil, actionPillLabel: String? = nil,
         metaLine: String? = nil, stats: [GlassStatColumn] = [], description: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.actionPillLabel = actionPillLabel
        self.metaLine = metaLine; self.stats = stats; self.description = description
    }
}

// MARK: - §2.1 GlassMediaCard (images 3,4,5)

/// The primary card. Collapsed = hero + overlay. Expanded = hero + body (meta, stats, thumb, copy).
/// `hero` and `thumb` are call-site ViewBuilders so media loading + MEDIA-GATE live upstream.
struct GlassMediaCard<Hero: View>: View {
    let model: GlassMediaCardModel
    var expandable: Bool = true
    var startExpanded: Bool = false
    var thumb: AnyView? = nil
    var onAction: (() -> Void)? = nil
    @ViewBuilder var hero: () -> Hero

    @State private var isExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasBody: Bool {
        model.metaLine != nil || !model.stats.isEmpty || model.description != nil || thumb != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroZone
            if expandable && hasBody && isExpanded {
                bodyZone
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if expandable && hasBody {
                footer
            }
        }
        .glassCardSurface()
        .onAppear { isExpanded = startExpanded }
    }

    private var heroZone: some View {
        hero()
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) { titleOverlay.padding(16) }
            .overlay(alignment: .bottomTrailing) { actionPill.padding(16) }
            .clipShape(RoundedRectangle(cornerRadius: GlassKitTokens.cardCorner, style: .continuous))
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
            if let subtitle = model.subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
    }

    @ViewBuilder private var actionPill: some View {
        if let label = model.actionPillLabel {
            Button(label) { onAction?() }
                .buttonStyle(GlassMediaPillStyle())
        }
    }

    private var bodyZone: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let meta = model.metaLine {
                Text(meta)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GlassKitTokens.inkSecondary)
            }
            if !model.stats.isEmpty {
                GlassStatRow(columns: model.stats)
            }
            if thumb != nil || model.description != nil {
                HStack(alignment: .top, spacing: 14) {
                    if let thumb { thumb }
                    if let desc = model.description {
                        Text(desc)
                            .font(.system(size: 14))
                            .foregroundStyle(GlassKitTokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            Spacer()
            ChevronToggle(isExpanded: $isExpanded)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
    }

    private func toggle() {
        if reduceMotion { isExpanded.toggle() }
        else { withAnimation(.spring(response: GlassKitTokens.motionNormal, dampingFraction: 0.85)) { isExpanded.toggle() } }
    }
}

// MARK: - ChevronToggle (image 5)

struct ChevronToggle: View {
    @Binding var isExpanded: Bool
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(GlassKitTokens.inkTertiary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
    }
}

// MARK: - GlassStatRow (3-up)

struct GlassStatRow: View {
    let columns: [GlassStatColumn]   // renders up to 3
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(columns.prefix(3))) { col in
                VStack(spacing: 3) {
                    Text(col.value)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GlassKitTokens.ink)
                    Text(col.caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GlassKitTokens.inkTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - GlassPreviewThumb (rounded square)

struct GlassPreviewThumb<Content: View>: View {
    var size: CGFloat = 72
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: GlassKitTokens.thumbCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GlassKitTokens.thumbCorner, style: .continuous)
                    .stroke(GlassKitTokens.divider, lineWidth: 0.5)
            )
    }
}

// MARK: - GlassFactCard (image 2 — Concierge answers)

struct GlassFactCard: View {
    let title: String
    let summary: String
    let facts: [GlassFact]
    var actions: [GlassPillAction] = []
    var sources: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(GlassKitTokens.ink)
            Text(summary)
                .font(.system(size: 15))
                .foregroundStyle(GlassKitTokens.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !facts.isEmpty {
                VStack(spacing: 0) {
                    ForEach(facts) { fact in
                        factRow(fact)
                        if fact.id != facts.last?.id {
                            Divider().background(GlassKitTokens.divider)
                        }
                    }
                }
            }

            if !actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(actions) { a in
                        Button(a.label, action: a.action)
                            .buttonStyle(GlassKitSolidPillStyle())
                    }
                }
            }

            if !sources.isEmpty {
                Text("Sources: " + sources.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(GlassKitTokens.inkTertiary)
            }
        }
        .padding(18)
        .glassCardSurface()
    }

    private func factRow(_ fact: GlassFact) -> some View {
        HStack(spacing: 8) {
            Text(fact.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(GlassKitTokens.inkSecondary)
            Spacer(minLength: 12)
            Text(fact.value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GlassKitTokens.ink)
            if let status = fact.status {
                Image(systemName: status == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(status == .ok ? GlassKitTokens.statusOk : GlassKitTokens.statusWarn)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - GlassEyebrow (image 3 — "UP NEXT")

struct GlassEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(GlassKitTokens.inkTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - EmphasisText (image 3 — gray copy with inline bold black)

struct EmphasisText: View {
    let segments: [(text: String, emphasized: Bool)]
    init(_ segments: [(text: String, emphasized: Bool)]) { self.segments = segments }

    var body: some View {
        segments.reduce(Text("")) { acc, seg in
            acc + Text(seg.text)
                .font(.system(size: 15, weight: seg.emphasized ? .bold : .regular))
                .foregroundColor(seg.emphasized ? GlassKitTokens.ink : GlassKitTokens.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
