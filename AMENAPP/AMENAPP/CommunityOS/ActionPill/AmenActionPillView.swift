// AmenActionPillView.swift
// AMEN App — CommunityOS / ActionPill
//
// Phase 2 — Agent A18 (Universal Action Pill)
// The expandable object-aware action pill — "Mail toolbar pattern" from C3 §8.
//
// Design rules enforced:
//   • Collapsed: white Capsule + AmenShadow.floating (3–4 top-ranked icons + overflow)
//   • Expanded: horizontal scroll of icon+label pairs, spring animation
//   • Over-photo: .ultraThinMaterial + forced .dark scheme (AmenMaterial.darkOverlayPill)
//   • System semantic colors only — no custom hex, no amenGold, no accentPurple
//   • All animations gated behind @Environment(\.accessibilityReduceMotion)
//   • All glass swapped to solid when @Environment(\.accessibilityReduceTransparency) == true
//   • Minimum 44x44pt touch targets
//   • Anti-engagement: no view/like/reaction counts shown at any state
//
// Cross-reference:
//   AmenActionPillModel.swift   — object-type to action mapping
//   AmenUniversalComposer.swift — composer presented for intent-based actions
//   AmenDesignSystem.swift      — AmenShadow, AmenSurface, AmenMaterial tokens
//   C3-design-tokens.md §8      — canonical pill design spec

import SwiftUI

// MARK: - AmenActionPillView

/// The expandable floating action pill for any AMEN object.
///
/// Collapsed state: 3–4 top-ranked action icons + "···" overflow inside a white Capsule.
/// Expanded state:  all `availableActions` as icon+label pairs in a horizontal scroll.
/// Over-photo mode: dark translucent glass pill (forced `.dark` color scheme).
///
/// Caller is responsible for routing actions:
/// - Intent-based actions (discuss, pray, share…) → present `AmenUniversalComposer`
/// - `save` / `followUp` → toggle local state
/// - `more` is internal only; never emitted via `onAction`
///
/// Usage:
/// ```swift
/// AmenActionPillView(
///     model: AmenActionPillModel(objectType: .post, objectRef: "posts/abc", ...),
///     onPhotoBackground: false
/// ) { action in
///     handleAction(action)
/// }
/// ```
struct AmenActionPillView: View {

    // MARK: Inputs

    let model: AmenActionPillModel

    /// `true` → dark translucent pill (over hero photos).
    /// `false` → white Capsule pill (over page backgrounds).
    var onPhotoBackground: Bool = false

    /// Called when the user taps an action icon. `.more` is never emitted.
    var onAction: (PillAction) -> Void = { _ in }

    /// Maximum actions shown in collapsed state before overflow.
    var maxVisible: Int = 4

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: State

    @State private var isExpanded: Bool = false
    @State private var pressedId: String? = nil

    // MARK: Namespace (matched geometry for pill morph)

    @Namespace private var pillNamespace

    // MARK: Computed

    private var collapsedActions: [PillAction] {
        model.collapsedActions(maxVisible: maxVisible)
    }

    private var overflowActions: [PillAction] {
        model.overflowActions(maxVisible: maxVisible)
    }

    private var hasOverflow: Bool { !overflowActions.isEmpty }

    private var allActions: [PillAction] { model.availableActions }

