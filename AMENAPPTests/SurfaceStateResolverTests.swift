//
//  SurfaceStateResolverTests.swift
//  AMENAPPTests
//
//  Exhaustive unit tests for SurfaceStateResolver.
//
//  Coverage matrix:
//    A11y overrides × every role
//    Full-screen video × every role
//    Keyboard transforms × bottomNav, composerTray
//    Scroll × role × media type
//    Busy background triggers frostedStrong
//    a11y always overrides aesthetics (priority 0 invariant)
//

import Testing
import Foundation
@testable import AMENAPP

// MARK: - Helpers

private func ctx(
    brightness: Brightness = .light,
    media: MediaKind = .none,
    scroll: ScrollState = .atTop,
    keyboard: Bool = false,
    contrastRisk: Bool = false,
    reduceTransparency: Bool = false,
    increaseContrast: Bool = false
) -> SurfaceContext {
    SurfaceContext(
        backgroundBrightness: brightness,
        dominantColor: nil,
        mediaType: media,
        scrollState: scroll,
        keyboardVisible: keyboard,
        activeInput: false,
        contrastRisk: contrastRisk,
        a11y: A11ySnapshot(
            reduceTransparency: reduceTransparency,
            reduceMotion: false,
            increaseContrast: increaseContrast,
            dynamicTypeSize: .large
        )
    )
}

private func resolve(_ context: SurfaceContext, _ role: SurfaceRole) -> GlassSurfaceState {
    SurfaceStateResolver.resolve(context: context, role: role)
}

// MARK: - A11y override tests (Priority 0 — always win)

@Suite("SurfaceStateResolver — A11y Overrides")
struct A11yOverrideTests {

    @Test("Increase Contrast forces solidLight on topBar regardless of media")
    func increaseContrastTopBar() {
        let result = resolve(ctx(media: .video, increaseContrast: true), .topBar)
        #expect(result == .solidLight)
    }

    @Test("Increase Contrast forces solidLight on bottomNav regardless of scroll")
    func increaseContrastBottomNav() {
        let result = resolve(ctx(scroll: .deep, increaseContrast: true), .bottomNav)
        #expect(result == .solidLight)
    }

    @Test("Reduce Transparency forces solidLight on composerTray")
    func reduceTransparencyComposerTray() {
        let result = resolve(ctx(reduceTransparency: true), .composerTray)
        #expect(result == .solidLight)
    }

    @Test("Reduce Transparency forces solidLight on card")
    func reduceTransparencyCard() {
        let result = resolve(ctx(keyboard: true, reduceTransparency: true), .card)
        #expect(result == .solidLight)
    }

    @Test("contrastRisk forces solidLight on statusZone")
    func contrastRiskStatusZone() {
        let result = resolve(ctx(contrastRisk: true), .statusZone)
        #expect(result == .solidLight)
    }

    @Test("A11y overrides busy background — solidLight, not frostedStrong")
    func a11yOverridesBusy() {
        let result = resolve(ctx(brightness: .busy, scroll: .scrolling(direction: .down), increaseContrast: true), .topBar)
        #expect(result == .solidLight)
    }

    @Test("All roles return solidLight when reduceTransparency is set")
    func allRolesReduceTransparency() {
        let allRoles: [SurfaceRole] = [.statusZone, .topBar, .bottomNav, .composerTray, .actionStrip, .card]
        for role in allRoles {
            let result = resolve(ctx(reduceTransparency: true), role)
            #expect(result == .solidLight, "Expected .solidLight for \(role)")
        }
    }

    @Test("All roles return solidLight when increaseContrast is set")
    func allRolesIncreaseContrast() {
        let allRoles: [SurfaceRole] = [.statusZone, .topBar, .bottomNav, .composerTray, .actionStrip, .card]
        for role in allRoles {
            let result = resolve(ctx(increaseContrast: true), role)
            #expect(result == .solidLight, "Expected .solidLight for \(role)")
        }
    }
}

// MARK: - Video rules (Priority 1)

@Suite("SurfaceStateResolver — Video Rules")
struct VideoRuleTests {

    @Test("Video + bottomNav → hidden")
    func videoHidesBottomNav() {
        #expect(resolve(ctx(media: .video), .bottomNav) == .hidden)
    }

    @Test("Video + topBar → transparent")
    func videoTransparentTopBar() {
        #expect(resolve(ctx(media: .video), .topBar) == .transparent)
    }

