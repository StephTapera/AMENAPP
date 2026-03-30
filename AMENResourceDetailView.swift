// AMENResourceDetailView.swift
// AMENAPP
//
// Premium editorial media detail screen.
// Reference: Apple Wikipedia card — full-bleed hero, large display headline over
// image gradient scrim, then structured content rows beneath.
// AMEN adaptation: liquid-glass surfaces, warm spiritual palette, calm pacing.

import SwiftUI
import WebKit

// MARK: - Entry point (type-erased)

enum AMENMediaEntry: Hashable {
    case sermon(AMENSermon)
    case podcast(AMENPodcastEpisode)
    case worship(AMENWorshipTrack)
}

// MARK: - Main view

struct AMENResourceDetailView: View {
    let entry: AMENMediaEntry
    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false
    @State private var showPlayer = false
    @State private var activeTab: MediaTab = .overview
    @State private var heroOffset: CGFloat = 0
    @State private var tabBarVisible = false
    @State private var sectionAppeared: Set<String> = []

    // MARK: Derived metadata

    private var title: String {
        switch entry {
        case .sermon(let s):  return s.title
        case .podcast(let p): return p.title
        case .worship(let w): return w.title
        }
    }
    private var speakerLine: String {
        switch entry {
        case .sermon(let s):  return s.speaker
        case .podcast(let p): return p.host
        case .worship(let w): return w.artist
        }
    }
    private var sourceLine: String {
        switch entry {
        case .sermon(let s):  return s.church
        case .podcast(let p): return p.showName
        case .worship(let w): return w.album ?? w.artist
        }
    }
    private var thumbnailURL: String? {
        switch entry {
        case .sermon(let s):  return s.thumbnailURL
        case .podcast(let p): return p.thumbnailURL
        case .worship(let w): return w.thumbnailURL
        }
    }
    private var description: String? {
        switch entry {
        case .sermon(let s):  return s.description
        case .podcast(let p): return p.description
        case .worship:        return nil
        }
    }
    private var scripture: String? {
        switch entry {
        case .sermon(let s):  return s.scriptureReference
        case .podcast:        return nil
        case .worship(let w): return w.scriptureReference
        }
    }
    private var duration: String? {
        let secs: Int?
        switch entry {
        case .sermon(let s):  secs = s.durationSeconds
        case .podcast(let p): secs = p.durationSeconds
        case .worship(let w): secs = w.durationSeconds
        }
        guard let s = secs, s > 0 else { return nil }
        let m = s / 60; let sec = s % 60
        return sec == 0 ? "\(m) min" : "\(m):\(String(format: "%02d", sec))"
    }
    private var embedURL: URL? {
        switch entry {
        case .sermon(let s):  return s.embedURL
        case .podcast(let p): return p.spotifyEmbedURL
        case .worship(let w): return w.spotifyEmbedURL
        }
    }
    private var deepLinkURL: URL? {
        switch entry {
        case .sermon(let s):  return s.deepLinkURL
        case .podcast(let p): return p.deepLinkURL
        case .worship(let w): return w.deepLinkURL
        }
    }
    private var mediaTypeIcon: String {
        switch entry {
        case .sermon:  return "video.fill"
        case .podcast: return "headphones"
        case .worship: return "music.note"
        }
    }
    private var typeLabel: String {
        switch entry {
        case .sermon:  return "Sermon"
        case .podcast: return "Podcast"
        case .worship: return "Worship"
        }
    }
    private var accentColor: Color {
        switch entry {
        case .sermon:  return Color(red: 0.42, green: 0.28, blue: 0.82) // warm violet
        case .podcast: return Color(red: 0.14, green: 0.52, blue: 0.36) // sage green
        case .worship: return Color(red: 0.72, green: 0.36, blue: 0.16) // warm amber
        }
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    tabBarSection
                    tabContent
                        .padding(.bottom, 60)
                }
            }
            .ignoresSafeArea(edges: .top)
            .coordinateSpace(name: "mediaScroll")

            // Floating dismiss + actions
            floatingBar
        }
        .navigationBarHidden(true)
    }

    // MARK: - Hero (reference-style: full-bleed + large headline over gradient scrim)

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {

            // Full-bleed image with parallax
            GeometryReader { geo in
                let minY = geo.frame(in: .named("mediaScroll")).minY
                Group {
                    if let urlStr = thumbnailURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                heroPlaceholder
                            }
                        }
                    } else {
                        heroPlaceholder
                    }
                }
                .frame(width: geo.size.width, height: max(geo.size.height + max(0, minY), geo.size.height))
                .clipped()
                .offset(y: minY > 0 ? -minY * 0.35 : 0)
                // Reveal tab bar when hero scrolls mostly out of view
                .onChange(of: minY) { _, newVal in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tabBarVisible = newVal < -260
                    }
                }
            }
            .frame(height: 420)

            // Three-stop gradient scrim: clear top → dark bottom (Apple reference style)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.12), location: 0.45),
                    .init(color: .black.opacity(0.72), location: 0.80),
                    .init(color: Color(.systemBackground), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 420)

            // Hero text stack — sits over scrim at bottom-left like reference
            VStack(alignment: .leading, spacing: 6) {

                // Type pill
                HStack(spacing: 5) {
                    Image(systemName: mediaTypeIcon)
                        .font(.system(size: 10, weight: .bold))
                    Text(typeLabel.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(accentColor.opacity(0.35), lineWidth: 1))

                // Large display headline
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)

                // Speaker / source line
                HStack(spacing: 6) {
                    Text(speakerLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    if !sourceLine.isEmpty && sourceLine != speakerLine {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.5))
                        Text(sourceLine)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                // Duration chip
                if let dur = duration {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text(dur)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.70))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
    }

    private var heroPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor.opacity(0.55), accentColor.opacity(0.28)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: mediaTypeIcon)
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    // MARK: - Play / action row (just below hero, before tabs)

    private var actionRow: some View {
        HStack(spacing: 12) {
            // Primary play button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    showPlayer.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 34, height: 34)
                        Image(systemName: showPlayer ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: showPlayer ? 0 : 1.5)
                    }
                    Text(showPlayer ? "Stop" : playLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(accentColor.opacity(0.22), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(MediaPressEffect())

            // Save
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isSaved.toggle() }
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSaved ? accentColor : .secondary)
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Share
            if let url = deepLinkURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, height: 46)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var playLabel: String {
        switch entry {
        case .sermon:  return "Watch Sermon"
        case .podcast: return "Listen"
        case .worship: return "Play Track"
        }
    }

    // MARK: - Tab bar

    enum MediaTab: String, CaseIterable {
        case overview = "Overview"
        case notes    = "Notes"
        case scripture = "Scripture"
        case related  = "Related"
    }

    private var tabBarSection: some View {
        VStack(spacing: 0) {
            actionRow

            // Inline player (expands below action row)
            if showPlayer, let url = embedURL {
                MediaEmbedWebView(url: url)
                    .frame(height: playerHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: accentColor.opacity(0.18), radius: 12, y: 6)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            editorialDivider
                .padding(.bottom, 4)

            // Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(MediaTab.allCases, id: \.self) { tab in
                        tabPill(tab)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }

            editorialDivider
        }
    }

    private func tabPill(_ tab: MediaTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                activeTab = tab
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 14, weight: activeTab == tab ? .semibold : .regular))
                .foregroundStyle(activeTab == tab ? accentColor : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(activeTab == tab ? accentColor.opacity(0.12) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(activeTab == tab ? accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .overview:
            overviewContent
                .transition(.opacity)
        case .notes:
            notesContent
                .transition(.opacity)
        case .scripture:
            scriptureContent
                .transition(.opacity)
        case .related:
            relatedContent
                .transition(.opacity)
        }
    }

    // MARK: Overview

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Description
            if let desc = description, !desc.isEmpty {
                editorialSection(label: "About") {
                    Text(desc)
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Key info rows (Apple-reference style: label-value table)
            editorialSection(label: "Details") {
                VStack(spacing: 0) {
                    infoRow(label: typeLabel == "Sermon" ? "Speaker" : "Host", value: speakerLine)
                    editorialDivider.padding(.horizontal, 0)
                    infoRow(label: typeLabel == "Sermon" ? "Church" : "Show", value: sourceLine)
                    if let dur = duration {
                        editorialDivider.padding(.horizontal, 0)
                        infoRow(label: "Duration", value: dur)
                    }
                    if case .sermon(let s) = entry, let series = s.series {
                        editorialDivider.padding(.horizontal, 0)
                        infoRow(label: "Series", value: series)
                    }
                    if case .sermon(let s) = entry, let topic = s.topic as String?, !topic.isEmpty {
                        editorialDivider.padding(.horizontal, 0)
                        infoRow(label: "Topic", value: topic)
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Affiliate books row
            if case .sermon(let s) = entry {
                editorialSection(label: "Resources") {
                    affiliateCard(bookTitle: "\(s.title) — Study Guide", bookAuthor: s.speaker)
                }
            }

            // Open external
            if let url = deepLinkURL {
                openExternalButton(url: url)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }

            Text(AffiliateConfig.disclosure)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
    }

    // MARK: Notes

    private var notesContent: some View {
        editorialSection(label: "My Notes") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your personal notes for this message will appear here.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                Button {
                    // Future: open notes editor
                } label: {
                    Label("Add a Note", systemImage: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accentColor)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Scripture

    private var scriptureContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let ref = scripture {
                editorialSection(label: "Scripture Reference") {
                    scriptureCard(ref)
                }
            } else {
                editorialSection(label: "Scripture") {
                    Text("No scripture references tagged for this content.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Related

    private var relatedContent: some View {
        editorialSection(label: "Related Content") {
            VStack(spacing: 12) {
                relatedPlaceholderRow(icon: "video.fill", label: "More from \(speakerLine)", color: accentColor)
                relatedPlaceholderRow(icon: "headphones", label: "Recommended Podcasts", color: .teal)
                relatedPlaceholderRow(icon: "book.fill", label: "Study Series", color: .orange)
            }
        }
    }

    // MARK: - Reusable editorial components

    /// Section with small-caps label and content
    private func editorialSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.horizontal, 20)

            content()
                .padding(.horizontal, 20)
        }
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    /// Apple-reference info row: plain label left, value right
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Scripture glass card with accent stripe
    private func scriptureCard(_ reference: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 3)
                .frame(minHeight: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("Scripture")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(reference)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.system(size: 18))
                .foregroundStyle(accentColor.opacity(0.7))
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    /// Affiliate book card
    private func affiliateCard(bookTitle: String, bookAuthor: String) -> some View {
        HStack(spacing: 14) {
            // Book cover placeholder
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.45), accentColor.opacity(0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 68)
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.7))
                )
                .shadow(color: accentColor.opacity(0.25), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(bookTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(bookAuthor)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    affiliatePill(label: "Amazon", color: Color(red: 0.95, green: 0.49, blue: 0.0)) {
                        if let encoded = bookTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://www.amazon.com/s?k=\(encoded)&tag=\(AffiliateConfig.amazonTag)") {
                            UIApplication.shared.open(url)
                        }
                    }
                    affiliatePill(label: "Apple Books", color: Color(red: 0.22, green: 0.44, blue: 0.92)) {
                        if let encoded = bookTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://books.apple.com/us/search?term=\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 1)
        )
    }

    private func affiliatePill(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Related content placeholder row
    private func relatedPlaceholderRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Open in external app border button
    private func openExternalButton(url: URL) -> some View {
        Button { UIApplication.shared.open(url) } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14))
                Text(openExternalLabel)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var openExternalLabel: String {
        switch entry {
        case .sermon:           return "Open in YouTube"
        case .podcast, .worship: return "Open in Spotify"
        }
    }

    private var playerHeight: CGFloat {
        switch entry {
        case .sermon:            return 218
        case .podcast, .worship: return 152
        }
    }

    /// Subtle hairline divider
    private var editorialDivider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.45))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    // MARK: - Floating dismiss bar

    private var floatingBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color(.separator).opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 58)
    }
}

// MARK: - MediaPressEffect ButtonStyle

struct MediaPressEffect: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - WKWebView embed

struct MediaEmbedWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(URLRequest(url: url))
    }
}
