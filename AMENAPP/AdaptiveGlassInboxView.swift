//
//  AdaptiveGlassInboxView.swift
//  AMENAPP — Liquid Glass Adaptive Inbox
//
//  A reusable, physics-driven Liquid Glass list surface that renders
//  messages, notifications, posts, prayers, church notes, Spaces,
//  communities, search, and events via data/config only.
//
//  Components
//  ──────────
//  MessageTab                  top-level tab (moved out of MessagesView)
//  InboxHeroState              5-state hero enum
//  InboxAdaptiveGlassHeader    scroll-aware adaptive header
//  InboxHeroPanel              expanded / compact hero with AI summary
//  InboxGlassFilterBar         magnetic glass filter chip row
//  InboxSwipeRow               physics swipe trays with haptic snap points
//  InboxPeekPreviewOverlay     peek preview on long-press
//  InboxAITriageInsights       floating glass triage insight cards
//  InboxFloatingSearchPill     bottom glass pill → full search canvas
//  InboxGlassPullHint          pull-to-refresh indicator
//  AdaptiveGlassInboxView      main container (wired to real services)
//

import SwiftUI
import FirebaseAuth

// MARK: - Message Tab (top-level so both MessagesView and AdaptiveGlassInboxView can see it)

enum MessageTab: Hashable {
    case messages
    case requests
    case archived
}

// MARK: - Hero State

enum InboxHeroState: Equatable {
    case expanded   // title + AI summary + filters + time context
    case compact    // title only, hero compressed, summary faded
    case floating   // detached glass panel integrated into the page
    case context    // surfaces a relevant card (event, prayer, Space)
    case search     // morphed into the search canvas
}

// MARK: - Scroll offset preference key

private struct GlassInboxScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - InboxSwipeRow
//
// Physics-based swipe row.  Drag left to reveal Archive (short) / execute (full).
// Drag right to reveal Read/Unread (short) / Pin (medium).
// Rubber-band resistance beyond snap limits.  Haptic at each threshold.

struct InboxSwipeRow<Content: View>: View {

    @ViewBuilder var content: () -> Content

    // Callbacks — nil = tray slot absent
    var onMoreOptions:    (() -> Void)?
    var onArchive:        (() -> Void)?
    var onExecuteArchive: (() -> Void)?
    var onToggleRead:     (() -> Void)?
    var onTogglePin:      (() -> Void)?
    var isUnread:  Bool = false
    var isPinned:  Bool = false

    // Accessibility labels
    var archiveLabel:  String = "Archive"
    var readLabel:     String = "Mark Read"
    var pinLabel:      String = "Pin"

    @State private var dragOffset:      CGFloat = 0
    @State private var committedOffset: CGFloat = 0
    @State private var isDragging:      Bool    = false
    @State private var lastThreshold:   CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shortThr:  CGFloat = 76
    private let mediumThr: CGFloat = 160
    private let fullThr:   CGFloat = 280

    private var total: CGFloat { dragOffset + committedOffset }

    var body: some View {
        ZStack {
            // Left tray — revealed when dragging right (positive offset)
            leadingTray
                .frame(maxWidth: .infinity, alignment: .leading)

            // Right tray — revealed when dragging left (negative offset)
            trailingTray
                .frame(maxWidth: .infinity, alignment: .trailing)

            // Content row, offset by current drag
            content()
                .offset(x: total)
                .simultaneousGesture(swipeGesture)
        }
        .clipped()
    }