    @Test("Video + statusZone → transparent")
    func videoTransparentStatusZone() {
        #expect(resolve(ctx(media: .video), .statusZone) == .transparent)
    }

    @Test("Video + composerTray → falls through to scroll rules (frosted at top)")
    func videoComposerTrayFallsThrough() {
        let result = resolve(ctx(media: .video, scroll: .atTop), .composerTray)
        #expect(result == .frosted)
    }

    @Test("Video + card → falls through to scroll rules (frosted at top)")
    func videoCardFallsThrough() {
        let result = resolve(ctx(media: .video, scroll: .atTop), .card)
        #expect(result == .frosted)
    }

    @Test("Video + actionStrip → falls through (frosted at top)")
    func videoActionStripFallsThrough() {
        let result = resolve(ctx(media: .video, scroll: .atTop), .actionStrip)
        #expect(result == .frosted)
    }
}

// MARK: - Keyboard transforms (Priority 2)

@Suite("SurfaceStateResolver — Keyboard Transforms")
struct KeyboardTransformTests {

    @Test("Keyboard visible + bottomNav → frosted (relocates above keyboard)")
    func keyboardBottomNav() {
        #expect(resolve(ctx(keyboard: true), .bottomNav) == .frosted)
    }

    @Test("Keyboard visible + composerTray → frosted")
    func keyboardComposerTray() {
        #expect(resolve(ctx(keyboard: true), .composerTray) == .frosted)
    }

    @Test("Keyboard visible + topBar → falls through to scroll rules")
    func keyboardTopBarFallsThrough() {
        let result = resolve(ctx(keyboard: true, scroll: .atTop, media: .none), .topBar)
        #expect(result == .solidLight)
    }

    @Test("Keyboard visible + card → falls through to scroll rules (frosted)")
    func keyboardCardFallsThrough() {
        #expect(resolve(ctx(keyboard: true), .card) == .frosted)
    }
}

// MARK: - Scroll state × role matrix (Priority 3)

@Suite("SurfaceStateResolver — atTop")
struct AtTopScrollTests {

    @Test("atTop + topBar + no media → solidLight (clean white at rest)")
    func atTopTopBarNoMedia() {
        #expect(resolve(ctx(media: .none, scroll: .atTop), .topBar) == .solidLight)
    }

    @Test("atTop + topBar + image media → transparent (content owns top edge)")
    func atTopTopBarImage() {
        #expect(resolve(ctx(media: .image, scroll: .atTop), .topBar) == .transparent)
    }

    @Test("atTop + topBar + heroBanner → transparent")
    func atTopTopBarHero() {
        #expect(resolve(ctx(media: .heroBanner, scroll: .atTop), .topBar) == .transparent)
    }

    @Test("atTop + statusZone + no media → frosted")
    func atTopStatusZoneNoMedia() {
        #expect(resolve(ctx(scroll: .atTop), .statusZone) == .frosted)
    }

    @Test("atTop + statusZone + image → transparent")
    func atTopStatusZoneImage() {
        #expect(resolve(ctx(media: .image, scroll: .atTop), .statusZone) == .transparent)
    }

    @Test("atTop + bottomNav → frosted")
    func atTopBottomNav() {
        #expect(resolve(ctx(scroll: .atTop), .bottomNav) == .frosted)
    }

    @Test("atTop + composerTray → frosted")
    func atTopComposerTray() {
        #expect(resolve(ctx(scroll: .atTop), .composerTray) == .frosted)
    }

    @Test("atTop + actionStrip → frosted")
    func atTopActionStrip() {
        #expect(resolve(ctx(scroll: .atTop), .actionStrip) == .frosted)
    }

    @Test("atTop + card → frosted")
    func atTopCard() {
        #expect(resolve(ctx(scroll: .atTop), .card) == .frosted)
    }
}

@Suite("SurfaceStateResolver — scrolling")
struct ScrollingTests {

    @Test("scrolling + topBar + non-busy → frosted")
    func scrollingTopBarNonBusy() {
        #expect(resolve(ctx(scroll: .scrolling(direction: .down)), .topBar) == .frosted)
    }

    @Test("scrolling + topBar + busy brightness → frostedStrong")
    func scrollingTopBarBusy() {
        #expect(resolve(ctx(brightness: .busy, scroll: .scrolling(direction: .down)), .topBar) == .frostedStrong)
    }

