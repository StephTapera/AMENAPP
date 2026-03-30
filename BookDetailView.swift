// BookDetailView.swift
// AMENAPP
//
// Premium book detail sheet. Shows atmospheric hero cover, metadata, and two
// purchase buttons:
//   "Buy on Amazon"      → Amazon Associates affiliate link
//   "Buy on Apple Books" → Apple Books affiliate link
//
// AMEN does not sell the book. Commerce happens externally.
// Affiliate disclosure is shown beneath the purchase buttons.

import SwiftUI

// MARK: - Design Tokens (mirrors WLToken in WisdomLibraryView)

private enum BDToken {
    static let bg            = Color(.systemBackground)
    static let bgSecondary   = Color(.secondarySystemBackground)
    static let textPrimary   = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary  = Color(.tertiaryLabel)
    static let accent        = Color(red: 0.78, green: 0.50, blue: 0.18)
    static let accentSoft    = Color(red: 0.78, green: 0.50, blue: 0.18).opacity(0.12)
    static let hPad: CGFloat = 20
    static let cornerLg: CGFloat = 16
    static let cornerMd: CGFloat = 12
}

// MARK: - WLBookDetailView

struct WLBookDetailView: View {
    let book: WLBook
    @ObservedObject var vm: BookDiscoveryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showBereanSheet = false
    @State private var savedPulse = false
    @State private var heroLoaded = false
    @State private var scrollOffset: CGFloat = 0

    private var isSaved: Bool { vm.isSaved(book) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                BDToken.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // ── Atmospheric Hero ──────────────────────────────────
                        BDHeroSection(book: book, heroLoaded: $heroLoaded)

                        // ── Content Body ──────────────────────────────────────
                        VStack(alignment: .leading, spacing: 0) {

                            // Title + author + rating
                            BDMetadataSection(book: book)

                            // Spiritual tags
                            if !book.curatedTags.isEmpty {
                                BDTagsRow(tags: book.curatedTags)
                                    .padding(.top, 14)
                                    .padding(.horizontal, BDToken.hPad)
                            }

                            // Why AMEN recommends
                            if let reason = book.recommendationReason {
                                BDRecommendsBanner(reason: reason)
                                    .padding(.top, 20)
                                    .padding(.horizontal, BDToken.hPad)
                            }

                            // Description
                            if let desc = book.shortDescription {
                                BDDescriptionSection(text: desc)
                                    .padding(.top, 20)
                                    .padding(.horizontal, BDToken.hPad)
                            }

                            // Action buttons
                            BDActionButtons(
                                book: book,
                                vm: vm,
                                isSaved: isSaved,
                                savedPulse: $savedPulse,
                                showBerean: $showBereanSheet,
                                reduceMotion: reduceMotion
                            )
                            .padding(.top, 24)
                            .padding(.horizontal, BDToken.hPad)

                            // Affiliate disclosure
                            Text(AffiliateConfig.disclosure)
                                .font(.system(size: 11))
                                .foregroundStyle(BDToken.textTertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, BDToken.hPad)
                                .padding(.top, 10)

                            // Publisher info
                            BDPublisherSection(book: book)

                            Color.clear.frame(height: 48)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BDToken.accent)
                }
            }
        }
        .sheet(isPresented: $showBereanSheet) {
            WLBereanBookPromptView(book: book)
        }
    }
}

// MARK: - Hero Section

private struct BDHeroSection: View {
    let book: WLBook
    @Binding var heroLoaded: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            // Atmospheric background — blurred cover image
            if let urlStr = book.highResThumbnailURL ?? book.thumbnailURL,
               let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 320)
                            .clipped()
                            .blur(radius: 28)
                            .saturation(0.9)
                            .overlay {
                                // Gradient veil
                                LinearGradient(
                                    colors: [
                                        book.coverColor.opacity(colorScheme == .dark ? 0.55 : 0.35),
                                        BDToken.bg.opacity(0.0),
                                        BDToken.bg
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                    } else {
                        // Fallback gradient atmosphere
                        LinearGradient(
                            colors: [book.coverColor.opacity(0.22), BDToken.bg],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 320)
                    }
                }
            } else {
                LinearGradient(
                    colors: [book.coverColor.opacity(0.22), BDToken.bg],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 320)
            }

            // Foreground cover image centered + elevated
            VStack(spacing: 0) {
                if let urlStr = book.thumbnailURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 210)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
                                .onAppear { heroLoaded = true }
                        } else {
                            WLBookCoverPlaceholder(book: book)
                                .frame(width: 140, height: 210)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 7)
                        }
                    }
                } else {
                    WLBookCoverPlaceholder(book: book)
                        .frame(width: 140, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 7)
                }
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipped()
    }
}

