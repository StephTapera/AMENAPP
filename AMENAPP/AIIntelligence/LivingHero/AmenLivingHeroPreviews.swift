import SwiftUI

#Preview("Living Hero - Daily Verse") {
    ScrollView {
        VStack(spacing: 18) {
            AmenLivingHeroCard(
                scene: AmenLivingHeroScene(
                    id: "preview-daily-verse",
                    surface: .dailyVerse,
                    eyebrow: "Scripture Focus",
                    title: "Psalm 23:1",
                    subtitle: "The Lord is my shepherd; I shall not want.",
                    detail: "A calm reflection surface that keeps the verse readable while ambient layers stay decorative.",
                    primaryActionTitle: "Reflect",
                    secondaryActionTitle: "Classic",
                    symbols: ["book.closed", "sparkles", "hands.sparkles", "sun.max"],
                    theme: .scripture
                ),
                motion: AmenLivingHeroMotionEngine(reduceMotion: true, reduceTransparency: false, lowPowerMode: false, scrollActivity: 0),
                floated: false,
                highContrast: false,
                dynamicTypeSize: .large,
                onPrimaryAction: nil,
                onSecondaryAction: nil
            )

            AmenLivingHeroReduceMotionFallback(
                scene: AmenLivingHeroScene(
                    id: "preview-fallback",
                    surface: .dailyDigest,
                    eyebrow: "Good morning",
                    title: "Today's reflection",
                    subtitle: "Start today grounded in Scripture, prayer, and community rhythm.",
                    detail: "Static fallback for Reduce Motion, Reduce Transparency, and Low Power Mode.",
                    primaryActionTitle: "Start Selah",
                    symbols: ["sun.max", "book.closed", "calendar"],
                    theme: .reflection
                )
            )
        }
        .padding(20)
    }
    .background(Color.white)
}

#Preview("Living Hero - Accessibility Size") {
    AmenLivingHeroCard(
        scene: AmenLivingHeroScene(
            id: "preview-accessibility",
            surface: .discover,
            eyebrow: "Amen Discover",
            title: "A curated path for today",
            subtitle: "Explore churches, teachings, Scripture, and community moments with readable text at larger sizes.",
            detail: "This detail intentionally drops at accessibility sizes.",
            primaryActionTitle: "Explore",
            secondaryActionTitle: "Why this",
            symbols: ["safari", "building.2", "book.closed", "person.2"],
            theme: .discovery
        ),
        motion: AmenLivingHeroMotionEngine(reduceMotion: true, reduceTransparency: false, lowPowerMode: false, scrollActivity: 0),
        floated: false,
        highContrast: true,
        dynamicTypeSize: .accessibility3,
        onPrimaryAction: nil,
        onSecondaryAction: nil
    )
    .padding(20)
    .background(Color.white)
}
