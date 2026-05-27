import SwiftUI
import UIKit

// MARK: - PUBLIC INTERFACE

/// Converts a `ShareCard` SwiftUI view into a `UIImage` with exact spec dimensions.
/// Must be called from the `@MainActor` — `ImageRenderer` is not Sendable.
enum ShareCardRenderer {

    /// Renders the share card for the given post and size.
    /// - Parameters:
    ///   - authorAvatar: Pre-resolved avatar image. Pass `nil` to use initials fallback.
    ///     Do NOT use `AsyncImage` — it doesn't render inside `ImageRenderer`.
    /// - Returns: A `UIImage` exactly `size.pixelSize` in points at 1× scale (= exact pixels).
    @MainActor
    static func renderImage(
        post: Post,
        size: ShareCardSize,
        pullQuote: String? = nil,
        verseRef: String? = nil,
        authorAvatar: UIImage? = nil
    ) -> UIImage? {
        let card = ShareCard(
            post: post,
            size: size,
            pullQuote: pullQuote,
            verseRef: verseRef,
            authorAvatar: authorAvatar
        )

        let renderer = ImageRenderer(content: card)
        // scale = 1.0 so rendered pixels == view points == spec dimensions (1080×1920, 1080×1080).
        // IG and FB re-scale on ingest; we guarantee the spec output size.
        renderer.scale = 1.0

        guard let image = renderer.uiImage else { return nil }
        return image
    }
}