    private var morphAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.32, dampingFraction: 0.82)
    }

    // MARK: Body

    var body: some View {
        Group {
            if isExpanded {
                expandedPill
                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal:   .scale(scale: 0.94).combined(with: .opacity)
                            )
                    )
            } else {
                collapsedPill
                    .matchedGeometryEffect(id: "pill", in: pillNamespace)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal:   .scale(scale: 0.96).combined(with: .opacity)
                            )
                    )
            }
        }
        .animation(morphAnimation, value: isExpanded)
    }

    // MARK: - Collapsed Pill

    private var collapsedPill: some View {
        HStack(spacing: 0) {
            ForEach(collapsedActions) { action in
                actionIconButton(action)
            }
            if hasOverflow {
                Divider()
                    .frame(width: 0.5, height: 24)
                    .background(Color(uiColor: .separator))
                    .padding(.horizontal, 2)
                overflowButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(pillBackground)
        .clipShape(Capsule(style: .continuous))
        .applyPillShadow(onPhoto: onPhotoBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(model.objectType.rawValue)")
    }

    // MARK: - Expanded Pill

    private var expandedPill: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(allActions) { action in
                    expandedActionButton(action)
                }
                closeButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(pillBackground)
        .clipShape(Capsule(style: .continuous))
        .applyPillShadow(onPhoto: onPhotoBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expanded actions for \(model.objectType.rawValue)")
    }

    // MARK: - Collapsed: single icon button

    private func actionIconButton(_ action: PillAction) -> some View {
        Button {
            triggerHaptic()
            withAnimation(morphAnimation) { pressedId = action.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(morphAnimation) { pressedId = nil }
                dispatch(action)
            }
        } label: {
            iconImage(action, weight: .regular)
                .frame(width: 44, height: 44)
                .scaleEffect(pressedId == action.id ? 0.88 : 1.0)
                .animation(morphAnimation, value: pressedId)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityHint(action.accessibilityHint)
    }

    // MARK: - Expanded: icon + label button

    private func expandedActionButton(_ action: PillAction) -> some View {
        Button {
            triggerHaptic()
            withAnimation(morphAnimation) {
                isExpanded = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                dispatch(action)
            }
        } label: {
            VStack(spacing: 4) {
                iconImage(action, weight: .regular)
                    .frame(width: 24, height: 24)
                Text(action.label)
                    .font(.caption2)
                    .foregroundStyle(pillForeground)
                    .lineLimit(1)
            }
            .frame(minWidth: 56, minHeight: 44)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityHint(action.accessibilityHint)
    }

    // MARK: - Overflow Button

    private var overflowButton: some View {
        Button {
            triggerHaptic()
            withAnimation(morphAnimation) {
                isExpanded = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(pillForeground)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
        .accessibilityHint("Shows \(overflowActions.count) additional actions")
    }

    // MARK: - Close Button (expanded state)

    private var closeButton: some View {
        Button {
            triggerHaptic()
            withAnimation(morphAnimation) {
                isExpanded = false
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pillForeground.opacity(0.6))
                .frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close expanded actions")
    }

    // MARK: - Icon Helper

    @ViewBuilder
    private func iconImage(_ action: PillAction, weight: Font.Weight) -> some View {
        Image(systemName: actionSystemImage(action))
            .font(.system(size: 17, weight: weight))
            .foregroundStyle(pillForeground)
    }

    /// Returns the SF Symbol, reflecting local toggle state for save/followUp.
    private func actionSystemImage(_ action: PillAction) -> String {
        switch action {
        case .save:
            return model.isSaved ? "bookmark.fill" : "bookmark"
        case .followUp:
            return model.isFollowedUp ? "arrow.uturn.right.circle.fill" : "arrow.uturn.right.circle"
        default:
            return action.systemImage
        }
    }

    // MARK: - Colors / Materials

    /// Primary foreground color for pill icons and labels.
    private var pillForeground: Color {
        onPhotoBackground
            ? .white
            : Color(uiColor: .label)
    }

    /// Pill background — white card or dark translucent glass per C3 §6.
    @ViewBuilder
    private var pillBackground: some View {
        if onPhotoBackground {
            // Dark overlay pill: AmenMaterial.darkOverlayPill
            // ultraThinMaterial + forced dark environment for white-on-image legibility
            if reduceTransparency {
                Color.black.opacity(0.72)
            } else {
                Color.black.opacity(0.40)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
        } else {
            // Standard white pill per C3 §8
            if reduceTransparency {
                Color(uiColor: .systemBackground)
            } else {
                Color.white
            }
        }
    }

    // MARK: - Action Dispatch

    /// Routes the tapped action.
    /// `more` is an internal expansion sentinel and is never forwarded.
    private func dispatch(_ action: PillAction) {
        guard action != .more else { return }
        onAction(action)
    }

    // MARK: - Haptics

    private func triggerHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }
}

// MARK: - Shadow ViewModifier Helper

private extension View {
    /// Applies the correct pill shadow token from AmenDesignSystem (C3 §5).
    @ViewBuilder
    func applyPillShadow(onPhoto: Bool) -> some View {
        if onPhoto {
            // Over photos: no shadow — the dark translucent background provides contrast
            self
        } else {
            self.shadow(
                color: AmenShadow.floating.color.opacity(AmenShadow.floating.opacity),
                radius: AmenShadow.floating.radius,
                x: AmenShadow.floating.x,
                y: AmenShadow.floating.y
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Collapsed — Post (light bg)") {
    VStack(spacing: 40) {
        AmenActionPillView(
            model: AmenActionPillModel(
                objectType: .post,
                objectRef: "posts/preview1",
                objectOwnerId: "uid_owner",
                currentUserId: "uid_viewer",
                isSaved: false,
                isFollowedUp: false
            ),
            onPhotoBackground: false
        ) { action in
            print("action: \(action.rawValue)")
        }

        AmenActionPillView(
            model: AmenActionPillModel(
                objectType: .event,
                objectRef: "events/preview2",
                objectOwnerId: "uid_owner",
                currentUserId: "uid_viewer",
                isSaved: true,
                isFollowedUp: false
            ),
            onPhotoBackground: false
        ) { action in
            print("action: \(action.rawValue)")
        }

        AmenActionPillView(
            model: AmenActionPillModel(
                objectType: .job,
                objectRef: "jobs/preview3",
                objectOwnerId: "uid_owner",
                currentUserId: "uid_viewer",
                isSaved: false,
                isFollowedUp: false
            ),
            onPhotoBackground: false
        ) { action in
            print("action: \(action.rawValue)")
        }
    }
    .padding(32)
    .background(Color(uiColor: .systemGroupedBackground))
}

#Preview("Dark overlay — over photo") {
    ZStack {
        LinearGradient(
            colors: [Color.blue.opacity(0.6), Color.indigo.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        AmenActionPillView(
            model: AmenActionPillModel(
                objectType: .bereanInsight,
                objectRef: "bereanInsights/preview4",
                objectOwnerId: "uid_owner",
                currentUserId: "uid_viewer",
                isSaved: false,
                isFollowedUp: false
            ),
            onPhotoBackground: true
        ) { action in
            print("action: \(action.rawValue)")
        }
    }
}
#endif