    // MARK: Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let h = value.translation.width
                let v = value.translation.height
                guard abs(h) > abs(v) else { return }
                isDragging = true
                let raw = h + committedOffset
                dragOffset = rubberBand(raw) - committedOffset
                fireHapticIfNeeded()
            }
            .onEnded { value in
                isDragging = false
                let velocity = value.predictedEndTranslation.width - value.translation.width
                let projected = total + velocity * 0.18
                let snap = nearestSnap(projected)

                if snap <= -fullThr { UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0); onExecuteArchive?() }
                if snap >=  fullThr { UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0) }

                withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.44, dampingFraction: 0.76)) {
                    // Full-swipe executes then dismisses
                    committedOffset = (abs(snap) >= fullThr) ? 0 : snap
                    dragOffset = 0
                }
                lastThreshold = 0
            }
    }

    private func rubberBand(_ value: CGFloat) -> CGFloat {
        let cap: CGFloat = fullThr + 60
        let sign: CGFloat = value < 0 ? -1 : 1
        let mag = Swift.abs(value)
        return mag <= cap ? value : sign * (cap + (mag - cap) * 0.22)
    }

    private func nearestSnap(_ offset: CGFloat) -> CGFloat {
        let mag  = Swift.abs(offset)
        let sign: CGFloat = offset < 0 ? -1 : 1
        if mag < shortThr  * 0.4 { return 0 }
        if mag < mediumThr * 0.5 { return sign * shortThr }
        if mag < fullThr   * 0.6 { return sign * mediumThr }
        return sign * fullThr
    }

    private func fireHapticIfNeeded() {
        let mag = Swift.abs(total)
        let thresholds: [CGFloat] = [shortThr, mediumThr, fullThr]
        for thr in thresholds where abs(mag - thr) < 10 && thr != lastThreshold {
            lastThreshold = thr
            if thr == fullThr {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
            } else if thr == mediumThr {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
            }
            break
        }
    }

    // MARK: Leading Tray (right swipe)

    @ViewBuilder
    private var leadingTray: some View {
        if total > 0 {
            let rev = min(total, fullThr)
            HStack(spacing: 0) {
                // Read/Unread — short
                trayButton(
                    show: rev > 14,
                    icon: isUnread ? "envelope.open.fill" : "envelope.badge.fill",
                    label: isUnread ? "Read" : "Unread",
                    color: .blue,
                    width: min(rev, shortThr)
                ) {
                    onToggleRead?()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { committedOffset = 0; dragOffset = 0 }
                }
                // Pin — medium
                trayButton(
                    show: rev > shortThr + 14,
                    icon: isPinned ? "pin.slash.fill" : "pin.fill",
                    label: pinLabel,
                    color: isPinned ? Color(.systemGray) : Color(.label),
                    width: min(rev - shortThr, mediumThr - shortThr)
                ) {
                    onTogglePin?()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { committedOffset = 0; dragOffset = 0 }
                }
                Spacer()
            }
        }
    }

    // MARK: Trailing Tray (left swipe)

    @ViewBuilder
    private var trailingTray: some View {
        if total < 0 {
            let rev = min(Swift.abs(total), fullThr)
            HStack(spacing: 0) {
                Spacer()
                // More — short
                trayButton(
                    show: rev > 14,
                    icon: "ellipsis",
                    label: "More",
                    color: Color(.systemGray3),
                    width: min(rev, shortThr)
                ) {
                    onMoreOptions?()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { committedOffset = 0; dragOffset = 0 }
                }
                // Archive — medium / full
                trayButton(
                    show: rev > shortThr + 14,
                    icon: rev > fullThr * 0.7 ? "archivebox.fill" : "archivebox",
                    label: rev > fullThr * 0.7 ? "Archive!" : archiveLabel,
                    color: rev > fullThr * 0.7 ? .orange : Color(.systemGray),
                    width: min(rev - shortThr, mediumThr - shortThr)
                ) {
                    onArchive?()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { committedOffset = 0; dragOffset = 0 }
                }
            }
        }
    }

    // MARK: Tray Button

    @ViewBuilder
    private func trayButton(show: Bool, icon: String, label: String, color: Color, width: CGFloat, action: @escaping () -> Void) -> some View {
        if show {
            let w = max(width, 0)
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                    if w > 50 {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: w)
                .frame(maxHeight: .infinity)
                .background(color)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.70), value: w)
        }
    }
}

// MARK: - InboxAdaptiveGlassHeader
//
// Pinned at the top.  Transparent when content is below the fold;
// progressively blurs and dims as content scrolls underneath.
// Safe-area + Dynamic Island aware (uses safeAreaInsets, not hardcoded values).

struct InboxAdaptiveGlassHeader: View {
    let title:        String
    let scrollOffset: CGFloat   // positive = content above top edge
    let heroState:    InboxHeroState
    let onCompose:    () -> Void
    let onSettings:   () -> Void
    let onRequests:   () -> Void
    let onBack:       () -> Void
    let requestCount: Int

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion

