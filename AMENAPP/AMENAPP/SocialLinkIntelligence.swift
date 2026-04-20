//
//  SocialLinkIntelligence.swift
//  AMENAPP
//
//  URL paste detection and platform normalization for social links.
//  Paste any URL → get back platform, clean handle, normalized URL,
//  suggested category, and a display label.
//
//  Pure Swift — no Firebase, no network calls, no UI.
//  Call SocialLinkIntelligence.parse(rawInput:) from the Add/Edit link sheet.
//

import Foundation

enum SocialLinkIntelligence {

    // MARK: - Result

    struct ParsedLink {
        let detectedPlatform: KnownPlatform?  // nil = unknown / generic URL
        let handle: String                    // cleaned username / handle / domain
        let normalizedURL: String             // canonical URL for platform
        let suggestedCategory: SocialLinkCategory
        let suggestedDisplayLabel: String     // e.g. "@user on YouTube"
        let isValidFormat: Bool
    }

    // MARK: - Known Platforms
    // Superset of the 5-platform UI picker — includes faith-native and audio link types.
    // Separate from SocialLinkUI.SocialPlatform to avoid changing the existing UI enum.

    enum KnownPlatform: String, CaseIterable {
        // Mainstream social
        case instagram   = "Instagram"
        case twitter     = "Twitter"
        case youtube     = "YouTube"
        case tiktok      = "TikTok"
        case linkedin    = "LinkedIn"
        case facebook    = "Facebook"
        case threads     = "Threads"
        // Audio / podcast
        case spotify     = "Spotify"
        case appleMusic  = "Apple Music"
        case applePodcast = "Apple Podcasts"
        case anchor      = "Anchor / Spotify for Podcasters"
        // Faith-native
        case churchCenter    = "Church Center"
        case planningCenter  = "Planning Center"
        case rightNowMedia   = "RightNow Media"
        case bible           = "Bible.com"
        // Generic
        case website    = "Website"
        case givingPage = "Giving Page"

        var urlPatterns: [String] {
            switch self {
            case .instagram:     return ["instagram.com"]
            case .twitter:       return ["twitter.com", "x.com"]
            case .youtube:       return ["youtube.com", "youtu.be"]
            case .tiktok:        return ["tiktok.com"]
            case .linkedin:      return ["linkedin.com"]
            case .facebook:      return ["facebook.com", "fb.com", "fb.me"]
            case .threads:       return ["threads.net"]
            case .spotify:       return ["open.spotify.com", "spotify.com"]
            case .appleMusic:    return ["music.apple.com"]
            case .applePodcast:  return ["podcasts.apple.com"]
            case .anchor:        return ["anchor.fm", "podcasters.spotify.com"]
            case .churchCenter:  return ["churchcenter.com"]
            case .planningCenter:return ["planningcenteronline.com", "planningcenter.com"]
            case .rightNowMedia: return ["rightnowmedia.org"]
            case .bible:         return ["bible.com", "youversion.com"]
            case .givingPage:    return ["pushpay.com", "tithe.ly", "givelify.com", "donorbox.org", "paypal.com/donate", "cash.app/$"]
            case .website:       return []
            }
        }

        var defaultCategory: SocialLinkCategory {
            switch self {
            case .instagram, .twitter, .tiktok, .threads, .facebook:
                return .personal
            case .youtube:
                return .teaching
            case .linkedin:
                return .personal
            case .spotify, .appleMusic, .anchor:
                return .music
            case .applePodcast:
                return .teaching
            case .churchCenter, .planningCenter:
                return .ministry
            case .rightNowMedia, .bible:
                return .study
            case .givingPage:
                return .giving
            case .website:
                return .website
            }
        }

        /// Maps back to the rawValue used by SocialLinkUI.SocialPlatform for the current
        /// 5-platform picker — returns nil for platforms not yet in the UI picker.
        var legacyPlatformRaw: String? {
            switch self {
            case .instagram: return "Instagram"
            case .twitter:   return "Twitter"
            case .youtube:   return "YouTube"
            case .tiktok:    return "TikTok"
            case .linkedin:  return "LinkedIn"
            default:         return nil
            }
        }
    }

    // MARK: - Parse Entry Point

