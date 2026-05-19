import SwiftUI

struct AmenImmersiveMediaChromeAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let accessibilityHint: String
    let action: () -> Void

    init(
        id: String? = nil,
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        accessibilityHint: String = "",
        action: @escaping () -> Void
    ) {
        self.id = id ?? "\(title.lowercased())_\(systemImage)"
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.accessibilityHint = accessibilityHint
        self.action = action
    }
}

enum AmenImmersivePillType: String, CaseIterable {
    case translate
    case summarize
    case askBerean
    case saveToChurchNotes
    case reflectInSelah
    case reportSafety
}

struct AmenImmersiveEligibilityInput {
    var canTranslate: Bool
    var canSummarize: Bool
    var canAskBerean: Bool
    var canSaveToChurchNotes: Bool
    var canReflectInSelah: Bool
    var canReportSafety: Bool
    var canReplyOrComment: Bool
    var canShare: Bool
    var canComposeOrEdit: Bool
}

enum AmenImmersiveMediaAnalyticsEvent: String {
    case immersiveOpened = "immersive_media_opened"
    case immersiveClosed = "immersive_media_closed"
    case chromeCollapsed = "immersive_chrome_collapsed"
    case chromeExpanded = "immersive_chrome_expanded"
    case actionTapped = "immersive_action_tapped"
    case previousNextTapped = "immersive_previous_next_tapped"
    case actionHiddenUnavailable = "immersive_action_hidden_unavailable"
    case translateTapped = "immersive_translate_tapped"
    case saveTapped = "immersive_save_tapped"
    case shareTapped = "immersive_share_tapped"
    case bereanOpened = "immersive_berean_opened"
}

enum AmenImmersiveMediaAnalytics {
    static func track(_ event: AmenImmersiveMediaAnalyticsEvent, params: [String: Any] = [:]) {
        guard AMENFeatureFlags.shared.analyticsEnabled else { return }
        dlog("[ImmersiveAnalytics] \(event.rawValue)\(params.isEmpty ? "" : " \(params)")")
    }
}

enum AmenImmersiveMediaEligibility {
    static func smartPills(from input: AmenImmersiveEligibilityInput) -> [AmenImmersivePillType] {
        var pills: [AmenImmersivePillType] = []
        if input.canTranslate { pills.append(.translate) }
        if input.canSummarize { pills.append(.summarize) }
        if input.canAskBerean { pills.append(.askBerean) }
        if input.canSaveToChurchNotes { pills.append(.saveToChurchNotes) }
        if input.canReflectInSelah { pills.append(.reflectInSelah) }
        if input.canReportSafety { pills.append(.reportSafety) }
        return pills
    }

