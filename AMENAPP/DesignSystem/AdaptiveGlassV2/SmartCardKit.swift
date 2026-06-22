//
//  SmartCardKit.swift
//  AMEN — Adaptive Glass V2
//
//  Wave 5: Smart adaptive cards.
//
//  Detects Bible references and rich URLs in post text and renders
//  adaptive glass cards below the text body.
//
//  Usage:
//
//      Text(post.body)
//          .smartCards(from: post.body)
//
//  All cards automatically adopt .adaptiveSurface(.card) — they respond
//  to media brightness and scroll context without any per-site logic.
//
//  Provider registry: add a new case to URLCardProvider + a matching
//  case in `from(url:)` to detect a new domain. No other file changes needed.
//

import SwiftUI

// MARK: - Bible reference model

/// A detected Bible verse reference.
public struct BibleReference: Hashable, Equatable, Sendable {
    public let displayText: String  // e.g. "John 3:16"
    public let book: String         // e.g. "John"
    public let chapter: Int
    public let verseStart: Int?
    public let verseEnd: Int?

    /// amen://bible/ deep-link used by the Selah / Berean reader.
    public var deepLink: URL? {
        guard let encoded = displayText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "amen://bible/\(encoded)")
    }
}

// MARK: - URL provider registry

/// One case per recognized content provider.
/// Add a case + entry in `from(url:)` to register a new provider.
public enum URLCardProvider: Equatable, Sendable {
    case youtube
    case spotify
    case appleMusic
    case podcast
    case bible
    case sermon
    case church
    case map
    case generic(domain: String)

    /// Identify the provider from a URL's host.
    public static func from(url: URL) -> URLCardProvider {
        let host = url.host?.lowercased() ?? ""
        switch true {
        case host.contains("youtube.com"), host.contains("youtu.be"):   return .youtube
        case host.contains("spotify.com"):                               return .spotify
        case host.contains("music.apple.com"):                           return .appleMusic
        case host.contains("bible.com"), host.contains("biblegateway"): return .bible
        case host.contains("maps.apple.com"), host.contains("maps.google.com"): return .map
        default:
            return .generic(domain: url.host ?? url.absoluteString)
        }
    }

    var icon: String {
        switch self {
        case .youtube:          return "play.rectangle.fill"
        case .spotify:          return "music.note"
        case .appleMusic:       return "music.note"
        case .podcast:          return "mic.fill"
        case .bible:            return "book.closed.fill"
        case .sermon:           return "waveform"
        case .church:           return "building.columns.fill"
        case .map:              return "map.fill"
        case .generic:          return "link"
        }
    }

    var accentColor: Color {
        switch self {
        case .youtube:          return Color(red: 1.0,  green: 0.0,  blue: 0.0)
        case .spotify:          return Color(red: 0.11, green: 0.73, blue: 0.33)
        case .appleMusic:       return Color(red: 0.98, green: 0.20, blue: 0.46)
        case .bible, .sermon:   return .accentColor
        case .church:           return .indigo
        case .map:              return .blue
        case .generic:          return .secondary
        case .podcast:          return .purple
        }
    }

    /// Human-readable label shown under the domain.
    var typeLabel: String {
        switch self {
        case .youtube:          return "YouTube video"
        case .spotify:          return "Spotify"
        case .appleMusic:       return "Apple Music"
        case .podcast:          return "Podcast"
        case .bible:            return "Bible"
        case .sermon:           return "Sermon"
        case .church:           return "Church"
        case .map:              return "Maps"
        case .generic:          return "Link"
        }
    }
}

// MARK: - Detector

/// Scans post body text for Bible references and https URLs.
/// Pure, synchronous, safe to call on any thread.
public enum SmartCardDetector {

    // Matches "1 John 4:8-9", "Romans 8", "Ps. 23:1", "John 3:16" etc.
    // Group 1 = optional number prefix, Group 2 = book name, Group 3 = chapter,
    // Group 4 = verse start (optional), Group 5 = verse end (optional).
    private static let bibleRaw = #"((?:[1-3]\s)?[A-Z][A-Za-z]+\.?)\s+(\d+)(?::(\d+)(?:\s*-\s*(\d+))?)?"#

