import SwiftUI
import FirebaseFirestore

// MARK: - Firestore-backed models

/// A curated featured card in the `featured` Firestore collection.
/// GUARDIAN moderates these — `moderationCleared` is set only by Cloud Functions.
struct FeaturedEntry: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String = ""
    var subtitle: String?
    var accentHex: String?
    var imageURL: String?
    var badgeLabel: String?
    var rating: String?
    var contentRef: ContentRef?
    var order: Int = 0
    var active: Bool = true
    var moderationCleared: Bool = true

    var displayID: String { id ?? UUID().uuidString }

    func asFeaturedItem() -> FeaturedItem {
        FeaturedItem(
            title: title,
            badge: badgeLabel,
            metadata: subtitle ?? "",
            rating: rating,
            accent: accentHex.flatMap(Color.init(hex:)) ?? .amenPurple,
            imageURL: imageURL.flatMap(URL.init(string:))
        )
    }
}

/// An item in a user's `users/{uid}/continue` subcollection, written by
/// `markEngaged` when the user opens or plays content.
struct ContinueEntry: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String = ""
    var accentHex: String?
    var imageURL: String?
    var contentRef: ContentRef?
    @ServerTimestamp var lastEngagedAt: Date?

    var displayID: String { id ?? UUID().uuidString }

    func asCarouselItem() -> CarouselItem {
        CarouselItem(
            title: title,
            accent: accentHex.flatMap(Color.init(hex:)) ?? .amenBlue,
            imageURL: imageURL.flatMap(URL.init(string:))
        )
    }
}

struct ContentRef: Codable {
    enum Kind: String, Codable {
        case post, ariseVideo, outpourClip, study, verse, churchNote
    }
    var kind: Kind
    var refID: String
}

// MARK: - Hex color initializer

extension Color {
    /// Initializes a Color from a 6-character hex string, with or without `#`.
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue: Double(rgb & 0xFF)           / 255
        )
    }
}