// MARK: - Metadata Section

private struct BDMetadataSection: View {
    let book: WLBook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(BDToken.textPrimary)

            if let subtitle = book.subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(BDToken.textSecondary)
            }

            Text(book.authorDisplayString)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BDToken.accent)
                .padding(.top, 2)

            // Star rating row
            if let rating = book.averageRating {
                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        Image(systemName: Double(i) < rating ? "star.fill" : (Double(i) < rating + 0.5 ? "star.leadinghalf.filled" : "star"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.2))
                    }
                    if let count = book.ratingsCount {
                        Text("(\(count.formatted()))")
                            .font(.system(size: 12))
                            .foregroundStyle(BDToken.textTertiary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, BDToken.hPad)
        .padding(.top, 20)
    }
}

// MARK: - Tags Row

private struct BDTagsRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(tags.prefix(6), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BDToken.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(BDToken.accentSoft, in: Capsule())
                }
            }
        }
        .accessibilityLabel("Topics: \(tags.prefix(6).joined(separator: ", "))")
    }
}

// MARK: - AMEN Recommends Banner

private struct BDRecommendsBanner: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hands.sparkles.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(BDToken.accent)
                Text("WHY AMEN RECOMMENDS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BDToken.accent)
                    .tracking(0.8)
            }

            Text(reason)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(BDToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: BDToken.cornerMd)
                .fill(BDToken.accentSoft)
                .overlay {
                    RoundedRectangle(cornerRadius: BDToken.cornerMd)
                        .strokeBorder(BDToken.accent.opacity(0.22), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AMEN recommends this because: \(reason)")
    }
}

// MARK: - Description Section

private struct BDDescriptionSection: View {
    let text: String
    @State private var expanded = false

    private let previewLineLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this book")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BDToken.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(BDToken.textPrimary)
                .lineLimit(expanded ? nil : previewLineLimit)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    expanded.toggle()
                }
            } label: {
                Text(expanded ? "Show less" : "Read more")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BDToken.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Action Buttons

private struct BDActionButtons: View {
    let book: WLBook
    @ObservedObject var vm: BookDiscoveryViewModel
    let isSaved: Bool
    @Binding var savedPulse: Bool
    @Binding var showBerean: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 10) {
            // Buy on Amazon — amber
            BDPrimaryButton(
                label: "Buy on Amazon",
                systemImage: "cart.fill",
                background: Color(red: 1.0, green: 0.60, blue: 0.0)
            ) {
                AffiliateLinkBuilder.openAmazon(for: book)
            }

            // Buy on Apple Books — blue (only when URL resolves)
            if AffiliateLinkBuilder.appleBooksURL(for: book) != nil {
                BDPrimaryButton(
                    label: "Buy on Apple Books",
                    systemImage: "books.vertical.fill",
                    background: Color(red: 0.0, green: 0.48, blue: 1.0)
                ) {
                    AffiliateLinkBuilder.openAppleBooks(for: book)
                }
            }

            // Save + Ask Berean row
            HStack(spacing: 10) {
                Button {
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            vm.toggleSave(book: book)
                            savedPulse = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            savedPulse = false
                        }
                    } else {
                        vm.toggleSave(book: book)
                    }
                } label: {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSaved ? .white : BDToken.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            isSaved ? BDToken.accent : BDToken.bgSecondary,
                            in: RoundedRectangle(cornerRadius: BDToken.cornerMd)
                        )
                }
                .buttonStyle(.plain)
                .scaleEffect(savedPulse && !reduceMotion ? 1.04 : 1.0)
                .accessibilityLabel(isSaved ? "Remove from saved books" : "Save this book")

                Button { showBerean = true } label: {
                    Label("Ask Berean", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BDToken.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(BDToken.bgSecondary, in: RoundedRectangle(cornerRadius: BDToken.cornerMd))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask Berean AI about this book")
            }
        }
    }
}

private struct BDPrimaryButton: View {
    let label: String
    let systemImage: String
    let background: Color
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(background, in: RoundedRectangle(cornerRadius: BDToken.cornerLg))
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { withAnimation(.easeOut(duration: 0.1)) { isPressed = true } }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isPressed = false }
                }
        )
    }
}

