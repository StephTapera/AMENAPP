// ScriptureIntelligenceView.swift
// AMEN Capabilities v1 — Scripture detection overlay modifier (Wave 1: Lane E)
//
// Provides a `.scriptureIntelligence(onInsertVerse:)` ViewModifier that:
//   • Overlays a "Detecting references..." status indicator (bottom-aligned) while detection runs
//   • Presents a VerseCardView popover when the user taps a detected reference
//   • Injects the shared ScriptureDetectionService via Environment so child views can
//     call `detectReferences(in:)` without needing to own the service.
//
// Also exposes ScriptureIntelligenceView as a standalone view for use in navigation stacks
// that need to present the detection surface without embedding a live editor.
//
// Flag gate: AMENFeatureFlags.shared.scriptureIntelligenceEnabled — checked inside
//   ScriptureDetectionService; the modifier itself is always applicable.

import SwiftUI

// MARK: - Environment Key

private struct DetectionServiceKey: EnvironmentKey {
    static let defaultValue: ScriptureDetectionService? = nil
}

extension EnvironmentValues {
    /// The shared ScriptureDetectionService injected by ScriptureIntelligenceModifier.
    var detectionService: ScriptureDetectionService? {
        get { self[DetectionServiceKey.self] }
        set { self[DetectionServiceKey.self] = newValue }
    }
}

// MARK: - ScriptureIntelligenceModifier

/// A ViewModifier that layers scripture detection onto any block-based note editor.
/// Apply via `.scriptureIntelligence(onInsertVerse:)`.
struct ScriptureIntelligenceModifier: ViewModifier {

    // MARK: State

    @StateObject private var detectionService = ScriptureDetectionService()
    @State private var selectedRef: ScriptureRef? = nil

    // MARK: Input

    /// Called when the user taps "Insert Verse" in the verse card popover.
    var onInsertVerse: ((VerseCard) -> Void)?

    // MARK: Body

    func body(content: Content) -> some View {
        content
            // Detecting status pill — anchored at the bottom edge of the editor
            .overlay(alignment: .bottom) {
                if detectionService.isDetecting {
                    detectingBadge
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeInOut(duration: 0.2), value: detectionService.isDetecting)
                }
            }
            // Verse card popover on reference tap
            .popover(item: $selectedRef) { ref in
                VerseCardView(
                    initialRef: ref,
                    onInsert: { card in
                        onInsertVerse?(card)
                        selectedRef = nil
                    }
                )
                .frame(minWidth: 300, maxWidth: 400)
            }
            // Inject service into the environment so descendant views can reach it
            .environment(\.detectionService, detectionService)
    }

    // MARK: - Sub-views

    private var detectingBadge: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
                .accessibilityHidden(true)
            Text("Detecting references…")
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel("Detecting scripture references")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - View Extension

extension View {
    /// Wraps a view in the scripture intelligence detection system.
    /// The injected `ScriptureDetectionService` is accessible via
    /// `@Environment(\.detectionService)` in descendant views.
    ///
    /// - Parameter onInsertVerse: Called when the user inserts a verse into the editor.
    func scriptureIntelligence(onInsertVerse: ((VerseCard) -> Void)? = nil) -> some View {
        modifier(ScriptureIntelligenceModifier(onInsertVerse: onInsertVerse))
    }
}

// MARK: - ScriptureIntelligenceView (Standalone)

/// Standalone navigation-stack presentable wrapper around the scripture detection surface.
/// For use in flows that route to scripture intelligence via a navigation link rather than
/// embedding it as a modifier on an existing editor.
struct ScriptureIntelligenceView: View {

    /// The note blocks to analyse on appear.
    let blocks: [(blockId: String, text: String)]
    /// Called when the user chooses to insert a resolved verse into the calling surface.
    var onInsertVerse: ((VerseCard) -> Void)? = nil

    @StateObject private var service = ScriptureDetectionService()
    @State private var selectedRef: ScriptureRef? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if service.isDetecting {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Detecting references…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Detecting scripture references")
            } else if service.detections.isEmpty {
                Text("No scripture references detected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Detected References")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(service.detections) { ref in
                            Button {
                                selectedRef = ref
                            } label: {
                                Text(ref.display)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            }
                            .accessibilityLabel(ref.display)
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
        }
        .padding()
        .popover(item: $selectedRef) { ref in
            VerseCardView(
                initialRef: ref,
                onInsert: { card in
                    onInsertVerse?(card)
                    selectedRef = nil
                }
            )
            .frame(minWidth: 300, maxWidth: 400)
        }
        .task {
            service.detectReferences(in: blocks)
        }
        .navigationTitle("Scripture Intelligence")
        .navigationBarTitleDisplayMode(.inline)
    }
}