    // 0 → transparent  1 → fully frosted
    private var glassProgress: Double {
        let offset = -scrollOffset          // positive as user scrolls down
        return min(max(Double(offset) / 64.0, 0), 1)
    }

    var body: some View {
        ZStack {
            // Glass background layer
            headerBackground

            HStack(spacing: 4) {
                // Back
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(.label))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                // Compact title only when scrolled in
                if heroState == .compact {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color(.label))
                        .transition(reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top)))
                    Spacer()
                }

                // Overflow menu
                Menu {
                    if requestCount > 0 {
                        Button { onRequests() } label: {
                            Label("Message Requests (\(requestCount))", systemImage: "tray.and.arrow.down")
                        }
                    }
                    Button { onSettings() } label: { Label("Settings", systemImage: "gearshape") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More options")

                // Compose
                Button(action: onCompose) {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New message")
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 52)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.82),
            value: glassProgress
        )
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.82),
            value: heroState
        )
    }

    @ViewBuilder
    private var headerBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
                .opacity(glassProgress > 0.5 ? 1 : 0)
                .overlay(alignment: .bottom) {
                    if glassProgress > 0.5 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.4))
                            .frame(height: 0.5)
                    }
                }
        } else {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(glassProgress)
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.06 * glassProgress))
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.35 * glassProgress))
                        .frame(height: 0.5)
                }
        }
    }
}

// MARK: - InboxHeroPanel
//
// 5-state hero card that lives below the fixed header.
// Expanded: title + AI smart summary + time context.
// Compact:  empty (hero compresses away).

struct InboxHeroPanel: View {
    let greetingName: String
    let heroSummary:  String    // "14 unread · 3 replies needed · 1 urgent"
    let heroState:    InboxHeroState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch heroState {
            case .expanded:
                expandedHero
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            case .compact:
                EmptyView()
            case .floating, .context, .search:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.40, dampingFraction: 0.82),
            value: heroState
        )
    }

    private var expandedHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Editorial index + title
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("01")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .kerning(1)
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)

                Text("messages")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Color(.label))
                    .kerning(-1.5)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            // AI smart summary row
            if !heroSummary.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text(heroSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                }
                .accessibilityLabel("Summary: \(heroSummary)")
            }

            // Time context
            Text(timeContext)
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.bottom, 4)
        }
    }

    private var timeContext: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        let date = df.string(from: Date())
        switch hour {
        case 5..<12:  return "Good morning · \(date)"
        case 12..<17: return "Good afternoon · \(date)"
        case 17..<21: return "Good evening · \(date)"
        default:      return date
        }
    }
}

// MARK: - InboxGlassFilterBar
//
// Horizontal scrolling glass chip row backed by MessagingInboxFilter.
// Magnetic spring when selecting a chip.  Reduce Motion: instant transition.

struct InboxGlassFilterBar: View {
    let chips: [MessagingInboxFilter]
    @Binding var selected: MessagingInboxFilter

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { filter in
                    chip(filter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func chip(_ filter: MessagingInboxFilter) -> some View {
        let active = selected == filter
        Button {
            HapticManager.impact(style: .light)
            withAnimation(reduceMotion
                ? .easeInOut(duration: 0.12)
                : .spring(response: 0.28, dampingFraction: 0.76)) {
                selected = filter
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.symbol)
                    .font(.caption.weight(.semibold))
                Text(filter.title)
                    .font(.subheadline.weight(active ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? Color(.systemBackground) : Color(.label))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if active {
                    Capsule(style: .continuous)
                        .fill(Color(.label))
                        .matchedGeometryEffect(id: "activeChip", in: ns)
                } else if reduceTransparency {
                    Capsule(style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay { Capsule(style: .continuous).fill(Color.white.opacity(0.08)) }
                }
            }
            .overlay {
                if !active {
                    Capsule(style: .continuous)
                        .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.title)
        .accessibilityHint(filter.voiceOverHint)
        .accessibilityAddTraits(active ? .isSelected : [])
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: active)
    }
}

// MARK: - InboxAITriageInsights
//
// A horizontal scrolling row of floating glass cards showing AI triage data
// (urgent, unread, replies needed, deadlines).  Appears only when relevant.

struct InboxTriageInsight: Identifiable {
    let id   = UUID()
    let icon: String
    let count: Int
    let label: String
}

struct InboxAITriageInsights: View {
    let insights: [InboxTriageInsight]

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @State private var appeared = false

    var body: some View {
        if !insights.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(insights) { insight in
                        card(insight)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: (appeared || reduceMotion) ? 0 : 10)
            .onAppear {
                withAnimation(reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.48, dampingFraction: 0.76).delay(0.15)) {
                    appeared = true
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func card(_ insight: InboxTriageInsight) -> some View {
        HStack(spacing: 8) {
            Image(systemName: insight.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.label))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(insight.count)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(.label))
                Text(insight.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.97))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.42), lineWidth: 0.5)
                    }
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        .accessibilityLabel("\(insight.count) \(insight.label)")
    }
}

// MARK: - InboxFloatingSearchPill
//
// A glass capsule floating above the home indicator.
// Tap → morphs into a full-width search canvas with voice/semantic input.
// Keyboard dismiss → collapses back to pill.

struct InboxFloatingSearchPill: View {
    @Binding var isExpanded:  Bool
    @Binding var searchText:  String
    let onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @FocusState private var focused: Bool
    @Namespace private var pillNS