    @Test("scrolling up + topBar + busy → frostedStrong (direction irrelevant)")
    func scrollingUpTopBarBusy() {
        #expect(resolve(ctx(brightness: .busy, scroll: .scrolling(direction: .up)), .topBar) == .frostedStrong)
    }

    @Test("scrolling + statusZone + busy → frostedStrong")
    func scrollingStatusZoneBusy() {
        #expect(resolve(ctx(brightness: .busy, scroll: .scrolling(direction: .down)), .statusZone) == .frostedStrong)
    }

    @Test("scrolling + bottomNav → frosted")
    func scrollingBottomNav() {
        #expect(resolve(ctx(scroll: .scrolling(direction: .down)), .bottomNav) == .frosted)
    }

    @Test("scrolling + composerTray + busy → frostedStrong")
    func scrollingComposerTrayBusy() {
        #expect(resolve(ctx(brightness: .busy, scroll: .scrolling(direction: .down)), .composerTray) == .frostedStrong)
    }

    @Test("scrolling + actionStrip + non-busy → frosted")
    func scrollingActionStripNonBusy() {
        #expect(resolve(ctx(scroll: .scrolling(direction: .down)), .actionStrip) == .frosted)
    }

    @Test("scrolling + card → frosted")
    func scrollingCard() {
        #expect(resolve(ctx(scroll: .scrolling(direction: .down)), .card) == .frosted)
    }
}

@Suite("SurfaceStateResolver — deep")
struct DeepScrollTests {

    @Test("deep + topBar → collapsed")
    func deepTopBar() {
        #expect(resolve(ctx(scroll: .deep), .topBar) == .collapsed)
    }

    @Test("deep + bottomNav → frosted (system handles compress)")
    func deepBottomNav() {
        #expect(resolve(ctx(scroll: .deep), .bottomNav) == .frosted)
    }

    @Test("deep + statusZone → frosted")
    func deepStatusZone() {
        #expect(resolve(ctx(scroll: .deep), .statusZone) == .frosted)
    }

    @Test("deep + composerTray → frosted")
    func deepComposerTray() {
        #expect(resolve(ctx(scroll: .deep), .composerTray) == .frosted)
    }

    @Test("deep + actionStrip → frosted")
    func deepActionStrip() {
        #expect(resolve(ctx(scroll: .deep), .actionStrip) == .frosted)
    }

    @Test("deep + card → frosted")
    func deepCard() {
        #expect(resolve(ctx(scroll: .deep), .card) == .frosted)
    }
}

// MARK: - Priority ordering invariants

@Suite("SurfaceStateResolver — Priority Ordering Invariants")
struct PriorityInvariantTests {

    @Test("A11y beats video: video + increaseContrast + bottomNav → solidLight, not hidden")
    func a11yBeatsVideo() {
        let result = resolve(ctx(media: .video, increaseContrast: true), .bottomNav)
        #expect(result == .solidLight)
        #expect(result != .hidden)
    }

    @Test("A11y beats keyboard: keyboard + reduceTransparency + composerTray → solidLight")
    func a11yBeatsKeyboard() {
        let result = resolve(ctx(keyboard: true, reduceTransparency: true), .composerTray)
        #expect(result == .solidLight)
    }

    @Test("A11y beats busy: busy + increaseContrast + topBar → solidLight, not frostedStrong")
    func a11yBeatsBusy() {
        let result = resolve(ctx(brightness: .busy, scroll: .scrolling(direction: .down), increaseContrast: true), .topBar)
        #expect(result == .solidLight)
        #expect(result != .frostedStrong)
    }

    @Test("Video beats keyboard: video + keyboard + bottomNav → hidden, not frosted")
    func videoBeatsKeyboard() {
        // Video P1 runs before keyboard P2 for bottomNav.
        let result = resolve(ctx(media: .video, keyboard: true), .bottomNav)
        #expect(result == .hidden)
    }

    @Test("Neutral context returns non-hidden state for all roles")
    func neutralContextNeverHides() {
        let neutral = SurfaceContext.neutral
        let allRoles: [SurfaceRole] = [.statusZone, .topBar, .bottomNav, .composerTray, .actionStrip, .card]
        for role in allRoles {
            let result = resolve(neutral, role)
            #expect(result != .hidden, "Neutral context should never produce .hidden for \(role)")
        }
    }
}
