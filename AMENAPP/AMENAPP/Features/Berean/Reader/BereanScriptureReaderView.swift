// BereanScriptureReaderView.swift
// AMEN — Berean Reading Surface: Scripture Reader (W5)
// Flag: bereanReaderActions (default false)
//
// Share: confirmation alert required before Guard routing.
// Verse selection: contextMenu with AI actions routing through BereanContextActionEngine.

import SwiftUI

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct BereanScriptureReaderView: View {

    var passageTitle: String
    var verseText: String

    @State private var isActionRowCollapsed = false
    @State private var lastScrollY: CGFloat = 0
    @State private var showShareConfirmation = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedVerseRange: String? = nil
    @State private var showVerseMenu = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        passageTitle: String = "John 1:1–5",
        verseText: String = BereanScriptureReaderView.sampleVerse
    ) {
        self.passageTitle = passageTitle
        self.verseText = verseText
    }

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let err = errorMessage {
                errorView(err)
            } else {
                readerView
            }
        }
        .background(Color.bereanWhite.ignoresSafeArea())
        .alert("Share Passage?", isPresented: $showShareConfirmation) {
            Button("Share") {
                // TODO: UGC SAFETY — route through GUARDIAN/Aegis Guard mode before sharing.
                //       Do not invoke system share sheet without Guard clearance.
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This passage will be shared from your reading session.")
        }
    }

    // MARK: - Reader

    private var readerView: some View {
        ZStack(alignment: .bottom) {
            // Scroll content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer(minLength: 20)

                    Text(passageTitle)
                        .font(BereanReaderType.sectionHeader)
                        .foregroundStyle(Color.bereanInk)
                        .padding(.horizontal, 28)

                    Text(verseText)
                        .font(BereanReaderType.body)
                        .foregroundStyle(Color.bereanInk)
                        .lineSpacing(10)
                        .padding(.horizontal, 28)
                        .contextMenu {
                            Button("Highlight", systemImage: "highlighter") { }
                            Button("Add Note", systemImage: "note.text.badge.plus") { }
                            Divider()
                            Button("Cross-Reference", systemImage: "arrow.triangle.branch") {
                                handleAction(.crossReference)
                            }
                            Button("Original Language", systemImage: "character.book.closed") {
                                handleAction(.originalLanguage)
                            }
                            Button("Ask Berean", systemImage: "sparkle") {
                                handleAction(.askBerean)
                            }
                        }
                        .accessibilityAction(named: "Ask Berean about this passage") {
                            handleAction(.explainPassage)
                        }

                    Spacer(minLength: 100)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("readerScroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "readerScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                let delta = value - lastScrollY
                if delta < -8 {
                    withAnimation(.berean(BereanSpring.actionRowCollapse, reduceMotion: reduceMotion)) {
                        isActionRowCollapsed = true
                    }
                } else if delta > 8 {
                    withAnimation(.berean(BereanSpring.actionRowCollapse, reduceMotion: reduceMotion)) {
                        isActionRowCollapsed = false
                    }
                }
                lastScrollY = value
            }

            // Scripture action row
            VStack(spacing: 0) {
                ScriptureActionRow(
                    passageTitle: passageTitle,
                    isCollapsed: isActionRowCollapsed,
                    onSave: handleSave,
                    onShare: { showShareConfirmation = true },
                    onPray: { handleAction(.guidedPrayer) },
                    onExplain: { handleAction(.explainPassage) },
                    onMore: { /* expanded options */ }
                )
                .background(
                    Color.bereanIvory.opacity(0.95)
                        .background(.ultraThinMaterial)
                )
            }
        }
    }

    private var loadingView: some View {
        VStack { Spacer(); WordGlowLoader(); Spacer() }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.closed").font(.system(size: 40)).foregroundStyle(Color.bereanInk.opacity(0.4))
            Text(message).font(BereanType.body()).foregroundStyle(Color.bereanInk.opacity(0.7))
            Button("Retry") { errorMessage = nil }.font(BereanType.subheadline())
            Spacer()
        }
    }

    // MARK: - Actions

    private func handleSave() {
        // TODO: Save passage via existing notes/bookmarks path
    }

    private func handleAction(_ action: BereanAIAction) {
        // TODO: Route through BereanContextActionEngine.perform(action: action, payload: ["passage": verseText, "reference": passageTitle])
        //       action.routesTo → .ask / .discern / .reflect determines callable.
        print("Scripture action: \(action.displayName) → \(action.routesTo.rawValue)")
    }

    static let sampleVerse = """
    In the beginning was the Word, and the Word was with God, and the Word was God. \
    He was with God in the beginning. Through him all things were made; without him \
    nothing was made that has been made. In him was life, and that life was the light \
    of all mankind. The light shines in the darkness, and the darkness has not overcome it.
    """
}

#Preview {
    BereanScriptureReaderView()
}