    var body: some View {
        Group {
            if isExpanded {
                expandedCanvas
            } else {
                collapsedPill
            }
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.44, dampingFraction: 0.78),
            value: isExpanded
        )
    }

    // Collapsed glass pill
    private var collapsedPill: some View {
        Button {
            HapticManager.impact(style: .light)
            withAnimation(reduceMotion
                ? .easeInOut(duration: 0.15)
                : .spring(response: 0.44, dampingFraction: 0.78)) {
                isExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(.label))
                Text("Search messages, people, notes…")
                    .font(.subheadline)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "mic.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.quaternaryLabel))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background { pillMaterial(Capsule(style: .continuous)) }
            .clipShape(Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 5)
        .padding(.horizontal, 22)
        .accessibilityLabel("Search")
        .accessibilityHint("Double tap to expand search canvas")
        .matchedGeometryEffect(id: "glassSearchShape", in: pillNS)
    }

    // Expanded canvas
    private var expandedCanvas: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(.label))

            TextField("Search conversations, people, notes, Scripture…", text: $searchText)
                .font(.body)
                .foregroundStyle(Color(.label))
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityLabel("Search field")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Button("Cancel") {
                searchText = ""
                focused = false
                withAnimation(reduceMotion
                    ? .easeInOut(duration: 0.15)
                    : .spring(response: 0.40, dampingFraction: 0.80)) {
                    isExpanded = false
                }
                onClose()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(.label))
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel search")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background { pillMaterial(RoundedRectangle(cornerRadius: 24, style: .continuous)) }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.38), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 5)
        .padding(.horizontal, 12)
        .matchedGeometryEffect(id: "glassSearchShape", in: pillNS)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func pillMaterial<S: Shape>(_ shape: S) -> some View {
        if reduceTransparency {
            shape.fill(Color(.systemBackground).opacity(0.97))
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay { shape.fill(Color.white.opacity(0.10)) }
        }
    }
}

// MARK: - InboxPeekPreviewOverlay
//
// Emerge from the selected row on long-press.
// Background soft-blurs, desaturates.  Peek card focuses with lighting.
// Supports: message / note / prayer.

struct InboxPeekPreviewOverlay: View {
    @Binding var conversation: ChatConversation?
    let onOpen:    (ChatConversation) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)       private var reduceMotion

    var body: some View {
        if let conv = conversation {
            ZStack {
                // Dimmed blurred backdrop
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)

                // Peek card
                peekCard(conv)
                    .transition(reduceMotion
                        ? .opacity
                        : .scale(scale: 0.90).combined(with: .opacity))
            }
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.38, dampingFraction: 0.82)) {
            onDismiss()
        }
    }

    private func peekCard(_ conv: ChatConversation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Conversation header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(conv.initials)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color(.label))
                    Text(conv.timestamp)
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                Spacer()
                if conv.unreadCount > 0 {
                    OdometerBadgeView(count: conv.unreadCount)
                }
            }

            Divider().opacity(0.35)

            // Message preview
            Text(conv.lastMessage.isEmpty ? "No messages yet" : conv.lastMessage)
                .font(.body)
                .foregroundStyle(Color(.label))
                .lineLimit(5)

            // Actions
            HStack(spacing: 12) {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onOpen(conv) }
                } label: {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule(style: .continuous).fill(Color(.label)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open conversation with \(conv.name)")

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Dismiss")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss preview")
            }
        }
        .padding(20)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.systemBackground))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.38), lineWidth: 0.5)
                    }
            }
        }
        .shadow(color: Color.black.opacity(0.20), radius: 28, x: 0, y: 8)
        .padding(.horizontal, 18)
    }
}

