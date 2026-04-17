//
//  SmartLinkClassifier.swift
//  AMENAPP
//
//  URL classification engine: categorizes links by type
//  (Bible, church, news, social, video, podcast, event, unsafe, general)
//  and determines the correct open mode for each category.
//

import Foundation

// MARK: - Link Open Mode

/// How the app should handle opening a link — derived from category + safety state.
enum LinkOpenMode {
    /// Route to a native in-app screen (AMEN deep link).
    case nativeInternal
    /// Open in the custom AMEN in-app browser.
    case inAppBrowser(readerMode: Bool)
    /// Open externally (e.g. the YouTube app, Instagram app).
    case externalApp
    /// Show a scripture-specific native view.
    case scriptureViewer
    /// Show a Maps-style action sheet for directions / event info.
    case mapsOrEventAction
    /// Show a safety warning before proceeding.
    case safetyInterstitial(message: String)
    /// Open in Safari as a last resort.
    case externalSafariFallback
}

// MARK: - Link Category

enum LinkCategory: String {
    case bible    = "Bible"
    case church   = "Church"
    case news     = "News"
    case social   = "Social"
    case video    = "Video"
    case podcast  = "Podcast"
    case event    = "Event"
    case unsafe   = "Warning"
    case general  = "Link"

    var icon: String {
        switch self {
        case .bible:   return "book.fill"
        case .church:  return "building.columns.fill"
        case .news:    return "newspaper.fill"
        case .social:  return "person.2.fill"
        case .video:   return "play.rectangle.fill"
        case .podcast: return "mic.fill"
        case .event:   return "calendar"
        case .unsafe:  return "exclamationmark.shield.fill"
        case .general: return "link"
        }
    }

    /// Whether this category should show a tinted badge on the card.
    var showsBadge: Bool { self != .general }

    /// The recommended open mode for this category (before safety checks).
    var defaultOpenMode: LinkOpenMode {
        switch self {
        case .bible:   return .scriptureViewer
        case .church:  return .inAppBrowser(readerMode: false)
        case .news:    return .inAppBrowser(readerMode: true)
        case .social:  return .externalApp
        case .video:   return .externalApp
        case .podcast: return .externalApp
        case .event:   return .mapsOrEventAction
        case .unsafe:  return .safetyInterstitial(message: "This link may be unsafe. Proceed with caution.")
        case .general: return .inAppBrowser(readerMode: false)
        }
    }
}

// MARK: - Smart Link Classifier

struct SmartLinkClassifier {

    // MARK: - Domain Sets

    private static let bibleDomains: Set<String> = [
        "bible.com", "youversion.com", "biblegateway.com",
        "biblehub.com", "blueletterbible.org", "openbible.info",
        "esv.org", "biblia.com", "bible.org", "bibleref.com",
        "biblestudytools.com", "bibleproject.com"
    ]

    private static let churchDomains: Set<String> = [
        "churchcenter.com", "planningcenter.com", "subsplash.com",
        "faithlife.com", "rightnowmedia.org", "sermons.io",
        "logos.com", "lifeway.com", "christianity.com",
        "thegospelcoalition.org", "desiringgod.org", "crosswalk.com",
        "gotquestions.org", "ligonier.org"
    ]

    private static let newsDomains: Set<String> = [
        "christianitytoday.com", "relevantmagazine.com", "churchleaders.com",
        "nytimes.com", "washingtonpost.com", "bbc.com", "cnn.com",
        "apnews.com", "reuters.com", "theatlantic.com", "time.com",
        "usatoday.com", "nbcnews.com", "foxnews.com", "cbsnews.com"
    ]

    private static let socialDomains: Set<String> = [
        "twitter.com", "x.com", "instagram.com", "facebook.com",
        "threads.net", "linkedin.com", "tiktok.com", "pinterest.com",
        "snapchat.com", "reddit.com"
    ]

    private static let videoDomains: Set<String> = [
        "youtube.com", "youtu.be", "vimeo.com", "rumble.com",
        "dailymotion.com", "twitch.tv"
    ]

    private static let podcastDomains: Set<String> = [
        "podcasts.apple.com", "open.spotify.com", "podcasts.google.com",
        "overcast.fm", "pocketcasts.com", "podchaser.com",
        "anchor.fm", "buzzsprout.com"
    ]

    private static let eventDomains: Set<String> = [
        "eventbrite.com", "ticketmaster.com", "meetup.com",
        "rsvpify.com", "splashthat.com"
    ]

    /// Domains known to be shorteners or suspicious — trigger safety interstitial.
    private static let unsafeDomains: Set<String> = [
        "bit.ly", "tinyurl.com", "t.co", "ow.ly", "buff.ly",
        "goo.gl", "is.gd", "rb.gy", "cutt.ly", "tiny.cc"
    ]

    // MARK: - Classification

    /// Classify a URL into a `LinkCategory`.
    static func classify(_ url: URL) -> LinkCategory {
        guard let rawHost = url.host?.lowercased() else { return .general }
        let host = rawHost.replacingOccurrences(of: "www.", with: "")

        if unsafeDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .unsafe
        }
        if bibleDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .bible
        }
        if churchDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .church
        }
        if videoDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .video
        }
        if podcastDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .podcast
        }
        if socialDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .social
        }
        if newsDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .news
        }
        if eventDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .event
        }

        // Path-based heuristics
        let path = url.path.lowercased()
        if path.contains("bible") || path.contains("verse") || path.contains("scripture") {
            return .bible
        }
        if path.contains("sermon") || path.contains("church") || path.contains("ministry") {
            return .church
        }
        if path.contains("podcast") || path.contains("episode") {
            return .podcast
        }
        if path.contains("event") || path.contains("rsvp") {
            return .event
        }

        return .general
    }

    /// Determine the full `LinkOpenMode` for a URL, incorporating safety state.
    static func openMode(for url: URL) -> LinkOpenMode {
        let category = classify(url)

        // Safety check via existing LinkSafetyService
        let decision = LinkSafetyService.check(url.absoluteString)
        switch decision {
        case .blocked(let reason, _), .blockedAndStrike(let reason, _, _):
            return .safetyInterstitial(message: reason)
        case .allowedWithWarn(let message):
            return .safetyInterstitial(message: message)
        case .allowed:
            break
        }

        // Check if this is an internal AMEN deep link
        if let host = url.host?.lowercased(), host.contains("amen.app") || host.contains("amenapp") {
            return .nativeInternal
        }

        return category.defaultOpenMode
    }

    /// Returns the display domain string for the card header.
    static func displayDomain(for url: URL) -> String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }
}
