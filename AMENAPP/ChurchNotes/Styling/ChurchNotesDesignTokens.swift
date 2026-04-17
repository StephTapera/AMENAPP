import SwiftUI

enum ChurchNotesDesignTokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let chip: CGFloat = 999
        static let card: CGFloat = 18
        static let editor: CGFloat = 22
        static let block: CGFloat = 14
    }

    enum Shadow {
        static let card = (color: Color.black.opacity(0.04), radius: CGFloat(10), y: CGFloat(3))
        static let capsule = (color: Color.black.opacity(0.08), radius: CGFloat(12), y: CGFloat(4))
    }

    enum Colors {
        static let cardBackground = Color(.systemBackground).opacity(0.78)
        static let neutralBorder = Color.primary.opacity(0.08)
        static let neutralButton = Color.white.opacity(0.72)
        static let darkText = Color.primary.opacity(0.86)
        static let quoteBlock = CNToken.BlockTint.quote
        static let takeawayBlock = CNToken.BlockTint.takeaway
        static let prayerBlock = CNToken.BlockTint.prayer
        static let actionBlock = CNToken.BlockTint.action
        static let reflectionBlock = CNToken.BlockTint.reflection
        static let scriptureBlock = CNToken.BlockTint.scripture
    }
}