    static func hasDeadButtons(actions: [AmenImmersiveMediaChromeAction]) -> Bool {
        actions.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum AmenImmersiveSurfaceActionFactory {
    static func messageAttachmentActionIDs(
        eligibility: AmenImmersiveEligibilityInput,
        hasReplyHandler: Bool
    ) -> [String] {
        var ids: [String] = []
        if hasReplyHandler && eligibility.canReplyOrComment { ids.append("reply") }
        if eligibility.canShare { ids.append("share") }
        if eligibility.canSaveToChurchNotes { ids.append("add_to_church_notes") }
        if eligibility.canReflectInSelah { ids.append("add_to_selah") }
        if eligibility.canSummarize { ids.append("summarize") }
        if eligibility.canAskBerean { ids.append("ask_berean") }
        if eligibility.canReportSafety { ids.append("report") }
        return ids
    }

    static func feedActionIDs(eligibility: AmenImmersiveEligibilityInput) -> [String] {
        var ids: [String] = []
        if eligibility.canReplyOrComment { ids.append("comment") }
        if eligibility.canShare { ids.append("share") }
        if eligibility.canSaveToChurchNotes { ids.append("add_to_church_notes") }
        if eligibility.canAskBerean { ids.append("ask_berean") }
        if eligibility.canReportSafety { ids.append("report") }
        return ids
    }

    static func selahActionIDs(eligibility: AmenImmersiveEligibilityInput) -> [String] {
        var ids: [String] = []
        if eligibility.canReplyOrComment { ids.append("comment") }
        ids.append("save")
        if eligibility.canReflectInSelah { ids.append("reflect") }
        if eligibility.canAskBerean { ids.append("ask_berean") }
        if eligibility.canSaveToChurchNotes { ids.append("add_to_church_notes") }
        if eligibility.canReportSafety { ids.append("report") }
        if eligibility.canShare { ids.append("share") }
        return ids
    }

    static func previousNextVisible(itemCount: Int) -> Bool {
        itemCount > 1
    }
}

struct AmenImmersiveMediaChrome: View {
    let title: String
    let onBack: () -> Void
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    let topTrailingActions: [AmenImmersiveMediaChromeAction]
    let smartPills: [AmenImmersivePillType]
    let bottomActions: [AmenImmersiveMediaChromeAction]
    let isCollapsed: Bool
    var onBackgroundTap: (() -> Void)? = nil
    var reduceMotionOverride: Bool? = nil
    var reduceTransparencyOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    init(
        title: String,
        onBack: @escaping () -> Void,
        onPrevious: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil,
        topTrailingActions: [AmenImmersiveMediaChromeAction] = [],
        smartPills: [AmenImmersivePillType] = [],
        bottomActions: [AmenImmersiveMediaChromeAction],
        isCollapsed: Bool,
        onBackgroundTap: (() -> Void)? = nil,
        reduceMotionOverride: Bool? = nil,
        reduceTransparencyOverride: Bool? = nil
    ) {
        self.title = title
        self.onBack = onBack
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.topTrailingActions = topTrailingActions
        self.smartPills = smartPills
        self.bottomActions = bottomActions
        self.isCollapsed = isCollapsed
        self.onBackgroundTap = onBackgroundTap
        self.reduceMotionOverride = reduceMotionOverride
        self.reduceTransparencyOverride = reduceTransparencyOverride
    }

    private var effectiveReduceMotion: Bool { reduceMotionOverride ?? reduceMotion }
    private var effectiveReduceTransparency: Bool { reduceTransparencyOverride ?? reduceTransparency }

    private var chromeAnimation: Animation {
        effectiveReduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.34, dampingFraction: 0.86)
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onBackgroundTap?()
                }

            VStack {
                topChrome
                Spacer()
                bottomChrome
            }
        }
        .animation(chromeAnimation, value: isCollapsed)
        .onChange(of: isCollapsed) { _, collapsed in
            AmenImmersiveMediaAnalytics.track(collapsed ? .chromeCollapsed : .chromeExpanded)
        }
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            AmenGlassCircleButton(systemImage: "chevron.left", label: "Back", hint: "Return to previous screen") {
                AmenImmersiveMediaAnalytics.track(.actionTapped, params: ["action": "back"])
                onBack()
            }

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)

            if onPrevious != nil || onNext != nil {
                AmenGlassCapsule {
                    HStack(spacing: 8) {
                        if let onPrevious {
                            AmenGlassCircleButton(systemImage: "chevron.up", label: "Previous item", hint: "Move to previous item") {
                                AmenImmersiveMediaAnalytics.track(.actionTapped, params: ["action": "previous"])
                                AmenImmersiveMediaAnalytics.track(.previousNextTapped, params: ["direction": "previous"])
                                onPrevious()
                            }
                        }
                        if let onNext {
                            AmenGlassCircleButton(systemImage: "chevron.down", label: "Next item", hint: "Move to next item") {
                                AmenImmersiveMediaAnalytics.track(.actionTapped, params: ["action": "next"])
                                AmenImmersiveMediaAnalytics.track(.previousNextTapped, params: ["direction": "next"])
                                onNext()
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .frame(minWidth: 96)
            }

            ForEach(topTrailingActions.prefix(1)) { action in
                AmenGlassCircleButton(systemImage: action.systemImage, label: action.title, hint: action.accessibilityHint.isEmpty ? action.title : action.accessibilityHint) {
                    AmenImmersiveMediaAnalytics.track(.actionTapped, params: ["action": action.id])
                    action.action()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .opacity(isCollapsed ? 0 : 1)
        .offset(y: isCollapsed ? -16 : 0)
        .safeAreaPadding(.top)
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if !smartPills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(smartPills, id: \.rawValue) { pill in
                            AmenGlassCapsule {
                                Text(pill.label)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bottomActions) { action in
                        Button(role: action.role) {
                            AmenImmersiveMediaAnalytics.track(.actionTapped, params: ["action": action.id])
                            if action.id.contains("translate") { AmenImmersiveMediaAnalytics.track(.translateTapped) }
                            if action.id.contains("save") { AmenImmersiveMediaAnalytics.track(.saveTapped) }
                            if action.id.contains("share") { AmenImmersiveMediaAnalytics.track(.shareTapped) }
                            if action.id.contains("berean") { AmenImmersiveMediaAnalytics.track(.bereanOpened) }
                            action.action()
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .background(
                            Capsule(style: .continuous)
                                .fill(effectiveReduceTransparency ? Color(.systemBackground) : Color.white.opacity(0.58))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(accessibilityContrast == .increased ? Color.black.opacity(0.35) : Color.black.opacity(0.12), lineWidth: 0.7)
                        )
                        .accessibilityLabel(action.title)
                        .accessibilityHint(action.accessibilityHint.isEmpty ? "Action" : action.accessibilityHint)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(AmenAdaptiveMaterialBackground(cornerRadius: 24, reduceTransparency: effectiveReduceTransparency))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
        .opacity(isCollapsed ? 0 : 1)
        .scaleEffect(isCollapsed ? 0.96 : 1)
        .offset(y: isCollapsed ? 20 : 0)
        .safeAreaPadding(.bottom)
    }
}

private extension AmenImmersivePillType {
    var label: String {
        switch self {
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        case .askBerean: return "Ask Berean"
        case .saveToChurchNotes: return "Save to Notes"
        case .reflectInSelah: return "Reflect"
        case .reportSafety: return "Safety"
        }
    }
}

private struct AmenAdaptiveMaterialBackground: View {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(reduceTransparency ? Color(.secondarySystemBackground) : Color.clear)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.regularMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
    }
}

private struct AmenGlassCapsule<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(AmenAdaptiveMaterialBackground(cornerRadius: 18, reduceTransparency: reduceTransparency))
            .clipShape(Capsule(style: .continuous))
    }
}

private struct AmenGlassCircleButton: View {
    let systemImage: String
    let label: String
    let hint: String
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(AmenAdaptiveMaterialBackground(cornerRadius: 22, reduceTransparency: reduceTransparency))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

#Preview("Expanded") {
    ZStack {
        Color.black
        AmenImmersiveMediaChrome(
            title: "Message Attachment",
            onBack: {},
            onPrevious: {},
            onNext: {},
            topTrailingActions: [.init(title: "More", systemImage: "ellipsis", action: {})],
            smartPills: [.translate, .askBerean, .saveToChurchNotes],
            bottomActions: [
                .init(id: "save", title: "Save", systemImage: "bookmark", action: {}),
                .init(id: "notes", title: "Add to Church Notes", systemImage: "note.text", action: {}),
                .init(id: "selah", title: "Add to Selah", systemImage: "brain.head.profile", action: {}),
                .init(id: "reply", title: "Reply", systemImage: "arrowshape.turn.up.left", action: {}),
                .init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {})
            ],
            isCollapsed: false
        )
    }
}

#Preview("Collapsed Reduce Transparency") {
    ZStack {
        Color.white
        AmenImmersiveMediaChrome(
            title: "Church Notes",
            onBack: {},
            bottomActions: [.init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {})],
            isCollapsed: true,
            reduceTransparencyOverride: true
        )
    }
}

#Preview("Bright Photo Single Item") {
    ZStack {
        Color.white
        AmenImmersiveMediaChrome(
            title: "Photo",
            onBack: {},
            bottomActions: [
                .init(id: "save", title: "Save", systemImage: "bookmark", action: {}),
                .init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {})
            ],
            isCollapsed: false
        )
    }
}

