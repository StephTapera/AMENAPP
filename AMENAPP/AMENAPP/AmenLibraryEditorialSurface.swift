// AmenLibraryEditorialSurface.swift
// AMENAPP
//
// Liquid Glass editorial cards for 10+ collection types.
// Hero lift on scroll, background tint that responds to the card, no noisy motion.

import SwiftUI

// MARK: - Collection Types

enum AmenEditorialCollectionType: String, CaseIterable, Identifiable {
    case seasonalPick     = "Seasonal Pick"
    case staffPick        = "Staff Pick"
    case sermonCompanion  = "Sermon Companion"
    case newRelease       = "New Release"
    case churchHistory    = "Church History Spotlight"
    case forNewBelievers  = "For New Believers"
    case forLeaders       = "For Leaders"
    case prayerLife       = "Prayer Life"
    case apologetics      = "Defend the Faith"
    case missionFocus     = "Missions & Service"
    case familyFaith      = "Family & Faith"
    case classicRevival   = "Classic Revisited"

    var id: String { rawValue }

    var accentColor: Color {
        switch self {
        case .seasonalPick:    return .orange
        case .staffPick:       return .purple
        case .sermonCompanion: return .blue
        case .newRelease:      return .green
        case .churchHistory:   return .brown
        case .forNewBelievers: return Color(.systemTeal)
        case .forLeaders:      return .indigo
        case .prayerLife:      return .pink
        case .apologetics:     return .red
        case .missionFocus:    return .mint
        case .familyFaith:     return Color(.systemYellow)
        case .classicRevival:  return .gray
        }
    }

    var icon: String {
        switch self {
        case .seasonalPick:    return "leaf"
        case .staffPick:       return "star"
        case .sermonCompanion: return "mic"
        case .newRelease:      return "sparkles"
        case .churchHistory:   return "clock"
        case .forNewBelievers: return "figure.walk"
        case .forLeaders:      return "person.3"
        case .prayerLife:      return "hands.sparkles"
        case .apologetics:     return "shield"
        case .missionFocus:    return "globe"
        case .familyFaith:     return "house"
        case .classicRevival:  return "crown"
        }
    }
}

// MARK: - Editorial Card

struct AmenEditorialCard: View {

    let book: WLBook
    let collectionType: AmenEditorialCollectionType
    let onTap: () -> Void
    let onSave: () -> Void
    var isSaved: Bool = false

    @State private var isLifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Background tint — responds to card's accent color
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(collectionType.accentColor.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(collectionType.accentColor.opacity(0.25), lineWidth: 1)
                    )

                // Cover + metadata
                VStack(alignment: .leading, spacing: 0) {
                    coverImage
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding([.top, .horizontal], 14)

                    VStack(alignment: .leading, spacing: 4) {
                        collectionBadge
                        Text(book.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(book.primaryAuthor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    HStack {
                        Spacer()
                        saveButton
                            .padding(.trailing, 14)
                            .padding(.bottom, 12)
                    }
                }
            }
            .frame(width: 180)
        }
        .buttonStyle(.plain)
        .scaleEffect(isLifted ? 1.04 : 1.0)
        .shadow(color: collectionType.accentColor.opacity(isLifted ? 0.3 : 0.1),
                radius: isLifted ? 14 : 6, y: isLifted ? 8 : 3)
        .onHover { hovering in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isLifted = hovering
            }
        }
        .accessibilityLabel("\(book.title) by \(book.primaryAuthor). \(collectionType.rawValue).")
        .accessibilityAddTraits(.isButton)
    }

    private var coverImage: some View {
        Group {
            if let url = book.thumbnailURL.flatMap({ URL(string: $0) }) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        fallbackCover
                    }
                }
            } else {
                fallbackCover
            }
        }
    }

    private var fallbackCover: some View {
        book.coverColor
            .overlay(
                Text(book.title.prefix(1))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    private var collectionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: collectionType.icon)
                .font(.systemScaled(9, weight: .medium))
            Text(collectionType.rawValue)
                .font(.systemScaled(10, weight: .semibold))
        }
        .foregroundStyle(collectionType.accentColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(collectionType.accentColor.opacity(0.12), in: Capsule())
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(isSaved ? collectionType.accentColor : .secondary)
        }
        .accessibilityLabel(isSaved ? "Remove from library" : "Save to library")
    }
}

// MARK: - Hero Editorial Banner

struct AmenHeroEditorialBanner: View {

    let book: WLBook
    let collectionType: AmenEditorialCollectionType
    let curatorNote: String?
    let onTap: () -> Void

    @State private var scrollOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Hero image
                coverBackground
                    .frame(height: 260)
                    .clipped()

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 260)

                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    collectionTypeBadge
                    Text(book.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(book.primaryAuthor)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    if let note = curatorNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(book.title) — \(collectionType.rawValue) hero feature")
    }

    private var coverBackground: some View {
        Group {
            if let url = book.highResThumbnailURL.flatMap(URL.init) ?? book.thumbnailURL.flatMap(URL.init) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        book.coverColor
                    }
                }
            } else {
                book.coverColor
            }
        }
    }

    private var collectionTypeBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: collectionType.icon)
                .font(.systemScaled(11, weight: .semibold))
            Text(collectionType.rawValue.uppercased())
                .font(.systemScaled(10, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Editorial Shelf Row

struct AmenEditorialShelfRow: View {

    let collectionType: AmenEditorialCollectionType
    let books: [WLBook]
    let savedBookIds: Set<String>
    let onBookTap: (WLBook) -> Void
    let onSaveToggle: (WLBook) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: collectionType.icon)
                    .foregroundStyle(collectionType.accentColor)
                Text(collectionType.rawValue)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(books) { book in
                        AmenEditorialCard(
                            book: book,
                            collectionType: collectionType,
                            onTap: { onBookTap(book) },
                            onSave: { onSaveToggle(book) },
                            isSaved: savedBookIds.contains(book.id)
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }
}
