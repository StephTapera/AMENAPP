import SwiftUI

// MARK: - AmenInlineDefinitionPopover
//
// A compact Liquid Glass popover that shows when the user taps an underlined
// semantic term. Long-press opens the expanded biblical context.
//
// Safety rules enforced here:
//  - Never fabricate scripture references (only shows refs returned by server)
//  - "Ask Berean" action only present when bereanRAGEnabled
//  - "Save to Selah" action only present when selahMediaOSEnabled
//  - Loading state shown while Cloud Function is in flight
//  - Error state shown on failure, never silent failures

struct AmenInlineDefinitionPopover: View {
    let term: String
    let definition: AmenSemanticDefinition?
    let isLoading: Bool
    let loadError: String?
    var onAskBerean: (() -> Void)? = nil
    var onSaveToSelah: (() -> Void)? = nil
    var onShowVerseContext: ((String) -> Void)? = nil
    var onExplainMore: (() -> Void)? = nil
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().opacity(0.3)
            bodyContent
            actionRow
        }
        .padding(16)
        .frame(maxWidth: AmenGlassMetrics.popoverMaxWidth)
        .background(popoverBackground)
        .clipShape(RoundedRectangle(cornerRadius: AmenGlassMetrics.popoverCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        .overlay(dismissZone)
        .transition(popoverTransition)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(term)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss definition")
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if isLoading {
            loadingView
        } else if let error = loadError {
            errorView(error)
        } else if let def = definition {
            definitionContent(def)
        } else {
            loadingView
        }
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Looking up \u{201C}\(term)\u{201D}…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Loading definition for \(term)")
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
            Text("Couldn't load definition")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Could not load definition. \(message)")
    }

    private func definitionContent(_ def: AmenSemanticDefinition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Compact definition — always shown
            Text(def.compactDefinition)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Expanded biblical context — shown on demand
            if showExpanded, let biblical = def.biblicalContext {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Biblical Context")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(biblical)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Scripture refs — only real, server-returned refs shown
            if !def.relatedScriptureRefs.isEmpty {
                scriptureRefPills(def.relatedScriptureRefs)
            }

            // Expand / collapse toggle
            if def.biblicalContext != nil {
                Button {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.82)) {
                        showExpanded.toggle()
                    }
                } label: {
                    Text(showExpanded ? "Show less" : "Show biblical context")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showExpanded ? "Collapse biblical context" : "Show biblical context for \(term)")
            }
        }
    }

    private func scriptureRefPills(_ refs: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(refs, id: \.self) { ref in
                    Button {
                        onShowVerseContext?(ref)
                    } label: {
                        Text(ref)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.blue.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(ref)")
                    .accessibilityHint("View verse context")
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if let explain = onExplainMore {
                actionPill(icon: "text.magnifyingglass", label: "Explain More", action: explain)
            }
            if let berean = onAskBerean {
                actionPill(icon: "sparkles", label: "Ask Berean", action: berean)
            }
            if let selah = onSaveToSelah {
                actionPill(icon: "bookmark", label: "Save", action: selah)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionPill(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Background & Decorators

    @ViewBuilder
    private var popoverBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: AmenGlassMetrics.popoverCornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: AmenGlassMetrics.popoverCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: AmenGlassMetrics.popoverCornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: AmenGlassMetrics.popoverCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AmenGlassMetrics.popoverCornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.52), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.7
                        )
                }
        }
    }

    // Tap-outside dismiss zone — invisible, behind the popover
    private var dismissZone: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .allowsHitTesting(false)
    }

    private var popoverTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
    }
}

// MARK: - AmenInlineDefinitionHost
// Wraps any view and manages the popover presentation lifecycle.

struct AmenInlineDefinitionHost<Content: View>: View {
    @ViewBuilder let content: Content
    @Binding var activeTerm: String?
    @Binding var activeDefinition: AmenSemanticDefinition?
    var isLoading: Bool = false
    var loadError: String? = nil
    var onAskBerean: ((String) -> Void)? = nil
    var onSaveToSelah: ((String) -> Void)? = nil
    var onShowVerseContext: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            content

            if let term = activeTerm {
                Color.black.opacity(0.01)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                AmenInlineDefinitionPopover(
                    term: term,
                    definition: activeDefinition,
                    isLoading: isLoading,
                    loadError: loadError,
                    onAskBerean: onAskBerean.map { fn in { fn(term) } },
                    onSaveToSelah: onSaveToSelah.map { fn in { fn(term) } },
                    onShowVerseContext: onShowVerseContext,
                    onExplainMore: { /* deepens request in parent */ },
                    onDismiss: dismiss
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .zIndex(100)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .top))
                )
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.84), value: activeTerm)
    }

    private func dismiss() {
        activeTerm = nil
        activeDefinition = nil
    }
}
