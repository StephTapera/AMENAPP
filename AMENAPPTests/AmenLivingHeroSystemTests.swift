import Foundation
import CoreFoundation
import Testing
@testable import AMENAPP

@MainActor
@Suite("Amen Living Hero System")
struct AmenLivingHeroSystemTests {
    @Test("Daily digest resolver uses real fallback data")
    func dailyDigestResolverUsesFallbackData() {
        let scene = AmenLivingHeroContentResolver.dailyDigest(nil)

        #expect(scene.surface == .dailyDigest)
        #expect(scene.title == AmenDailyDigest.fallback().title)
        #expect(scene.symbols.isEmpty == false)
    }

    @Test("Daily verse resolver preserves scripture reference")
    func dailyVerseResolverPreservesReference() {
        let digest = AmenDailyDigest.fallback()
        let scene = AmenLivingHeroContentResolver.dailyVerse(verse: nil, digest: digest)

        #expect(scene.surface == .dailyVerse)
        #expect(scene.title == digest.verseReference)
        #expect(scene.subtitle == digest.verseText)
    }

    @Test("Motion engine disables animation for accessibility and low power")
    func motionEngineDisablesAnimationWhenRequired() {
        #expect(AmenLivingHeroMotionEngine(reduceMotion: true, reduceTransparency: false, lowPowerMode: false, scrollActivity: 0).shouldAnimate == false)
        #expect(AmenLivingHeroMotionEngine(reduceMotion: false, reduceTransparency: true, lowPowerMode: false, scrollActivity: 0).shouldAnimate == false)
        #expect(AmenLivingHeroMotionEngine(reduceMotion: false, reduceTransparency: false, lowPowerMode: true, scrollActivity: 0).shouldAnimate == false)
        #expect(AmenLivingHeroMotionEngine(reduceMotion: false, reduceTransparency: false, lowPowerMode: false, scrollActivity: 0.8).shouldAnimate == false)
        #expect(AmenLivingHeroMotionEngine(reduceMotion: false, reduceTransparency: false, lowPowerMode: false, scrollActivity: 0).shouldAnimate)
    }
}
