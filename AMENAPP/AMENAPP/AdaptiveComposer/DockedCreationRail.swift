// DockedCreationRail.swift
// AMEN — Full-width keyboard-attached creation rail for Posts, Spaces, Church Notes, Bible Studies.
import SwiftUI

// MARK: - DockedCreationRail

/// Full-width keyboard-attached creation rail for Posts, Spaces, Church Notes, Bible Studies.
/// Presents in .compact, .expanded, or .predictive states.
/// Guard: only shown when featureFlags.composerAdaptiveRailEnabled == true (caller responsibility).
struct DockedCreationRail: View {
    @StateObject private var vm: CreationRailViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var railNamespace

    let surface: ComposerSurface
    let onToolSelected: (ToolID) -> Void
    let onAttachmentReady: (ComposerAttachment) -> Void
    @Binding var currentText: String

    init(surface: ComposerSurface,
         currentText: Binding<String>,
         churchContext: ChurchComposerContext? = nil,
         onToolSelected: @escaping (ToolID) -> Void,
         onAttachmentReady: @escaping (ComposerAttachment) -> Void) {
        self._vm = StateObject(wrappedValue: CreationRailViewModel.makeForSurface(surface, churchContext: churchContext))
        self.surface = surface
        self._currentText = currentText
        self.onToolSelected = onToolSelected
        self.onAttachmentReady = onAttachmentReady
    }

    var body: some View {
        VStack(spacing: 0) {
            // Predictive suggestions row
            if case .predictive(let suggestions) = vm.railState, !suggestions.isEmpty {
                PredictiveSuggestionsRow(suggestions: suggestions,
                                        onSelect: { id in
                                            onToolSelected(id)
                                            vm.setExpanded(false, reduceMotion: reduceMotion)
                                        },
                                        reduceMotion: reduceMotion)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .padding(.bottom, 4)
            }

            // Main rail
            railContent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(railBackground)
        .onChange(of: currentText) { _, text in
            vm.textDidChange(text, reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Creation tools")
        .accessibilityHint("Scroll to see more tools")
    }

    @ViewBuilder
    private var railContent: some View {
        switch vm.railState {
        case .compact:
            compactRail
        case .expanded:
            expandedRail
        case .predictive:
            compactRail  // compact underneath predictive row
        }
    }

    private var compactRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.orderedTools.prefix(4)) { tool in
                    RailToolButton(tool: tool, isCompact: true,
                                   onTap: { onToolSelected(tool.id) },
                                   reduceMotion: reduceMotion)
                }
                RailExpandButton(isExpanded: false) {
                    vm.setExpanded(true, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 44)
    }

    private var expandedRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.orderedTools) { tool in
                    RailToolButton(tool: tool, isCompact: false,
                                   onTap: { onToolSelected(tool.id) },
                                   reduceMotion: reduceMotion)
                }
                RailExpandButton(isExpanded: true) {
                    vm.setExpanded(false, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 60)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
    }

    @ViewBuilder
    private var railBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground).opacity(0.97))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.10))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - RailToolButton
private struct RailToolButton: View {
    let tool: CreationTool
    let isCompact: Bool
    let onTap: () -> Void
    let reduceMotion: Bool
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Image(systemName: tool.icon)
                    .font(.system(size: isCompact ? 18 : 16))
                    .frame(width: 28, height: 28)
                if !isCompact {
                    Text(tool.title)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .scaleEffect(isPressed && !reduceMotion ? 1.06 : 1.0)
        .animation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.28, dampingFraction: 0.86), value: isPressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in isPressed = true }
            .onEnded { _ in isPressed = false })
        .accessibilityLabel(tool.title)
        .accessibilityHint("Adds a \(tool.title) attachment")
        .accessibilityAddTraits(.isButton)
        .accessibilityShowsLargeContentViewer()
    }
}

// MARK: - RailExpandButton
private struct RailExpandButton: View {
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isExpanded ? "xmark" : "ellipsis")
                .font(.system(size: 16))
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(isExpanded ? "Collapse tools" : "More tools")
        .accessibilityHint(isExpanded ? "Collapses to compact rail" : "Shows all available creation tools")
        .accessibilityShowsLargeContentViewer()
    }
}

// MARK: - PredictiveSuggestionsRow
private struct PredictiveSuggestionsRow: View {
    let suggestions: [IntentSuggestion]
    let onSelect: (ToolID) -> Void
    let reduceMotion: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(suggestions.prefix(3).enumerated()), id: \.element.id) { index, suggestion in
                    PredictiveChip(suggestion: suggestion, delay: reduceMotion ? 0 : Double(index) * 0.04) {
                        onSelect(suggestion.primaryTool)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - PredictiveChip
private struct PredictiveChip: View {
    let suggestion: IntentSuggestion
    let delay: Double
    let onTap: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            Label(suggestion.label, systemImage: toolIcon(for: suggestion.primaryTool))
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
        .frame(minWidth: 44, minHeight: 44)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : (reduceMotion ? 0 : -12))
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0)
                          : .easeOut(duration: 0.18).delay(delay)) {
                appeared = true
            }
        }
        .accessibilityLabel(suggestion.label)
        .accessibilityHint("Tap to \(suggestion.label.lowercased())")
        .accessibilityShowsLargeContentViewer()
    }

    private func toolIcon(for id: ToolID) -> String {
        CreationTool.registry.first { $0.id == id }?.icon ?? "plus"
    }
}

// MARK: - View Extension for keyboard toolbar
extension View {
    /// Attaches the DockedCreationRail to the keyboard toolbar.
    func dockedCreationRail(
        surface: ComposerSurface,
        currentText: Binding<String>,
        isEnabled: Bool,
        churchContext: ChurchComposerContext? = nil,
        onToolSelected: @escaping (ToolID) -> Void,
        onAttachmentReady: @escaping (ComposerAttachment) -> Void
    ) -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isEnabled {
                    DockedCreationRail(
                        surface: surface,
                        currentText: currentText,
                        churchContext: churchContext,
                        onToolSelected: onToolSelected,
                        onAttachmentReady: onAttachmentReady
                    )
                }
            }
        }
    }
}
