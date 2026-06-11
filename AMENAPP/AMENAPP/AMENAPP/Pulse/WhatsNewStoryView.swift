//
//  WhatsNewStoryView.swift
//  AMEN — Amen Pulse (What's New editorial)
//
//  WWDC-style swipeable full-screen story. Each page is a full-bleed hero
//  (image or gradient) with a headline + body laid over the lower third, a
//  custom animated page-dot row, and a bottom action row (Try It Now + bookmark).
//  Binds to the frozen WhatsNewStory contract in PulseModels.swift — does not
//  redefine any types. Presented via .fullScreenCover(item:).
//

import SwiftUI

struct WhatsNewStoryView: View {
    let storyId: String

    init(storyId: String) {
        self.storyId = storyId
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var story: WhatsNewStory?
    @State private var pageIndex: Int = 0
    @State private var isBookmarked: Bool = false
    @State private var didLoadBookmark: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story {
                content(for: story)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            closeButton
        }
        .task {
            await load()
        }
    }

    // MARK: - Loading

    private func load() async {
        let loaded = try? await PulseService.shared.loadStory(id: storyId)
        if let loaded {
            story = loaded
        } else {
            #if DEBUG
            story = Self.sampleStory(id: storyId)
            #endif
        }

        if !didLoadBookmark {
            didLoadBookmark = true
            if let bookmarks = try? await PulseService.shared.loadBookmarks() {
                isBookmarked = bookmarks.contains(storyId)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for story: WhatsNewStory) -> some View {
        VStack(spacing: 0) {
            TabView(selection: $pageIndex) {
                ForEach(Array(story.pages.enumerated()), id: \.offset) { index, page in
                    PageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            controlsBar(for: story)
        }
    }

    private func controlsBar(for story: WhatsNewStory) -> some View {
        VStack(spacing: 18) {
            pageDots(count: story.pages.count)

            HStack(spacing: 12) {
                if let tryAction = story.tryAction {
                    Button {
                        openDeeplink(tryAction.deeplink)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold))
                            Text(tryAction.label.isEmpty ? "Try It Now" : tryAction.label)
                                .font(.system(size: 16.5, weight: .bold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.black)
                        .background(Capsule().fill(Color.white))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Try it now"))
                    .accessibilityHint(Text(tryAction.label))
                }

                Button {
                    toggleBookmark()
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isBookmarked ? "Remove bookmark" : "Bookmark this update"))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(Color.black)
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i == pageIndex ? Color.white : Color.white.opacity(0.32))
                    .frame(width: i == pageIndex ? 22 : 7, height: 7)
                    .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.85), value: pageIndex)
            }
        }
        .accessibilityHidden(true)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(hex: "787880").opacity(0.45)))
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 54)
    }

    // MARK: - Actions

    private func toggleBookmark() {
        let next = !isBookmarked
        isBookmarked = next
        Task {
            do {
                try await PulseService.shared.setBookmark(storyId: storyId, bookmarked: next)
            } catch {
                // Revert optimistic toggle on failure.
                isBookmarked = !next
            }
        }
    }

    private func openDeeplink(_ deeplink: String) {
        guard let url = URL(string: deeplink) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Page

    private struct PageView: View {
        let page: WhatsNewPage

        private var scrim: PulseScrim {
            PulseHeroStyle.resolve(page.style ?? "whatsnew").scrim
        }

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: textAlignment) {
                    hero
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    PulseScrimOverlay(scrim: scrim)

                    textBlock
                        .padding(.horizontal, 28)
                        .padding(.bottom, page.layout == .captionOver ? geo.size.height * 0.16 : 48)
                        .padding(.top, page.layout == .captionOver ? 0 : geo.size.height * 0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        }

        @ViewBuilder
        private var hero: some View {
            if let urlString = page.heroImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ZStack {
                            PulseHeroStyle.resolve(page.style ?? "whatsnew").background()
                            ProgressView().tint(.white)
                        }
                    case .failure:
                        PulseHeroStyle.resolve(page.style ?? "whatsnew").background()
                    @unknown default:
                        PulseHeroStyle.resolve(page.style ?? "whatsnew").background()
                    }
                }
            } else {
                PulseHeroStyle.resolve(page.style ?? "whatsnew").background()
            }
        }

        private var textAlignment: Alignment {
            page.layout == .captionOver ? .bottomLeading : .bottomLeading
        }

        private var textColor: Color {
            scrim == .dark ? .white : Color(hex: "1C1C1E")
        }

        private var textBlock: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(page.headline)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.body)
                    .font(.system(size: 17))
                    .foregroundColor(textColor.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .shadow(color: scrim == .dark ? Color.black.opacity(0.4) : Color.clear, radius: 8, y: 2)
        }
    }

    // MARK: - DEBUG sample

    #if DEBUG
    static func sampleStory(id: String) -> WhatsNewStory {
        WhatsNewStory(
            id: id,
            version: "v3.2",
            title: "Amen Pulse",
            tagline: "Your day, gathered into one calm surface.",
            pages: [
                WhatsNewPage(
                    style: "whatsnew",
                    headline: "A calmer way to catch up",
                    body: "Amen Pulse gathers what matters today into a small, finite set of cards — then ends. No endless scroll.",
                    layout: .fullBleed
                ),
                WhatsNewPage(
                    style: "brief",
                    headline: "One Daily Brief",
                    body: "Read in 30 seconds, 3 minutes, or 10. You choose the depth; we never nag you back.",
                    layout: .captionOver
                ),
                WhatsNewPage(
                    style: "prayer",
                    headline: "Prayer that follows up",
                    body: "Gentle reminders to return to the people you said you'd pray for.",
                    layout: .split
                )
            ],
            tryAction: WhatsNewTryAction(deeplink: "amen://pulse", label: "Open Pulse"),
            audience: .all,
            publishedAt: Date(),
            bookmarkable: true
        )
    }
    #endif
}

#if DEBUG
#Preview {
    WhatsNewStoryView(storyId: "sample-story")
}
#endif
