//
//  AkamaiMediaService.swift
//  AMENAPP
//
//  Rewrites Firebase Storage download URLs to go through Akamai CDN.
//  Also builds Image Manager URLs for server-side resize + WebP conversion.
//
//  Setup:
//  1. Configure an Akamai property with origin = firebasestorage.googleapis.com
//  2. Attach an Image Manager behavior to the property
//  3. Set AKAMAI_MEDIA_HOST in Config.xcconfig (e.g. media.amenapp.com)
//  4. Add AKAMAI_MEDIA_HOST key to Info.plist pointing to $(AKAMAI_MEDIA_HOST)
//
//  When AKAMAI_MEDIA_HOST is empty (default), all methods return the original
//  Firebase URL unchanged — safe to merge before Akamai is configured.
//

import Foundation

struct AkamaiMediaService {
    static let shared = AkamaiMediaService()

    /// Akamai CDN hostname, e.g. "media.amenapp.com".
    /// Read from Info.plist key AKAMAI_MEDIA_HOST (set via Config.xcconfig).
    /// Empty string = no CDN configured → fall through to Firebase origin.
    private let cdnHost: String = {
        (Bundle.main.object(forInfoDictionaryKey: "AKAMAI_MEDIA_HOST") as? String) ?? ""
    }()

    private init() {}

    // MARK: - CDN URL Rewriting

    /// Rewrite a Firebase Storage download URL to route through Akamai CDN.
    /// Returns the original URL unchanged when no CDN host is configured.
    ///
    ///   "https://firebasestorage.googleapis.com/v0/b/…"
    ///   → "https://media.amenapp.com/v0/b/…"
    func cdnURL(for firebaseURL: URL) -> URL {
        guard !cdnHost.isEmpty,
              var components = URLComponents(url: firebaseURL, resolvingAgainstBaseURL: false)
        else { return firebaseURL }
        components.host = cdnHost
        return components.url ?? firebaseURL
    }

    func cdnURL(for string: String) -> String {
        guard let url = URL(string: string) else { return string }
        return cdnURL(for: url).absoluteString
    }

    // MARK: - Image Manager URLs

    /// Build a URL that Akamai Image Manager will serve as a resized WebP.
    ///
    /// The Image Manager directive is appended as the `im` query parameter.
    /// If no CDN host is configured, returns the original URL so the app can
    /// fall back to client-side resize as today.
    ///
    /// - Parameters:
    ///   - base: Firebase Storage download URL string
    ///   - width: Target pixel width (pass 2× the point size for retina)
    ///   - height: Target pixel height, or nil for proportional scaling
    /// - Returns: Image Manager URL, or `nil` if `base` is not a valid URL
    func imageManagerURL(base: String, width: Int, height: Int? = nil) -> URL? {
        guard let url = URL(string: base) else { return nil }
        guard !cdnHost.isEmpty else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = cdnHost

        // Build Image Manager directive
        var directive = "resize,width=\(width),format=webp"
        if let height { directive += ",height=\(height)" }

        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "im", value: directive))
        components?.queryItems = items

        return components?.url
    }

    // MARK: - Convenience Helpers

    /// Profile avatar URL — 88×88 WebP (44pt @2x)
    func profileAvatarURL(_ base: String) -> URL? {
        imageManagerURL(base: base, width: 88, height: 88)
    }

    /// Post feed image — 750px wide WebP, height proportional
    func feedImageURL(_ base: String) -> URL? {
        imageManagerURL(base: base, width: 750)
    }

    /// Post detail image — 1242px wide WebP (iPhone max width @3x)
    func detailImageURL(_ base: String) -> URL? {
        imageManagerURL(base: base, width: 1242)
    }

    /// Thumbnail for notification/preview — 200×150 WebP
    func thumbnailURL(_ base: String) -> URL? {
        imageManagerURL(base: base, width: 200, height: 150)
    }
}
