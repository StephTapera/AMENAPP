//
//  VerseDrawerCoordinator.swift
//  AMENAPP
//
//  Two-stage verse drawer coordinator
//  Manages mini → full drawer transitions via native iOS presentation detents
//

import SwiftUI

// MARK: - Coordinator Sheet

struct VerseDrawerCoordinator: View {
    @Binding var isPresented: Bool
    let onAttach: (BibleVerse) -> Void

    @StateObject private var searchEngine = VerseSmartSearchEngine()
    @StateObject private var baseViewModel = AttachVerseViewModel()

    @State private var selectedDetent: PresentationDetent = .medium
    @State private var searchText = ""
    @State private var selectedVerse: BibleVerse?
    @State private var selectedTranslation: LocalBibleTranslation = .BSB

    // Whether the user has manually expanded to full
    private var isExpanded: Bool { selectedDetent == .large }

    var body: some View {
        // Wrap in a NavigationStack so the sheet has its own nav scope
        NavigationStack {
            Group {
                if isExpanded {
                    VerseFullDrawerView(
                        searchText: $searchText,
                        selectedVerse: $selectedVerse,
                        translation: $selectedTranslation,
                        searchEngine: searchEngine,
                        baseViewModel: baseViewModel,
                        onAttach: attachVerse,
                        onDismiss: dismissDrawer
                    )
                } else {
                    VerseMiniDrawerView(
                        searchText: $searchText,
                        selectedVerse: $selectedVerse,
                        translation: $selectedTranslation,
                        searchEngine: searchEngine,
                        baseViewModel: baseViewModel,
                        onExpand: expandToFull,
                        onAttach: attachVerse,
                        onDismiss: dismissDrawer
                    )
                }
            }
            .animation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.82)), value: isExpanded)
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
        .onChange(of: isPresented) { _, presented in
            if !presented { resetState() }
        }
    }

    // MARK: - Actions

    private func expandToFull() {
        withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.82))) {
            selectedDetent = .large
        }
    }

    private func dismissDrawer() {
        isPresented = false
    }

    private func attachVerse() {
        guard let verse = selectedVerse else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        onAttach(verse)
        isPresented = false
    }

    private func resetState() {
        searchText = ""
        selectedVerse = nil
        selectedDetent = .medium
        searchEngine.results = []
    }
}

// MARK: - Presentation Modifier

struct VerseDrawerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onAttach: (BibleVerse) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                VerseDrawerCoordinator(
                    isPresented: $isPresented,
                    onAttach: onAttach
                )
            }
    }
}

extension View {
    func verseDrawer(isPresented: Binding<Bool>, onAttach: @escaping (BibleVerse) -> Void) -> some View {
        modifier(VerseDrawerModifier(isPresented: isPresented, onAttach: onAttach))
    }
}