    private static let bibleRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: bibleRaw, options: [])
    }()

    // Simple URL detector — finds http/https links.
    private static let urlRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#, options: [])
    }()

    /// Returns up to 3 Bible references detected in `text`.
    public static func detectBibleReferences(in text: String) -> [BibleReference] {
        guard let regex = bibleRegex else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)

        return matches.prefix(3).compactMap { m -> BibleReference? in
            guard let rawRange = Range(m.range, in: text) else { return nil }
            let raw = String(text[rawRange])
            let book    = captureGroup(1, match: m, in: text) + captureGroup(2, match: m, in: text)
            let chapStr = captureGroup(3, match: m, in: text)
            guard let chap = Int(chapStr.isEmpty ? captureGroup(3, match: m, in: text) : chapStr),
                  chap > 0
            else {
                // fallback parse
                let parts = raw.split(separator: " ", maxSplits: 2)
                guard parts.count >= 2, let c = Int(String(parts.last ?? "0")) else { return nil }
                return BibleReference(displayText: raw, book: raw, chapter: c,
                                      verseStart: nil, verseEnd: nil)
            }
            let vs = Int(captureGroup(4, match: m, in: text))
            let ve = Int(captureGroup(5, match: m, in: text))
            return BibleReference(displayText: raw.trimmingCharacters(in: .whitespaces),
                                  book: book.trimmingCharacters(in: .whitespaces),
                                  chapter: chap, verseStart: vs, verseEnd: ve)
        }
    }

    /// Returns up to 3 URLs detected in `text`, skipping duplicates.
    public static func detectURLs(in text: String) -> [URL] {
        guard let regex = urlRegex else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)
        var seen = Set<String>()
        return matches.prefix(3).compactMap { m -> URL? in
            guard let r = Range(m.range, in: text) else { return nil }
            let raw = String(text[r])
            guard seen.insert(raw).inserted,
                  let url = URL(string: raw)
            else { return nil }
            return url
        }
    }

    private static func captureGroup(_ n: Int, match m: NSTextCheckingResult, in text: String) -> String {
        guard n < m.numberOfRanges, let r = Range(m.range(at: n), in: text) else { return "" }
        return String(text[r])
    }
}

// MARK: - Smart Bible Card

/// Adaptive glass card for a detected Bible verse reference.
/// Tapping deep-links into the Selah / Berean scripture reader.
public struct SmartBibleCard: View {

    public let reference: BibleReference

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Button {
            if let url = reference.deepLink { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                iconBadge(systemName: "book.closed.fill", tint: .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.displayText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Open in Scripture reader")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .adaptiveSurface(.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        .accessibilityLabel("Scripture reference: \(reference.displayText)")
        .accessibilityHint("Opens this passage in the scripture reader")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Smart URL Card

/// Adaptive glass card for a detected URL.
/// Provider is determined from the host; icon and accent adapt automatically.
public struct SmartURLCard: View {

    public let url: URL
    public let provider: URLCardProvider

    @Environment(\.openURL) private var openURL

    public var body: some View {
        Button { openURL(url) } label: {
            HStack(spacing: 12) {
                iconBadge(systemName: provider.icon, tint: provider.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.host ?? url.absoluteString)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(provider.typeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .adaptiveSurface(.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(provider.accentColor.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        .accessibilityLabel("Link: \(url.host ?? url.absoluteString), \(provider.typeLabel)")
        .accessibilityHint("Opens in browser")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Shared icon badge helper

@ViewBuilder
private func iconBadge(systemName: String, tint: Color) -> some View {
    Image(systemName: systemName)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(tint)
        .frame(width: 32, height: 32)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
}

// MARK: - Smart card container modifier

/// Scans `text` for Bible references and URLs and appends the appropriate
/// adaptive glass cards below the content view.
///
///     Text(post.body)
///         .smartCards(from: post.body)
///
/// Detection runs asynchronously on first appear and on text changes.
/// No-op when `adaptiveGlassV2Enabled` is OFF.
public struct SmartCardModifier: ViewModifier {

    let text: String

    @State private var bibleRefs: [BibleReference] = []
    @State private var smartURLs:  [URL]            = []

    public func body(content: Content) -> some View {
        guard AMENFeatureFlags.shared.adaptiveGlassV2Enabled else {
            return AnyView(content)
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                content

                ForEach(bibleRefs, id: \.displayText) { ref in
                    SmartBibleCard(reference: ref)
                }

                ForEach(smartURLs, id: \.absoluteString) { url in
                    SmartURLCard(url: url, provider: URLCardProvider.from(url: url))
                }
            }
            .task(id: text) {
                // Off the render path — detect after the view is on screen.
                let refs = SmartCardDetector.detectBibleReferences(in: text)
                let urls = SmartCardDetector.detectURLs(in: text)
                bibleRefs = refs
                smartURLs = urls
            }
        )
    }
}

public extension View {
    /// Detect Bible references and URLs in `text` and append adaptive glass
    /// cards below this view. Detection runs asynchronously.
    /// No-op when `adaptiveGlassV2Enabled` is OFF.
    func smartCards(from text: String) -> some View {
        modifier(SmartCardModifier(text: text))
    }
}