#Preview("Dark Video Multi Item") {
    ZStack {
        Color.black
        AmenImmersiveMediaChrome(
            title: "Video 2 of 4",
            onBack: {},
            onPrevious: {},
            onNext: {},
            smartPills: [.summarize, .askBerean],
            bottomActions: [
                .init(id: "reply", title: "Reply", systemImage: "arrowshape.turn.up.left", action: {}),
                .init(id: "save", title: "Save", systemImage: "bookmark", action: {}),
                .init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {})
            ],
            isCollapsed: false
        )
    }
}

#Preview("Message Attachment") {
    ZStack {
        Color.gray.opacity(0.3)
        AmenImmersiveMediaChrome(
            title: "Message Attachment",
            onBack: {},
            smartPills: [.summarize],
            bottomActions: [
                .init(id: "reply", title: "Reply", systemImage: "arrowshape.turn.up.left", action: {}),
                .init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {})
            ],
            isCollapsed: false
        )
    }
}

#Preview("Feed Post") {
    ZStack {
        Color(white: 0.95)
        AmenImmersiveMediaChrome(
            title: "Today: AMEN",
            onBack: {},
            smartPills: [.translate, .askBerean],
            bottomActions: [
                .init(id: "comment", title: "Comment", systemImage: "text.bubble", action: {}),
                .init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {}),
                .init(id: "report", title: "Report", systemImage: "flag", role: .destructive, action: {})
            ],
            isCollapsed: false
        )
    }
}

#Preview("Selah Memory") {
    ZStack {
        Color(white: 0.9)
        AmenImmersiveMediaChrome(
            title: "Selah Memory",
            onBack: {},
            smartPills: [.reflectInSelah],
            bottomActions: [
                .init(id: "reflect", title: "Reflect", systemImage: "brain.head.profile", action: {}),
                .init(id: "add_to_church_notes", title: "Add to Church Notes", systemImage: "note.text", action: {}),
                .init(id: "report", title: "Report", systemImage: "flag", role: .destructive, action: {})
            ],
            isCollapsed: false
        )
    }
}

#Preview("Reduce Motion") {
    ZStack {
        Color.black
        AmenImmersiveMediaChrome(
            title: "Reduced Motion",
            onBack: {},
            onPrevious: {},
            onNext: {},
            bottomActions: [.init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {})],
            isCollapsed: true,
            reduceMotionOverride: true
        )
    }
}

#Preview("Large Dynamic Type") {
    ZStack {
        Color(white: 0.1)
        AmenImmersiveMediaChrome(
            title: "Large Type",
            onBack: {},
            bottomActions: [
                .init(id: "save", title: "Save", systemImage: "bookmark", action: {}),
                .init(id: "share", title: "Share", systemImage: "square.and.arrow.up", action: {})
            ],
            isCollapsed: false
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
