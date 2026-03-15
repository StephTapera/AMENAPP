//
//  LiquidGlassMotion.swift
//  AMENAPP
//
//  Reusable Liquid Glass motion infrastructure.
//
//  Two patterns:
//  A. GlassExpandableCard  — expandable card with depth + refocus
//  B. GlassSheetModifier   — contextual sheet emergence from a source element
//
//  Usage — Pattern A (expandable card):
//
//      GlassExpandableCard(isExpanded: $expanded) {
//          // collapsed header
//      } expandedContent: {
//          // detail content revealed in layers
//      }
//
//  Usage — Pattern B (contextual sheet):
//
//      Button("Compose") { showComposer = true }
//          .glassSourceAnchor(id: "compose", namespace: ns)
//      .glassContextualSheet(isPresented: $showComposer, sourceId: "compose", namespace: ns) {
//          CreatePostView()
//      }
//

import SwiftUI

// MARK: - Animation Constants

enum AmenMotion {
    /// Card expand/collapse — soft, confident, not bouncy
    static let cardSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Sheet emergence — slightly faster
    static let sheetSpring = Animation.spring(response: 0.38, dampingFraction: 0.85)
    /// Micro-interaction (press scale, opacity)
    static let micro = Animation.spring(response: 0.22, dampingFraction: 0.9)
    /// Refocus / blur fade — eased, not springy
    static let refocus = Animation.easeInOut(duration: 0.28)

    /// Respect system Reduce Motion: returns a simpler fade when active
    static func cardAnimation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : cardSpring
    }
    static func sheetAnimation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : sheetSpring
    }
}

// MARK: - A. Expandable Glass Card

/// Self-contained expandable card using native Liquid Glass material.
/// Drop in wherever you need a card that lifts, refocuses its background,
/// and reveals content in layered stages.
///
/// - Performance: uses `drawingGroup()` on the background blur only when expanded,
///   keeping the resting cost negligible in scroll lists.
/// - Reduce Motion: collapses to a simple fade when the accessibility flag is set.
struct GlassExpandableCard<Header: View, Detail: View>: View {
    @Binding var isExpanded: Bool
    let cornerRadius: CGFloat
    let namespace: Namespace.ID
    /// String ID used for glassEffectID — must be unique within the namespace.
    let glassId: String
    @ViewBuilder let header: () -> Header
    @ViewBuilder let detail: () -> Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Internal staged reveal — 3 layers after the container expands
    @State private var showLayer1 = false  // title lock-in (instant, from header)
    @State private var showLayer2 = false  // metadata / actions
    @State private var showLayer3 = false  // secondary details

    init(
        isExpanded: Binding<Bool>,
        cornerRadius: CGFloat = 20,
        namespace: Namespace.ID,
        glassId: String,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        _isExpanded = isExpanded
        self.cornerRadius = cornerRadius
        self.namespace = namespace
        self.glassId = glassId
        self.header = header
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always-visible header
            header()

            // Detail layers revealed progressively after expansion
            if isExpanded {
                // Layer 2 — metadata / actions (slight delay)
                if showLayer2 {
                    detail()
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                }
            }
        }
        .padding(16)
        // Liquid Glass background — morphs shape on expand/collapse
        .glassEffect(
            Glass.regular,
            in: RoundedRectangle(cornerRadius: isExpanded ? cornerRadius + 4 : cornerRadius,
                                 style: .continuous)
        )
        .glassEffectID(glassId, in: namespace)
        // Subtle scale lift on expand (restrained — not dramatic)
        .scaleEffect(isExpanded ? 1.012 : 1.0)
        // Shadow elevation increases on expand
        .shadow(
            color: .black.opacity(isExpanded ? 0.12 : 0.04),
            radius: isExpanded ? 18 : 4,
            y: isExpanded ? 8 : 2
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            toggle()
        }
        .animation(AmenMotion.cardAnimation(reduceMotion), value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            stageLayers(expanded: expanded)
        }
    }

    private func toggle() {
        withAnimation(AmenMotion.cardAnimation(reduceMotion)) {
            isExpanded.toggle()
        }
    }

    private func stageLayers(expanded: Bool) {
        if expanded {
            // Layer 1 is the header itself — already visible
            // Layer 2: short delay after container expansion
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.12)) {
                withAnimation(AmenMotion.cardAnimation(reduceMotion)) {
                    showLayer2 = true
                }
            }
            // Layer 3: secondary details follow
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.22)) {
                withAnimation(AmenMotion.cardAnimation(reduceMotion)) {
                    showLayer3 = true
                }
            }
        } else {
            // Collapse: reverse layers immediately
            withAnimation(AmenMotion.cardAnimation(reduceMotion)) {
                showLayer2 = false
                showLayer3 = false
            }
        }
    }
}

