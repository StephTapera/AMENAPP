// LongPressIntelligenceMenu.swift
// AMENAPP — Long-Press Intelligence Layer (Wave 1)
//
// ONE reusable glass contextual menu for the entire app.
// No per-screen reimplementation. AI streaming is Wave 2.

import SwiftUI

struct LongPressIntelligenceMenu: View {

    let context: BereanObjectContext
    let onAction: (IntelligenceAction) -> Void
    let onDismiss: () -> Void

    @AppStorage("lp_hint_shown") private var hintShown: Bool = false
    @State private var appeared: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var actions: [IntelligenceAction] {
        LongPressActionRegistry.shared.actions(for: context.objectType)
    }

    private var quickActions: [IntelligenceAction] {
        actions.filter { $0.category == .quick }
    }

    private var smartActions: [IntelligenceAction] {
        actions.filter { $0.category == .smart }
    }

    private var safetyActions: [IntelligenceAction] {
        actions.filter { $0.category == .safety }
    }

    var body: some View {
        guard AMENFeatureFlags.shared.longPressIntelligenceEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(menuContent)
    }

    @ViewBuilder
    private var menuContent: some View {
        ZStack(alignment: .bottom) {
            scrim
            card
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .scaleEffect(appeared ? 1 : 0.7, anchor: .bottom)
                .opacity(appeared ? 1 : 0)
                .animation(
                    reduceMotion
                        ? .easeInOut(duration: 0.2)
                        : .spring(response: 0.35, dampingFraction: 0.7),
                    value: appeared
                )
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global)
                .onEnded { value in
                    if value.translation.height > 40 {
                        onDismiss()
                    }
                }
        )
        .onAppear {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation { appeared = true }
        }
    }

    private var scrim: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .onTapGesture { onDismiss() }
            .accessibilityLabel("Dismiss menu")
            .accessibilityAddTraits(.isButton)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !hintShown {
                hintChip
                    .padding(.bottom, 12)
            }

            if !quickActions.isEmpty {
                quickRow
                    .padding(.bottom, 16)
            }

            if !smartActions.isEmpty {
                smartList
            }

            if !safetyActions.isEmpty {
                Divider()
                    .padding(.vertical, 8)
                safetyList
            }
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            Color(uiColor: .secondarySystemBackground)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var hintChip: some View {
        Text("Press and hold anything to ask Berean")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .onAppear { hintShown = true }
    }

    private var quickRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickActions) { action in
                    quickPill(action)
                }
            }
        }
    }

    private func quickPill(_ action: IntelligenceAction) -> some View {
        Button {
            onAction(action)
            onDismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbolName(for: action))
                    .font(.caption.weight(.medium))
                Text(action.label)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var smartList: some View {
        VStack(spacing: 0) {
            ForEach(smartActions) { action in
                smartRow(action)
            }
        }
    }

    private func smartRow(_ action: IntelligenceAction) -> some View {
        Button {
            onAction(action)
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbolName(for: action))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                Text(action.label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
        }
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var safetyList: some View {
        VStack(spacing: 0) {
            ForEach(safetyActions) { action in
                safetyRow(action)
            }
        }
    }

    private func safetyRow(_ action: IntelligenceAction) -> some View {
        Button {
            onAction(action)
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbolName(for: action))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                Text(action.label)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Symbol Map

    private func symbolName(for action: IntelligenceAction) -> String {
        switch action.id {
        case "verse_explain_simply":    return "text.bubble"
        case "verse_original_language": return "character.book.closed"
        case "verse_cross_references":  return "link"
        case "verse_apply":             return "heart.text.square"
        case "verse_save":              return "bookmark"
        case "verse_highlight":         return "highlighter"
        case "comment_ask_berean":      return "sparkles"
        case "comment_find_verses":     return "book.closed"
        case "comment_find_opposing":   return "arrow.left.arrow.right"
        case "comment_reply":           return "arrowshape.turn.up.left"
        case "comment_save":            return "bookmark"
        case "comment_report":          return "flag"
        default:
            switch action.category {
            case .quick:        return "bolt"
            case .smart:        return "sparkles"
            case .relationship: return "person.badge.plus"
            case .safety:       return "flag"
            }
        }
    }
}