    /// Accepts a pasted URL or a bare username.
    /// Returns nil only if `rawInput` is blank.
    static func parse(rawInput: String) -> ParsedLink? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let looksLikeURL = trimmed.hasPrefix("http") || trimmed.contains(".")
        return looksLikeURL ? parseURL(trimmed) : parseBareHandle(trimmed)
    }

    // MARK: - URL Parsing

    private static func parseURL(_ raw: String) -> ParsedLink? {
        let withScheme = raw.hasPrefix("http") ? raw : "https://\(raw)"
        guard let components = URLComponents(string: withScheme),
              let host = components.host?.lowercased() else { return nil }

        let platform = KnownPlatform.allCases.first { p in
            p.urlPatterns.contains { pattern in
                host.contains(pattern) || withScheme.lowercased().contains(pattern)
            }
        }

        let handle = extractHandle(from: components, platform: platform, fallback: host)
        let cleanHandle = handle.replacingOccurrences(of: "@", with: "")
        let normalized = normalizedURL(for: platform, handle: cleanHandle, fallback: withScheme)
        let category = platform?.defaultCategory ?? .website
        let displayLabel = platform.map { "\(cleanHandle) on \($0.rawValue)" } ?? withScheme

        return ParsedLink(
            detectedPlatform: platform,
            handle: cleanHandle,
            normalizedURL: normalized,
            suggestedCategory: category,
            suggestedDisplayLabel: displayLabel,
            isValidFormat: !cleanHandle.isEmpty
        )
    }

    private static func parseBareHandle(_ raw: String) -> ParsedLink {
        let handle = raw.replacingOccurrences(of: "@", with: "")
        return ParsedLink(
            detectedPlatform: nil,
            handle: handle,
            normalizedURL: raw,
            suggestedCategory: .personal,
            suggestedDisplayLabel: handle,
            isValidFormat: !handle.isEmpty
        )
    }

    // MARK: - Handle Extraction

    private static func extractHandle(from components: URLComponents,
                                       platform: KnownPlatform?,
                                       fallback: String) -> String {
        let path = components.path

        switch platform {
        case .youtube:
            if path.hasPrefix("/@") { return String(path.dropFirst(2)) }
            return firstPathSegment(path)

        case .linkedin:
            let segments = path.components(separatedBy: "/").filter { !$0.isEmpty }
            // /in/{handle} or /company/{handle}
            return segments.count >= 2 ? segments[1] : (segments.first ?? fallback)

        case .spotify, .applePodcast, .appleMusic, .anchor,
             .churchCenter, .planningCenter, .rightNowMedia, .bible:
            return fallback    // domain is the most meaningful identifier

        case .givingPage:
            return fallback

        case .website, nil:
            return fallback

        default:
            // Instagram, Twitter, TikTok, Facebook, Threads, LinkedIn (in)
            return firstPathSegment(path)
        }
    }

    // MARK: - URL Normalization

    static func normalizedURL(for platform: KnownPlatform?,
                               handle: String,
                               fallback: String) -> String {
        switch platform {
        case .instagram:  return "https://instagram.com/\(handle)"
        case .twitter:    return "https://twitter.com/\(handle)"
        case .youtube:    return "https://youtube.com/@\(handle)"
        case .tiktok:     return "https://tiktok.com/@\(handle)"
        case .linkedin:   return "https://linkedin.com/in/\(handle)"
        case .facebook:   return "https://facebook.com/\(handle)"
        case .threads:    return "https://threads.net/@\(handle)"
        default:          return fallback
        }
    }

    // MARK: - Duplicate Prevention Key

    /// Returns a stable dedup key for a parsed link.
    /// Two links are considered duplicates if they resolve to the same key.
    static func platformKey(for parsed: ParsedLink) -> String {
        parsed.detectedPlatform?.rawValue ?? parsed.normalizedURL
    }

    // MARK: - Validation

    /// Quick format check — does not make a network request.
    static func isValidHandle(_ handle: String, for platform: KnownPlatform) -> Bool {
        guard !handle.isEmpty else { return false }
        let clean = handle.replacingOccurrences(of: "@", with: "")
        switch platform {
        case .instagram, .twitter, .tiktok, .threads:
            return clean.count >= 1 && clean.count <= 30
                && clean.range(of: "^[A-Za-z0-9_.]+$", options: .regularExpression) != nil
        case .youtube:
            return clean.count >= 3
        case .linkedin:
            return clean.count >= 3 && clean.count <= 100
        default:
            return clean.count >= 1
        }
    }

    // MARK: - Helpers

    private static func firstPathSegment(_ path: String) -> String {
        path.components(separatedBy: "/").filter { !$0.isEmpty }.first ?? ""
    }
}