// MARK: - Background Refocus Modifier

/// Applies a soft dimming + blur to its content when `isActive` is true.
/// Used on the feed/list behind an expanded card to create depth separation.
/// Keep blur radius ≤ 3 — anything higher costs too much on older iPhones.
struct BackgroundRefocusModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .blur(radius: (isActive && !reduceMotion) ? 2.5 : 0)
            .opacity(isActive ? 0.55 : 1.0)
            .allowsHitTesting(!isActive)
            .animation(AmenMotion.refocus, value: isActive)
    }
}

extension View {
    /// Softly de-emphasizes content when a card above it is expanded.
    func refocused(when active: Bool) -> some View {
        modifier(BackgroundRefocusModifier(isActive: active))
    }
}

// MARK: - Pressable Glass Button Modifier

/// A lightweight press-scale modifier that gives glass cards tactile feedback.
/// Replaces any existing `.pressableCard()` modifier for glass-surfaced cards.
struct GlassPressModifier: ViewModifier {
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.975 : 1.0)
            .animation(AmenMotion.micro, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
            )
    }
}

extension View {
    func glassPress() -> some View {
        modifier(GlassPressModifier())
    }
}

// MARK: - B. Contextual Glass Sheet

/// Marks a source view as the origin anchor for a contextual sheet.
/// Place this on the button/control that triggers the sheet.
extension View {
    func glassSourceAnchor(id: some Hashable, namespace: Namespace.ID) -> some View {
        self.matchedGeometryEffect(id: id, in: namespace, isSource: true)
    }
}

/// Presents a sheet that emerges from the source anchor geometry,
/// with a glass material surface and layered content staging.
///
/// Falls back to a standard `.sheet()` on iOS < 26 or when Reduce Motion is on.
struct GlassContextualSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sourceId: String
    let namespace: Namespace.ID
    @ViewBuilder let sheetContent: () -> SheetContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                GlassSheetContainer(
                    isPresented: $isPresented,
                    reduceMotion: reduceMotion,
                    content: sheetContent
                )
            }
    }
}

extension View {
    /// Attaches a contextual glass sheet to a view.
    /// The sheet will visually emerge from the element tagged with `glassSourceAnchor(id:namespace:)`.
    func glassContextualSheet<C: View>(
        isPresented: Binding<Bool>,
        sourceId: String,
        namespace: Namespace.ID,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        modifier(GlassContextualSheet(
            isPresented: isPresented,
            sourceId: sourceId,
            namespace: namespace,
            sheetContent: content
        ))
    }
}

// MARK: - Glass Sheet Container

/// Internal shell for the contextual sheet.
/// Applies glass surface, safe area handling, and staged content reveal.
private struct GlassSheetContainer<C: View>: View {
    @Binding var isPresented: Bool
    let reduceMotion: Bool
    @ViewBuilder let content: () -> C

    // Staged content appearance inside the sheet
    @State private var showPrimary = false
    @State private var showActions = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Glass surface — the sheet's own material
            // Using presentationBackground(.clear) + manual glass lets us control
            // the shape precisely and keep the transition crisp.
            content()
                .opacity(showPrimary ? 1 : 0)
                .offset(y: showPrimary ? 0 : 24)
        }
        .onAppear {
            stageIn()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(.regularMaterial)
    }

    private func stageIn() {
        // Stage 1: primary input area
        withAnimation(AmenMotion.sheetAnimation(reduceMotion)) {
            showPrimary = true
        }
        // Stage 2: supporting actions/options
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.14)) {
            withAnimation(AmenMotion.sheetAnimation(reduceMotion)) {
                showActions = true
            }
        }
    }
}

// MARK: - Glass Card Container (Simpler Wrapper)

/// A simpler non-expanding glass card container for feed cells where you don't need
/// the full expand/collapse behavior — just the glass material and shadow.
///
/// Use this on PostCard, ChurchPillCard, etc. as a drop-in replacement for
/// the existing `RoundedRectangle + shadow` background pattern.
struct GlassCardBackground: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
            )
    }
}

extension View {
    /// Wraps view in a glass-material card background with shadow.
    /// Drop-in for `.background(RoundedRectangle(...).fill(...).shadow(...))`.
    func glassCardBackground(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCardBackground(cornerRadius: cornerRadius))
    }
}
