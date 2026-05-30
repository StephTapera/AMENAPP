// CommunityNoteCardView.swift
// AMENAPP — Reusable community note card
//
// Handles both CommunityNote (full) and CommunityNotesSearchResult (lightweight)
// via a NoteCardDisplayable protocol — no duplication.
// Glass background via AMENGlassCard; faith-native scripture chips via ChurchBadgeChip.
// Press animation via AmenPressStyle (.amenPress) from Motion.swift.

import SwiftUI

// MARK: - NoteCardDisplayable Protocol

/// Unifies CommunityNote and CommunityNotesSearchResult for card rendering.
protocol NoteCardDisplayable: Identifiable {
    var id: String { get }
    var authorName: String { get }
    var authorInitial: String { get }
    var authorSwiftUIColor: Color { get }
    var title: String { get }
    var excerpt: String { get }
    var category: NoteCategory { get }
    var scriptureRefStrings: [String] { get }
    var likeCount: Int { get }
    var commentCount: Int { get }
}

// MARK: - CommunityNote conformance

extension CommunityNote: NoteCardDisplayable {}

// MARK: - CommunityNotesSearchResult conformance

extension CommunityNotesSearchResult: NoteCardDisplayable {}

// MARK: - CommunityNoteCardView

/// Generic card for feed lists and search results.
/// Initialise with either a CommunityNote or a CommunityNotesSearchResult.
@available(iOS 26.0, *)
struct CommunityNoteCardView<Note: NoteCardDisplayable>: View {

    let note: Note

    var body: some View {
        AMENGlassCard(
            width: UIScreen.main.bounds.width - 40,
            height: cardHeight,
            tintColor: note.category.tint
        ) {
            HStack(alignment: .top, spacing: 12) {
                authorAvatar
                contentColumn
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Author Avatar

    private var authorAvatar: some View {
        Text(note.authorInitial)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(note.authorSwiftUIColor))
            .accessibilityHidden(true)
    }

    // MARK: - Content Column

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Author name + timestamp row
            HStack {
                Text(note.authorName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer()
                ChurchBadgeChip(badge: ChurchBadgeChip.Badge(
                    icon: note.category.icon,
                    label: note.category.displayName,
                    tint: note.category.tint
                ))
            }

            // Title
            Text(note.title)
                .font(.subheadline.bold())
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)

            // Excerpt
            Text(note.excerpt)
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(2)

            // Scripture ref chips (if any)
            if !note.scriptureRefStrings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(note.scriptureRefStrings.prefix(3), id: \.self) { ref in
                            ChurchBadgeChip(badge: ChurchBadgeChip.Badge(
                                icon: "book.closed.fill",
                                label: ref,
                                tint: AmenTheme.Colors.amenGold
                            ))
                        }
                    }
                }
                .accessibilityHidden(true)
            }

            // Footer: like count + comment count
            HStack(spacing: 14) {
                Label("\(note.likeCount)", systemImage: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(AmenTheme.Colors.amenGold)

                Label("\(note.commentCount)", systemImage: "bubble.fill")
                    .font(.caption2)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                Spacer()
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Adaptive height

    private var cardHeight: CGFloat {
        note.scriptureRefStrings.isEmpty ? 120 : 148
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts = ["\(note.title), by \(note.authorName)", note.category.displayName]
        if !note.scriptureRefStrings.isEmpty {
            parts.append("Scriptures: \(note.scriptureRefStrings.prefix(3).joined(separator: ", "))")
        }
        parts.append("\(note.likeCount) likes, \(note.commentCount) comments")
        return parts.joined(separator: ". ")
    }
}

// MARK: - Convenience initialisers for type inference

@available(iOS 26.0, *)
extension CommunityNoteCardView where Note == CommunityNote {
    init(note: CommunityNote) {
        self.note = note
    }
}

@available(iOS 26.0, *)
extension CommunityNoteCardView where Note == CommunityNotesSearchResult {
    init(searchResult: CommunityNotesSearchResult) {
        self.note = searchResult
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 26.0, *)
#Preview("CommunityNoteCardView — note") {
    let sample = CommunityNote(
        id: "p1",
        authorId: "u1",
        authorName: "Marcus Webb",
        authorHandle: "marcuswebb",
        authorInitial: "M",
        authorColor: "#7243CC",
        title: "What Romans 8 taught me this week",
        excerpt: "Paul's encouragement that nothing can separate us from the love of God hits differently when you're walking through a difficult season.",
        body: "",
        category: .study,
        tags: ["romans", "faith"],
        scriptureRefStrings: ["Romans 8:28", "Romans 8:38-39"],
        scriptureKeys: ["ROM.8.28", "ROM.8.38"],
        visibility: .public_,
        likeCount: 42,
        commentCount: 7,
        saveCount: 5,
        createdAt: Date(),
        updatedAt: Date(),
        publishedAt: Date()
    )
    return CommunityNoteCardView(note: sample)
        .padding()
        .background(AmenTheme.Colors.backgroundPrimary)
}
#endif
