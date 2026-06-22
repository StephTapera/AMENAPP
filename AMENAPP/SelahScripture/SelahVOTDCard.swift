//
//  SelahVOTDCard.swift
//  AMENAPP
//
//  Verse of the Day card for the Selah formation surface.
//  Design tokens from selah.contracts.ts §1–§9.
//
//  Formation-first: no like count, no comment count, no share count,
//  no streak counter. Primary action is reading the full chapter.
//  Long-press verse text exposes a "Check against Scripture" discernment
//  entry point (wired to DiscernmentEntrySheet once Agent C files land).
//

import SwiftUI

// MARK: - SelahVOTDCard

struct SelahVOTDCard: View {

    // MARK: - Inputs

    /// Scripture reference, e.g. "John 3:16"
    let verseRef: String
    /// Full verse text displayed on the card.
    let verseText: String
    /// Optional remote hero photo. When nil a scripture-themed fallback fills the hero.
    let heroImageURL: URL?
    /// Called when the user taps "Read Chapter". Receives the verseRef string.
    let onReadChapter: (String) -> Void

    // MARK: - State

    /// Controls the discernment context-menu sheet.
    @State private var showDiscernmentSheet = false

    // MARK: - Constants

    private let heroHeight: CGFloat = 200
    private let cardCornerRadius: CGFloat = 28

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroArea
            bottomArea
        }
        // §2 Floating adaptive card
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showDiscernmentSheet) {
            DiscernmentEntrySheet(inputText: verseText, sourceType: "verse", sourceRef: verseRef)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Hero Area

    @ViewBuilder
    private var heroArea: some View {
        ZStack(alignment: .bottom) {
            // Background: photo or neutral gradient placeholder
            heroBackground
                .frame(height: heroHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: cardCornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: cardCornerRadius,
                        style: .continuous
                    )
                )

            // Bottom scrim — §3: covers bottom ~45% of the hero
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight * 0.45)
            .allowsHitTesting(false)

            // Overlay content on scrim
            HStack(alignment: .bottom, spacing: 12) {
                // Bottom-left: verse ref + preview text
                verseScrimOverlay
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Bottom-right: "Read Chapter" dark glass pill
                readChapterPill
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let url = heroImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    scriptureFallbackHero
                case .empty:
                    scriptureFallbackHero
                @unknown default:
                    scriptureFallbackHero
                }
            }
        } else {
            scriptureFallbackHero
        }
    }

    private var scriptureFallbackHero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.97, blue: 1.00),
                    Color(red: 0.76, green: 0.84, blue: 0.92),
                    Color(red: 0.42, green: 0.48, blue: 0.56)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.72), Color.clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 180
            )

            VStack(spacing: 10) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)

                Text("Verse of the Day")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.74))
            }
            .offset(y: -18)
        }
    }

    // MARK: - Scrim Overlays

    private var verseScrimOverlay: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verseRef)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)

            let preview = verseText.count > 80
                ? String(verseText.prefix(80)) + "…"
                : verseText
            Text(preview)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Read Chapter Pill (§3 dark glass pill)

    private var readChapterPill: some View {
        Button {
            onReadChapter(verseRef)
        } label: {
            Text("Read Chapter")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    ZStack {
                        Capsule()
                            .fill(.black.opacity(0.40))
                        Capsule()
                            .fill(Material.regular)
                            .opacity(0.6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read \(verseRef) chapter")
    }

    // MARK: - Bottom Area

    private var bottomArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Full verse text — not truncated
            Text(verseText)
                .font(.body)
                .foregroundStyle(Color(.label))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                // Long-press: "Check against Scripture" discernment entry
                .contextMenu {
                    Button {
                        showDiscernmentSheet = true
                    } label: {
                        Label("Check against Scripture", systemImage: "checkmark.seal")
                    }
                }

            // "Verse of the Day" label — §1 secondary text
            Text("Verse of the Day")
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .padding(16)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // With hero image (placeholder will show since no live URL in preview)
            SelahVOTDCard(
                verseRef: "John 3:16",
                verseText: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
                heroImageURL: nil,
                onReadChapter: { ref in
                    print("Navigate to chapter for \(ref)")
                }
            )

            // Without hero image
            SelahVOTDCard(
                verseRef: "Philippians 4:13",
                verseText: "I can do all things through Christ which strengtheneth me.",
                heroImageURL: nil,
                onReadChapter: { _ in }
            )
        }
        .padding(20)
    }
    .background(Color(.systemGroupedBackground))
}
