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
        static let card: CGFloat = 16
        static let editor: CGFloat = 20
        static let block: CGFloat = 12
    }

    enum Shadow {
        static let card = (color: Color.black.opacity(0.04), radius: CGFloat(10), y: CGFloat(3))
        static let capsule = (color: Color.black.opacity(0.08), radius: CGFloat(12), y: CGFloat(4))
    }

    enum Colors {
        static let cardBackground = Color(.systemBackground).opacity(0.70)
        static let neutralBorder = Color.primary.opacity(0.07)
        static let neutralButton = Color(.secondarySystemGroupedBackground).opacity(0.76)
        static let darkText = Color.primary.opacity(0.86)
        static let personalTint = Color.accentColor
        static let calmBlue = Color(red: 0.20, green: 0.42, blue: 0.72)
        static let olive = Color(red: 0.36, green: 0.48, blue: 0.30)
        static let gold = Color(red: 0.72, green: 0.52, blue: 0.18)
        static let rose = Color(red: 0.70, green: 0.34, blue: 0.42)
        static let slate = Color(red: 0.34, green: 0.39, blue: 0.46)
        static let quoteBlock = CNToken.BlockTint.quote
        static let takeawayBlock = CNToken.BlockTint.takeaway
        static let prayerBlock = CNToken.BlockTint.prayer
        static let actionBlock = CNToken.BlockTint.action
        static let reflectionBlock = CNToken.BlockTint.reflection
        static let scriptureBlock = CNToken.BlockTint.scripture
    }
}