// MARK: - AdaptiveGlassInboxView
//
// Main container.  Wired to real FirebaseMessagingService data.
// Surface differences (messages vs posts vs events) are data/config only.

struct AdaptiveGlassInboxView: View {

    // MARK: Data
    let conversations:       [ChatConversation]
    let pinnedConversations: [ChatConversation]
    let aiSummaryService:    InboxAISummaryService
    let requestCount:        Int
    let firstName:           String

    // MARK: Parent-controlled state
    @Binding var searchText:   String
    @Binding var selectedTab:  MessageTab
    @Binding var isRefreshing: Bool

    // MARK: Callbacks (all wired to real MessagesView actions)
    let onOpenChat:    (ChatConversation) -> Void
    let onCompose:     () -> Void
    let onSettings:    () -> Void
    let onRequests:    () -> Void
    let onBack:        () -> Void
    let onArchive:     (ChatConversation) -> Void
    let onDelete:      (ChatConversation) -> Void
    let onPin:         (ChatConversation) -> Void
    let onUnpin:       (ChatConversation) -> Void
    let onMarkRead:    (ChatConversation) -> Void
    let onMarkUnread:  (ChatConversation) -> Void
    let onRefresh:     () async -> Void

    // MARK: Internal state
    @State private var scrollOffset:       CGFloat              = 0
    @State private var heroState:          InboxHeroState       = .expanded
    @State private var searchPillExpanded: Bool                 = false
    @State private var selectedFilter:     MessagingInboxFilter = .all
    @State private var peekConversation:   ChatConversation?
    @State private var rowsVisible:        Bool                 = false

    @Namespace private var tabNS

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let compactThreshold: CGFloat = 90

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            // ── Layer 1: Scrollable content ──────────────────────────────
            scrollContent

            // ── Layer 2: Fixed adaptive header ───────────────────────────
            VStack(spacing: 0) {
                Color.clear.frame(height: topSafeInset)
                InboxAdaptiveGlassHeader(
                    title:        "Messages",
                    scrollOffset: scrollOffset,
                    heroState:    heroState,
                    onCompose:    onCompose,
                    onSettings:   onSettings,
                    onRequests:   onRequests,
                    onBack:       onBack,
                    requestCount: requestCount
                )
            }
            .ignoresSafeArea(edges: .top)

            // ── Layer 3: Floating search pill ────────────────────────────
            VStack {
                Spacer()
                InboxFloatingSearchPill(
                    isExpanded: $searchPillExpanded,
                    searchText: $searchText,
                    onClose:    { searchText = "" }
                )
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .bottom)

