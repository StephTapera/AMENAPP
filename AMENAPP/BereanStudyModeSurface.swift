//
//  BereanStudyModeSurface.swift
//  AMENAPP
//
//  Visual reasoning surface for Berean Study Mode.
//  Shows evidence categories (scripture, commentary, context, etc.)
//  with animated state transitions during assistant reasoning.
//
//  Non-negotiables:
//   - Never exposes raw internal chain-of-thought or private reasoning tokens
//   - Fully accessibility-labelled
//   - Respects Reduce Motion preference
//   - Collapses gracefully into a ribbon on scroll
//

import SwiftUI

struct BereanStudyModeSurface: View {
    let state: BereanStudyModeState
    let nodes: [BereanReasoningNode]
    let onCategoryTap: (BereanReasoningNode) -> Void
    let isCollapsed: Bool
    let reduceMotion: Bool
    var columnCount: Int = 2

    @State private var pulsePhase: CGFloat = 0
    @State private var activePulseIndex: Int = 0
    @State private var pulseTimer: Timer? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isCollapsed {
                collapsedRibbon
                    .transition(.opacity)
            } else {
                grid
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(16)
        .background(surfaceBackground)
        .animation(
            BereanAnimationCoordinator.adaptiveStudySpring(reduceMotion: reduceMotion),
            value: isCollapsed
        )
        .onAppear { startPulse() }
        .onDisappear { stopPulse() }
        .onChange(of: state) { _, newState in
            if newState == .resolved { stopPulse() }
            else if newState == .reasoning { startPulse() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Study Mode — \(stateTitle)")
    }

    // MARK: - Surface Background

    private var surfaceBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.80))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.7))
            Text(stateTitle)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.8))
            Spacer()
            if state == .reasoning {
                // Subtle spinner during reasoning
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
                    .transition(.opacity)
            }
            Text(stateSubtitle)
                .font(.systemScaled(12, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.5))
                .animation(BereanAnimationCoordinator.fade, value: stateSubtitle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stateTitle). \(stateSubtitle)")
    }

    // MARK: - Collapsed Ribbon

    private var collapsedRibbon: some View {
        HStack(spacing: 8) {
            let activeNodes = nodes.filter { $0.state == .active || $0.state == .scanning }
            let displayNodes = activeNodes.isEmpty ? Array(nodes.prefix(3)) : Array(activeNodes.prefix(3))
            ForEach(displayNodes) { node in
                categoryPill(node)
            }
            Spacer()
        }
        .accessibilityHidden(true)  // Ribbon is decorative; full grid is accessible
    }

    // MARK: - Full Grid

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: columnCount),
            spacing: 10
        ) {
            ForEach(nodes) { node in
                categoryCard(node)
            }
        }
    }

    // MARK: - Category Card

    private func categoryCard(_ node: BereanReasoningNode) -> some View {
        Button {
            onCategoryTap(node)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: node.category.icon)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(color(for: node.state))
                    .animation(BereanAnimationCoordinator.microFade, value: node.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.category.title)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                    Text(label(for: node.state))
                        .font(.systemScaled(11, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .animation(BereanAnimationCoordinator.microFade, value: node.state)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(cardBackground(for: node.state))
            .overlay(alignment: .topTrailing) {
                if (node.state == .active || node.state == .scanning) && !reduceMotion {
                    Circle()
                        .fill(color(for: node.state).opacity(0.5))
                        .frame(width: 7, height: 7)
                        .scaleEffect(1 + (pulsePhase * 0.5))
                        .opacity(0.5 + pulsePhase * 0.4)
                        .padding(7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(node.category.title): \(accessibilityLabel(for: node.state))")
        .accessibilityHint("Tap for details")
    }

    private func cardBackground(for state: BereanReasoningCategoryState) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(backgroundFill(for: state))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor(for: state), lineWidth: 0.5)
            )
    }

    private func backgroundFill(for state: BereanReasoningCategoryState) -> Color {
        switch state {
        case .idle: return Color.white.opacity(0.65)
        case .scanning: return Color.blue.opacity(0.04)
        case .active: return Color.green.opacity(0.06)
        case .complete: return Color.white.opacity(0.75)
        }
    }

    private func borderColor(for state: BereanReasoningCategoryState) -> Color {
        switch state {
        case .idle: return Color.white.opacity(0.5)
        case .scanning: return Color.blue.opacity(0.18)
        case .active: return Color.green.opacity(0.22)
        case .complete: return Color.white.opacity(0.5)
        }
    }

    // MARK: - Category Pill (collapsed)

    private func categoryPill(_ node: BereanReasoningNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: node.category.icon)
                .font(.systemScaled(10, weight: .semibold))
            Text(node.category.title)
                .font(.systemScaled(11, weight: .semibold))
        }
        .foregroundStyle(Color.black.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.75))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    // MARK: - State Strings

    private var stateTitle: String {
        switch state {
        case .idle: return "Study Mode"
        case .reasoning: return "Thinking"
        case .resolved: return "Sources Mapped"
        case .collapsedSummary: return "Study Mode"
        case .off: return "Study Mode"
        }
    }

    private var stateSubtitle: String {
        switch state {
        case .reasoning: return "Scanning sources"
        case .resolved: return "Complete"
        case .collapsedSummary: return "Summary"
        default: return ""
        }
    }

    private func label(for state: BereanReasoningCategoryState) -> String {
        switch state {
        case .idle: return "Standing by"
        case .scanning: return "Scanning…"
        case .active: return "Active"
        case .complete: return "Ready"
        }
    }

    private func accessibilityLabel(for state: BereanReasoningCategoryState) -> String {
        switch state {
        case .idle: return "standing by"
        case .scanning: return "scanning sources"
        case .active: return "actively processing"
        case .complete: return "complete"
        }
    }

    private func color(for state: BereanReasoningCategoryState) -> Color {
        switch state {
        case .idle: return Color.black.opacity(0.35)
        case .scanning: return Color.blue.opacity(0.75)
        case .active: return Color(red: 0.20, green: 0.65, blue: 0.45)
        case .complete: return Color.black.opacity(0.65)
        }
    }

    // MARK: - Pulse Timer

    private func startPulse() {
        guard !reduceMotion else { return }
        if let animation = BereanAnimationCoordinator.pulseAnimation(reduceMotion: reduceMotion) {
            withAnimation(animation) { pulsePhase = 1 }
        }
    }

    private func stopPulse() {
        withAnimation(BereanAnimationCoordinator.fade) { pulsePhase = 0 }
    }
}
