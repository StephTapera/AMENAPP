// FROZEN — Wave 0 contract. Changes require orchestrator approval.

import SwiftUI

enum ChurchNoteSmartObjectPresentation {
    static func iconName(for type: ChurchNoteSmartObjectType) -> String {
        switch type {
        case .church: return "building.columns"
        case .scripture: return "book"
        case .sermonVideo: return "play.rectangle"
        case .audio: return "waveform"
        case .event: return "calendar"
        case .location: return "map"
        case .prayer: return "hands.sparkles"
        case .resource: return "books.vertical"
        case .group: return "person.3"
        case .person: return "person.crop.circle"
        case .song: return "music.note"
        case .findChurchIntent: return "location.magnifyingglass"
        case .quote: return "quote.opening"
        case .mixed: return "square.stack.3d.up"
        }
    }

    static func accessibilityLabel(for object: ChurchNoteSmartObject) -> String {
        if object.shouldRenderFallback {
            return "Link fallback, \(object.fallback.title)"
        }

        let title = object.previewState.title
        let correction = object.needsCorrectionAffordance ? ", needs confirmation" : ""
        return "Smart church note object, \(title)\(correction)"
    }

    static func fallbackReasonText(for reason: ChurchNoteSmartFallbackReason) -> String {
        switch reason {
        case .lowConfidence: return "Review link"
        case .pendingSafety: return "Checking"
        case .restrictedSafety: return "Limited"
        case .blockedSafety: return "Unavailable"
        case .unsupported: return "Open link"
        }
    }
}

struct ChurchNoteGlassCard<Content: View>: View {
    let accent: Color
    let cornerRadius: CGFloat
    let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        accent: Color = ChurchNotesDesignTokens.Colors.olive,
        cornerRadius: CGFloat = 26,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.accent = accent
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .padding(18)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.18 : 0.08), lineWidth: contrast == .increased ? 1 : 0.5)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
            .amenNativeGlassEffect(accent: accent, cornerRadius: cornerRadius, reduceTransparency: reduceTransparency)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(hex: "FCFBF8").opacity(0.94))
                .overlay(alignment: .topLeading) {
                    accent.opacity(0.10)
                }
        }
    }
}

struct NoteMetaPill: View {
    let title: String
    let systemImage: String?
    let accent: Color

    init(_ title: String, systemImage: String? = nil, accent: Color = ChurchNotesDesignTokens.Colors.slate) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.primary.opacity(0.82))
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Capsule(style: .continuous).fill(Color(.systemBackground).opacity(0.72)))
        .overlay(Capsule(style: .continuous).strokeBorder(accent.opacity(0.16), lineWidth: 0.5))
        .accessibilityLabel(title)
    }
}

struct ChurchNoteSmartScripturePill: View {
    let reference: String
    let accent: Color
    let action: () -> Void

    init(reference: String, accent: Color = ChurchNotesDesignTokens.Colors.olive, action: @escaping () -> Void = {}) {
        self.reference = reference
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(reference, systemImage: "book")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.88))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .background(Capsule(style: .continuous).fill(accent.opacity(0.12)))
        .overlay(Capsule(style: .continuous).strokeBorder(accent.opacity(0.22), lineWidth: 0.5))
        .amenNativeGlassEffect(accent: accent, cornerRadius: 22, reduceTransparency: false)
        .accessibilityLabel("Open scripture, \(reference)")
    }
}

struct PrayerActionPill: View {
    let title: String
    let action: () -> Void

    init(title: String = "Pray", action: @escaping () -> Void = {}) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "hands.sparkles")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.88))
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .background(Capsule(style: .continuous).fill(ChurchNotesDesignTokens.Colors.rose.opacity(0.12)))
        .overlay(Capsule(style: .continuous).strokeBorder(ChurchNotesDesignTokens.Colors.rose.opacity(0.22), lineWidth: 0.5))
        .amenNativeGlassEffect(accent: ChurchNotesDesignTokens.Colors.rose, cornerRadius: 22, reduceTransparency: false)
        .accessibilityLabel(title)
    }
}

