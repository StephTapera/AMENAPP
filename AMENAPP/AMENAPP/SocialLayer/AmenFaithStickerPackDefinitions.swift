// AmenFaithStickerPackDefinitions.swift
// AMENAPP — SocialLayer
//
// Defines the bundled AMEN Faith sticker pack.
// All stickers render as SwiftUI views using SF Symbols — no external asset downloads required.
// Pack ID: "amen-faith-v1"
//
// To add new stickers: append to AmenFaithStickerPack.stickers and implement
// the matching @ViewBuilder case in AmenFaithSticker.stickerView.

import SwiftUI

// MARK: - AmenFaithSticker

struct AmenFaithSticker: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let sfSymbol: String
    let tintColor: Color

    /// For SF Symbol stickers, assetId mirrors the sfSymbol name.
    var assetId: String { sfSymbol }

    // MARK: ComposerStickerAttachment factory

    /// Creates the Codable attachment that is stored in a ComposerDraft / sent to Firestore.
    func attachment() -> ComposerStickerAttachment {
        ComposerStickerAttachment(
            id: UUID(),
            stickerId: id,
            url: "",           // rendered locally — no remote URL
            category: "faith",
            packId: "amen-faith-v1"
        )
    }

    // MARK: View rendering

    /// Returns a 72 × 72 pt SwiftUI view for this sticker.
    @ViewBuilder
    var stickerView: some View {
        switch id {
        case "faith.cross":
            CrossStickerView()
        case "faith.dove":
            DoveStickerView()
        case "faith.prayingHands":
            PrayingHandsStickerView()
        case "faith.john316":
            John316BadgeView()
        case "faith.fire":
            FireStickerView()
        case "faith.heart":
            HeartOfWorshipStickerView()
        case "faith.bible":
            BibleStickerView()
        case "faith.church":
            ChurchStickerView()
        default:
            // Fallback: generic SF Symbol rendering
            Image(systemName: sfSymbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(tintColor)
                .frame(width: 72, height: 72)
        }
    }
}

// MARK: - AmenFaithStickerPack

enum AmenFaithStickerPack {
    static let id = "amen-faith-v1"
    static let displayName = "AMEN Faith"

    static let stickers: [AmenFaithSticker] = [
        AmenFaithSticker(
            id: "faith.cross",
            name: "Cross",
            category: "Faith",
            sfSymbol: "cross.fill",
            tintColor: AmenTheme.Colors.amenGold
        ),
        AmenFaithSticker(
            id: "faith.dove",
            name: "Dove",
            category: "Faith",
            sfSymbol: "bird.fill",
            tintColor: Color.white
        ),
        AmenFaithSticker(
            id: "faith.prayingHands",
            name: "Praying Hands",
            category: "Faith",
            sfSymbol: "hands.sparkles.fill",
            tintColor: AmenTheme.Colors.amenPurple
        ),
        AmenFaithSticker(
            id: "faith.john316",
            name: "John 3:16",
            category: "Faith",
            sfSymbol: "quote.bubble.fill",  // decorative; view renders custom badge
            tintColor: AmenTheme.Colors.amenGold
        ),
        AmenFaithSticker(
            id: "faith.fire",
            name: "Fire of the Spirit",
            category: "Faith",
            sfSymbol: "flame.fill",
            tintColor: Color.orange
        ),
        AmenFaithSticker(
            id: "faith.heart",
            name: "Heart of Worship",
            category: "Faith",
            sfSymbol: "heart.fill",
            tintColor: AmenTheme.Colors.amenBlue
        ),
        AmenFaithSticker(
            id: "faith.bible",
            name: "Open Bible",
            category: "Faith",
            sfSymbol: "book.closed.fill",
            tintColor: AmenTheme.Colors.amenGold
        ),
        AmenFaithSticker(
            id: "faith.church",
            name: "Church Building",
            category: "Faith",
            sfSymbol: "building.columns.fill",
            tintColor: Color.gray
        ),
    ]
}

// MARK: - Individual sticker view implementations (72 × 72 pt)

// Cross
private struct CrossStickerView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AmenTheme.Colors.amenGold.opacity(0.15))
            Image(systemName: "cross.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
        }
        .frame(width: 72, height: 72)
    }
}

// Dove
private struct DoveStickerView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AmenTheme.Colors.amenBlue.opacity(0.15))
            Image(systemName: "bird.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: AmenTheme.Colors.amenBlue.opacity(0.35), radius: 6, y: 2)
        }
        .frame(width: 72, height: 72)
    }
}

// Praying Hands
private struct PrayingHandsStickerView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AmenTheme.Colors.amenPurple.opacity(0.15))
            Image(systemName: "hands.sparkles.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenPurple)
        }
        .frame(width: 72, height: 72)
    }
}

// John 3:16 verse badge — custom SwiftUI layout, no external image required
struct John316BadgeView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AmenTheme.Colors.amenGold.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.amenGold, lineWidth: 1.5)
                )
            VStack(spacing: 1) {
                Text("John")
                    .font(AMENFont.semiBold(10))
                    .foregroundStyle(AmenTheme.Colors.amenGoldText)
                Text("3:16")
                    .font(AMENFont.bold(18))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
            }
        }
        .frame(width: 72, height: 72)
        .shadow(color: AmenTheme.Colors.amenGold.opacity(0.25), radius: 6, y: 2)
    }
}

// Fire of the Spirit
private struct FireStickerView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.15))
            Image(systemName: "flame.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange, Color.red.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: 72, height: 72)
    }
}

// Heart of Worship
private struct HeartOfWorshipStickerView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AmenTheme.Colors.amenBlue.opacity(0.15))
            Image(systemName: "heart.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
        .frame(width: 72, height: 72)
    }
}

// Open Bible
private struct BibleStickerView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AmenTheme.Colors.amenGold.opacity(0.15))
            Image(systemName: "book.closed.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
        }
        .frame(width: 72, height: 72)
    }
}

// Church Building
private struct ChurchStickerView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.15))
            Image(systemName: "building.columns.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.gray)
        }
        .frame(width: 72, height: 72)
    }
}
