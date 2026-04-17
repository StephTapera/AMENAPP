import Foundation

// MARK: - Suggested Rail Analytics Helper

/// Convenience wrapper around `AMENAnalyticsService` for all suggestion rail events.
/// Centralizes event construction so surface renderers, the ViewModel, and the peek
/// sheet can fire analytics with a single call instead of constructing enum cases inline.
enum SuggestedRailAnalytics {

    private static var analytics: AMENAnalyticsService { .shared }

    // MARK: - Card Events

    /// A suggestion card became visible in the scroll viewport.
    static func trackImpression(userId: String, position: Int, reasonType: String) {
        analytics.track(.suggestionImpression(suggestedUserId: userId, position: position, reasonType: reasonType))
    }

    /// The user tapped the follow button on a suggestion card.
    static func trackFollowTap(userId: String, position: Int) {
        analytics.track(.suggestionFollowTap(suggestedUserId: userId, position: position))
    }

    /// A follow request succeeded.
    static func trackFollowSuccess(userId: String) {
        analytics.track(.suggestionFollowSuccess(suggestedUserId: userId))
    }

    /// A follow request failed.
    static func trackFollowFailure(userId: String) {
        analytics.track(.suggestionFollowFailure(suggestedUserId: userId))
    }

    /// The user tapped on a suggestion card to open the profile (without peek sheet).
    static func trackProfileOpen(userId: String) {
        analytics.track(.suggestionProfileOpen(suggestedUserId: userId))
    }

    /// The user dismissed a suggestion card.
    static func trackDismiss(userId: String) {
        analytics.track(.suggestionDismiss(suggestedUserId: userId))
    }

    // MARK: - Rail Events

    /// The suggestions rail became visible with a given number of cards.
    static func trackRailSeen(count: Int) {
        analytics.track(.suggestionsRailSeen(count: count))
    }

    /// The user hid the suggestions module (legacy event, no surface).
    static func trackModuleHidden() {
        analytics.track(.suggestionsModuleHidden)
    }

    /// The user restored the suggestions module (legacy event, no surface).
    static func trackModuleRestored() {
        analytics.track(.suggestionsModuleRestored)
    }

    // MARK: - Surface-Aware Events

    /// The user opened the peek sheet for a suggestion card.
    static func trackPeekOpen(userId: String, surface: SuggestionSurface) {
        analytics.track(.suggestionPeekOpen(suggestedUserId: userId, surface: surface.rawValue))
    }

    /// The user expanded the peek sheet from compact to full height.
    static func trackPeekExpand(userId: String, surface: SuggestionSurface) {
        analytics.track(.suggestionPeekExpand(suggestedUserId: userId, surface: surface.rawValue))
    }

    /// The user opened the full profile from the peek sheet.
    static func trackFullProfileOpen(userId: String, surface: SuggestionSurface) {
        analytics.track(.suggestionFullProfileOpen(suggestedUserId: userId, surface: surface.rawValue))
    }

    /// The user hid the rail for a specific surface.
    static func trackRailHidden(surface: SuggestionSurface) {
        analytics.track(.suggestionRailHidden(surface: surface.rawValue))
    }

    /// The rail was restored for a specific surface.
    static func trackRailRestored(surface: SuggestionSurface) {
        analytics.track(.suggestionRailRestored(surface: surface.rawValue))
    }

    /// The user chose "Show fewer suggestions" for a surface.
    static func trackShowFewer(surface: SuggestionSurface) {
        analytics.track(.suggestionShowFewer(surface: surface.rawValue))
    }

    /// The user chose "Why am I seeing this?" for a surface.
    static func trackWhyShown(surface: SuggestionSurface) {
        analytics.track(.suggestionWhyShown(surface: surface.rawValue))
    }
}