struct SmartObjectPill: View {
    let object: ChurchNoteSmartObject
    let onAction: (ChurchNoteSmartActionKind, ChurchNoteSmartObject) -> Void

    init(
        object: ChurchNoteSmartObject,
        onAction: @escaping (ChurchNoteSmartActionKind, ChurchNoteSmartObject) -> Void = { _, _ in }
    ) {
        self.object = object
        self.onAction = onAction
    }

    @ViewBuilder
    var body: some View {
        switch object.renderState {
        case .interactive, .confirmationRequired:
            interactivePill
        case .fallback:
            fallbackPill
        case .pendingSkeleton:
            pendingSkeletonPill
        case .removed:
            EmptyView()
        }
    }

    private var accent: Color {
        object.previewState.accentHex.map(Color.init(hex:)) ?? defaultAccent
    }

    private var defaultAccent: Color {
        switch object.type {
        case .scripture: return ChurchNotesDesignTokens.Colors.olive
        case .prayer: return ChurchNotesDesignTokens.Colors.rose
        case .event: return ChurchNotesDesignTokens.Colors.gold
        case .location, .findChurchIntent, .church: return ChurchNotesDesignTokens.Colors.calmBlue
        case .song, .audio, .sermonVideo: return Color.accentColor
        case .quote: return ChurchNotesDesignTokens.Colors.slate
        case .mixed, .resource, .group, .person: return ChurchNotesDesignTokens.Colors.slate
        }
    }

    private var primaryAction: ChurchNoteSmartActionKind {
        object.actionSet.first?.kind ?? .open
    }

    private var interactivePill: some View {
        Button { onAction(primaryAction, object) } label: {
            HStack(spacing: 8) {
                Image(systemName: ChurchNoteSmartObjectPresentation.iconName(for: object.type))
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(object.previewState.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if object.needsCorrectionAffordance {
                        Text("Confirm")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(Color.primary.opacity(0.88))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .background(Capsule(style: .continuous).fill(accent.opacity(0.12)))
        .overlay(Capsule(style: .continuous).strokeBorder(accent.opacity(0.24), lineWidth: 0.5))
        .amenNativeGlassEffect(accent: accent, cornerRadius: 24, reduceTransparency: false)
        .accessibilityLabel(ChurchNoteSmartObjectPresentation.accessibilityLabel(for: object))
    }

    private var fallbackPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.subheadline.weight(.semibold))
            Text(object.fallback.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(ChurchNoteSmartObjectPresentation.fallbackReasonText(for: ChurchNoteSmartFallbackReason(object: object)))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.primary.opacity(0.72))
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Capsule(style: .continuous).fill(Color(.secondarySystemGroupedBackground).opacity(0.86)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityLabel(ChurchNoteSmartObjectPresentation.accessibilityLabel(for: object))
    }

    private var pendingSkeletonPill: some View {
        HStack(spacing: 8) {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 18, height: 18)
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 112, height: 12)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Capsule(style: .continuous).fill(Color(.secondarySystemGroupedBackground).opacity(0.72)))
        .redacted(reason: .placeholder)
        .accessibilityLabel("Smart object pending safety review")
    }
}

struct FloatingActionDock: View {
    let actions: [ChurchNoteSmartAction]
    let onAction: (ChurchNoteSmartActionKind) -> Void

    init(actions: [ChurchNoteSmartAction], onAction: @escaping (ChurchNoteSmartActionKind) -> Void = { _ in }) {
        self.actions = actions
        self.onAction = onAction
    }