// MARK: - Publisher Section

private struct BDPublisherSection: View {
    let book: WLBook

    private var hasData: Bool {
        book.publisher != nil || book.publishedDate != nil || book.pageCount != nil
    }

    var body: some View {
        if hasData {
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Color(.separator).opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, BDToken.hPad)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Publication Details")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BDToken.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .padding(.bottom, 2)

                    if let pub = book.publisher {
                        BDInfoRow(label: "Publisher", value: pub)
                    }
                    if let date = book.publishedDate {
                        BDInfoRow(label: "Published", value: date)
                    }
                    if let pages = book.pageCount {
                        BDInfoRow(label: "Pages", value: "\(pages)")
                    }
                    if let isbn = book.isbn13 ?? book.isbn10 {
                        BDInfoRow(label: "ISBN", value: isbn)
                    }
                }
                .padding(.horizontal, BDToken.hPad)
                .padding(.top, 14)
            }
        }
    }
}

private struct BDInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BDToken.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(BDToken.textPrimary)
        }
    }
}

// MARK: - Berean AI Prompt Sheet

struct WLBereanBookPromptView: View {
    let book: WLBook
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Book pill header
                    HStack(spacing: 12) {
                        if let urlStr = book.thumbnailURL, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 44, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    WLBookCoverPlaceholder(book: book)
                                        .frame(width: 44, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        } else {
                            WLBookCoverPlaceholder(book: book)
                                .frame(width: 44, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(BDToken.textPrimary)
                                .lineLimit(2)
                            Text(book.authorDisplayString)
                                .font(.system(size: 12))
                                .foregroundStyle(BDToken.textSecondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BDToken.bgSecondary, in: RoundedRectangle(cornerRadius: BDToken.cornerMd))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ask Berean")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(BDToken.textPrimary)
                        Text("Explore this book's themes, theological depth, and scripture connections — grounded in the Word.")
                            .font(.system(size: 14))
                            .foregroundStyle(BDToken.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Suggestion chips
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach([
                            ("book.closed.fill", "What are the key theological themes?"),
                            ("text.book.closed.fill", "What scriptures does this connect to?"),
                            ("checkmark.seal.fill", "Is this book theologically sound?"),
                            ("calendar", "Create a reading plan for this book"),
                            ("person.2.fill", "Suggest group discussion questions")
                        ], id: \.1) { icon, suggestion in
                            Button {
                                // Production: route to BereanAI with prompt + book context
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: icon)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.indigo)
                                        .frame(width: 20)
                                    Text(suggestion)
                                        .font(.system(size: 14))
                                        .foregroundStyle(BDToken.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(BDToken.textTertiary)
                                }
                                .padding(14)
                                .background(BDToken.bgSecondary, in: RoundedRectangle(cornerRadius: BDToken.cornerMd))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Premium note
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(.indigo)
                        Text("AI book summaries, scripture cross-references, and discussion prompts are AMEN Premium features.")
                            .font(.system(size: 12))
                            .foregroundStyle(BDToken.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: BDToken.cornerMd))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Color.clear.frame(height: 36)
                }
            }
            .navigationTitle("Ask Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BDToken.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

// MARK: - Preview

#Preview {
    let book = WLBook(
        id: "preview-001",
        title: "The Cost of Discipleship",
        subtitle: "A Bonhoeffer Classic",
        authors: ["Dietrich Bonhoeffer"],
        description: "In this landmark work, Bonhoeffer calls out the comfortable Christianity of his day and challenges readers to a radical commitment to Christ — a discipleship that costs everything.",
        categories: ["Theology", "Discipleship"],
        isbn13: nil, isbn10: nil,
        publishedDate: "1937",
        publisher: "SCM Press",
        pageCount: 320,
        language: "en",
        thumbnailURL: nil,
        highResThumbnailURL: nil,
        previewLink: nil,
        averageRating: 4.8,
        ratingsCount: 1240,
        amazonAffiliateURL: nil,
        appleBooksURL: nil,
        isFeatured: true,
        recommendationReason: "A prophetic challenge to cheap grace — essential reading for every serious follower of Christ.",
        curatedTags: ["Discipleship", "Grace", "Theology", "Classic"]
    )
    WLBookDetailView(book: book, vm: BookDiscoveryViewModel())
}