            // ── Layer 4: Peek preview overlay ────────────────────────────
            if peekConversation != nil {
                InboxPeekPreviewOverlay(
                    conversation: $peekConversation,
                    onOpen: { conv in
                        peekConversation = nil
                        onOpenChat(conv)
                    },
                    onDismiss: { peekConversation = nil }
                )
                .zIndex(10)
                .transition(.opacity)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.40, dampingFraction: 0.80),
                    value: peekConversation != nil
                )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation { rowsVisible = true }
            }
        }
    }

    // MARK: Scroll Content

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Scroll offset sensor
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GlassInboxScrollKey.self,
                        value: geo.frame(in: .named("glassInbox")).minY
                    )
                }
                .frame(height: 0)

                // Space under fixed header
                Color.clear.frame(height: topSafeInset + 52 + 16)

                // Hero panel
                InboxHeroPanel(
                    greetingName: firstName,
                    heroSummary:  heroSummaryText,
                    heroState:    heroState
                )
                .padding(.bottom, heroState == .compact ? 0 : 8)

                // AI triage insight cards
                InboxAITriageInsights(insights: triageInsights)
                    .padding(.bottom, triageInsights.isEmpty ? 0 : 4)

                // Glass filter chips
                if !filterChips.isEmpty {
                    InboxGlassFilterBar(chips: filterChips, selected: $selectedFilter)
                        .padding(.bottom, 4)
                }

                // Tab selector — All / Requests / Archived
                tabSelector
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                // Quick contacts strip (messages tab, no search)
                if selectedTab == .messages && searchText.isEmpty {
                    let accepted = conversations.filter { $0.status == "accepted" }
                    if !accepted.isEmpty {
                        QuickAccessRow(conversations: accepted) { conv in onOpenChat(conv) }
                            .padding(.bottom, 8)
                    }
                }

                // Pinned section
                if !pinnedConversations.isEmpty && selectedTab == .messages && searchText.isEmpty {
                    InboxSectionLabel(text: "Pinned")
                    ForEach(pinnedConversations) { conv in
                        inboxRow(conv, isPinned: true)
                        InboxSeparator()
                    }
                    InboxSectionLabel(text: "All Messages")
                }

                // Main list
                conversationList

                // Bottom padding for search pill + home indicator
                Color.clear.frame(height: 130)
            }
        }
        .coordinateSpace(name: "glassInbox")
        .onPreferenceChange(GlassInboxScrollKey.self) { val in
            guard abs(val - scrollOffset) >= 1 else { return }
            scrollOffset = val
            updateHero(offset: val)
        }
        .refreshable { await onRefresh() }
        .modifier(AdaptiveScrollEdgeModifier())
    }

    // MARK: Conversation List

    @ViewBuilder
    private var conversationList: some View {
        let filtered = filterApplied(conversations)
        if filtered.isEmpty {
            InboxEmptyState(mode: searchText.isEmpty ? .noMessages : .noResults(searchText))
                .padding(.top, 60)
        } else {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, conv in
                inboxRow(conv, isPinned: false)
                    .onAppear { aiSummaryService.requestSummary(for: conv) }
                    .opacity(rowsVisible ? 1 : 0)
                    .offset(x: (rowsVisible || reduceMotion) ? 0 : 22)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.10)
                            : .spring(response: 0.46, dampingFraction: 0.78)
                                .delay(Double(min(idx, 12)) * 0.04),
                        value: rowsVisible
                    )
                InboxSeparator()
            }
        }
    }

    // MARK: Inbox Row

    @ViewBuilder
    private func inboxRow(_ conv: ChatConversation, isPinned: Bool) -> some View {
        InboxSwipeRow(
            content: {
                AMENThreadRow(
                    conversation: conv,
                    aiSummary: aiSummaryService.summary(for: conv),
                    onTap: { onOpenChat(conv) }
                )
                .contextMenu { rowContextMenu(conv, isPinned: isPinned) }
                .onLongPressGesture(minimumDuration: 0.45) {
                    HapticManager.impact(style: .medium)
                    withAnimation(reduceMotion
                        ? .easeOut(duration: 0.15)
                        : .spring(response: 0.42, dampingFraction: 0.78)) {
                        peekConversation = conv
                    }
                }
            },
            onMoreOptions:    nil,   // context menu serves this role
            onArchive:        { onArchive(conv) },
            onExecuteArchive: { onArchive(conv) },
            onToggleRead:     { conv.unreadCount > 0 ? onMarkRead(conv) : onMarkUnread(conv) },
            onTogglePin:      { isPinned ? onUnpin(conv) : onPin(conv) },
            isUnread:  conv.unreadCount > 0,
            isPinned:  isPinned,
            archiveLabel: "Archive",
            readLabel:    conv.unreadCount > 0 ? "Mark Read" : "Mark Unread",
            pinLabel:     isPinned ? "Unpin" : "Pin"
        )
    }

    // MARK: Context Menu

    @ViewBuilder
    private func rowContextMenu(_ conv: ChatConversation, isPinned: Bool) -> some View {
        Button { onOpenChat(conv) } label: { Label("Open", systemImage: "arrow.up.right") }

        if conv.unreadCount > 0 {
            Button { onMarkRead(conv) } label: { Label("Mark as Read", systemImage: "envelope.open.fill") }
        } else {
            Button { onMarkUnread(conv) } label: { Label("Mark as Unread", systemImage: "envelope.badge.fill") }
        }

        if isPinned {
            Button { onUnpin(conv) } label: { Label("Unpin", systemImage: "pin.slash.fill") }
        } else {
            Button { onPin(conv) } label: { Label("Pin", systemImage: "pin.fill") }
        }

        Button { onArchive(conv) } label: { Label("Archive", systemImage: "archivebox.fill") }

        Divider()

        Button(role: .destructive) { onDelete(conv) } label: { Label("Delete", systemImage: "trash.fill") }
    }

    // MARK: Tab Selector

    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tabPill(.messages,  "All",      nil)
                tabPill(.requests,  "Requests", requestCount > 0 ? requestCount : nil)
                tabPill(.archived,  "Archived", nil)
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func tabPill(_ tab: MessageTab, _ label: String, _ badge: Int?) -> some View {
        let active = selectedTab == tab
        Button {
            HapticManager.impact(style: .light)
            withAnimation(reduceMotion
                ? .easeInOut(duration: 0.12)
                : .spring(response: 0.26, dampingFraction: 0.76)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.subheadline.weight(active ? .semibold : .medium))
                    .foregroundStyle(active ? Color(.systemBackground) : Color(.secondaryLabel))
                if let n = badge, n > 0 {
                    Text("\(min(n, 99))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(active ? Color(.systemBackground) : .white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(active ? Color(.systemBackground).opacity(0.22) : Color.red))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background {
                if active {
                    Capsule(style: .continuous)
                        .fill(Color(.label))
                        .matchedGeometryEffect(id: "activeTab", in: tabNS)
                } else if reduceTransparency {
                    Capsule(style: .continuous).fill(Color(.systemGray6))
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay { Capsule(style: .continuous).fill(Color.white.opacity(0.07)) }
                }
            }
            .overlay {
                if !active {
                    Capsule(style: .continuous)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: active)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityLabel(badge.map { "\(label), \($0) pending" } ?? label)
    }

    // MARK: Hero state management

    private func updateHero(offset: CGFloat) {
        let depth = -offset              // positive as user scrolls down
        let newState: InboxHeroState = depth > compactThreshold ? .compact : .expanded
        guard newState != heroState else { return }
        withAnimation(reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.36, dampingFraction: 0.82)) {
            heroState = newState
        }
    }

    // MARK: Filter application

    private func filterApplied(_ list: [ChatConversation]) -> [ChatConversation] {
        guard selectedFilter != .all else { return list }
        return selectedFilter.apply(to: list) { _ in MessagingConversationMetadata.empty }
    }

    // MARK: Derived data

    private var heroSummaryText: String {
        let unread = conversations.reduce(0) { $0 + $1.unreadCount }
        guard unread > 0 else { return "" }
        return "\(unread) unread"
    }

    private var triageInsights: [InboxTriageInsight] {
        var out: [InboxTriageInsight] = []
        let unread = conversations.reduce(0) { $0 + $1.unreadCount }
        if unread > 0 { out.append(.init(icon: "envelope.badge.fill",    count: unread,                                        label: "unread")) }
        let prayers  = conversations.filter { $0.lastMessage.localizedCaseInsensitiveContains("pray") }.count
        if prayers > 0 { out.append(.init(icon: "hands.sparkles.fill",   count: prayers,                                       label: "prayer")) }
        if requestCount > 0 { out.append(.init(icon: "tray.and.arrow.down.fill", count: requestCount,                          label: "requests")) }
        return out
    }

    private var filterChips: [MessagingInboxFilter] {
        let caps = MessagingInboxFilterCapabilities(
            hasUnread: conversations.contains { $0.unreadCount > 0 },
            hasGroups: conversations.contains { $0.isGroup },
            hasMuted:  conversations.contains { $0.isMuted }
        )
        return MessagingInboxFilter.chips(for: caps, max: 5)
    }

    // MARK: Safe area

    private var topSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 47
    }
}