    var body: some View {
        AmenLiquidGlassControlDock(placement: .bottom) {
            ForEach(actions) { action in
                AmenLiquidGlassPillButton(
                    title: action.title,
                    systemImage: action.requiresPremium ? "lock" : action.systemImage,
                    isLoading: false,
                    isDisabled: false
                ) {
                    onAction(action.kind)
                }
            }
        }
    }
}

struct ChurchNoteSmartFeedCard: View {
    let noteTitle: String
    let churchName: String?
    let noteType: String
    let speaker: String?
    let dateText: String?
    let summary: String?
    let smartObjects: [ChurchNoteSmartObject]
    let actions: [ChurchNoteSmartAction]
    let onAction: (ChurchNoteSmartActionKind, ChurchNoteSmartObject?) -> Void

    init(
        noteTitle: String,
        churchName: String? = nil,
        noteType: String = "Note",
        speaker: String? = nil,
        dateText: String? = nil,
        summary: String? = nil,
        smartObjects: [ChurchNoteSmartObject] = [],
        actions: [ChurchNoteSmartAction] = [.readNote, .save, .pray, .discuss],
        onAction: @escaping (ChurchNoteSmartActionKind, ChurchNoteSmartObject?) -> Void = { _, _ in }
    ) {
        self.noteTitle = noteTitle
        self.churchName = churchName
        self.noteType = noteType
        self.speaker = speaker
        self.dateText = dateText
        self.summary = summary
        self.smartObjects = smartObjects
        self.actions = actions
        self.onAction = onAction
    }

    var body: some View {
        ChurchNoteGlassCard(accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if let churchName, !churchName.isEmpty {
                        NoteMetaPill(churchName, systemImage: "building.columns", accent: accent)
                    }
                    NoteMetaPill(noteType, systemImage: "doc.text", accent: accent)
                }

                if metadataText != nil {
                    Text(metadataText ?? "")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(noteTitle)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }

                if !smartObjects.isEmpty {
                    smartObjectRow
                }

                actionRow
            }
        }
        .background(Color(hex: "FCFBF8"))
    }

    private var accent: Color {
        smartObjects.first?.previewState.accentHex.map(Color.init(hex:)) ?? ChurchNotesDesignTokens.Colors.olive
    }

    private var metadataText: String? {
        [speaker, dateText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")
            .nilIfEmpty
    }

    private var smartObjectRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(smartObjects.prefix(3))) { object in
                    SmartObjectPill(object: object) { kind, tappedObject in
                        onAction(kind, tappedObject)
                    }
                }

                if smartObjects.count > 3 {
                    NoteMetaPill("+\(smartObjects.count - 3) more", systemImage: "ellipsis", accent: accent)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in
                Button { onAction(action.kind, nil) } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.78))
                .background(Capsule(style: .continuous).fill(Color(.systemBackground).opacity(0.70)))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .accessibilityLabel(action.title)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func amenNativeGlassEffect(accent: Color, cornerRadius: CGFloat, reduceTransparency: Bool) -> some View {
        if reduceTransparency {
            self
        } else if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.tint(accent.opacity(0.14)).interactive(),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#Preview("Church Note Smart Feed Card") {
    ChurchNoteSmartFeedCard(
        noteTitle: "Walking by Faith When It Feels Silent",
        churchName: "Grace Community",
        noteType: "Sermon Note",
        speaker: "Pastor John",
        dateText: "June 14",
        summary: "Three key points from today's message on trust, patience, and faithful action.",
        smartObjects: [
            ChurchNoteSmartObject(
                type: .scripture,
                source: .textDetection,
                confidence: 0.94,
                privacyLevel: .churchOnly,
                actionSet: [.readNote, .save, .discuss],
                previewState: ChurchNoteSmartPreviewPayload(title: "Hebrews 11:1", accentHex: "5C7A4C"),
                fallback: ChurchNotePlainLinkFallback(title: "Hebrews 11:1"),
                safetyStatus: .approved
            )
        ]
    )
    .padding()
    .background(Color(hex: "FCFBF8"))
}
