import Foundation
import Testing
@testable import AMENAPP

struct ChurchNoteMusicAttachmentTests {
    @Test("Spotify URLs parse into normalized song links")
    func spotifyTrackURLParses() throws {
        let parsed = try ChurchNoteMusicURLParser.parse("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6?si=test")
        #expect(parsed.provider == .spotify)
        #expect(parsed.entityType == .song)
        #expect(parsed.providerID == "6rqhFgbbKwnb9MLmUQDhG6")
    }

    @Test("Apple Music album song URLs preserve storefront and song id")
    func appleMusicSongURLParses() throws {
        let parsed = try ChurchNoteMusicURLParser.parse("https://music.apple.com/us/album/goodness-of-god/1499302433?i=1499302437&utm_source=test")
        #expect(parsed.provider == .appleMusic)
        #expect(parsed.entityType == .song)
        #expect(parsed.providerID == "1499302437")
        #expect(parsed.storefront == "us")
    }

    @Test("Unsupported hosts are rejected")
    func unsupportedHostRejected() {
        #expect(throws: MusicAttachmentValidationError.unsupported) {
            try ChurchNoteMusicURLParser.parse("https://example.com/music/123")
        }
    }

    @Test("Normalized music attachment encodes and decodes")
    func musicAttachmentRoundTrip() throws {
        let original = WorshipSongReference(
            provider: .spotify,
            entityType: .album,
            providerID: "2noRn2Aes5aoNVsU6iWThc",
            storefront: nil,
            title: "Old Church Basement",
            artist: "Elevation Worship",
            subtitle: "Album",
            albumArtURL: "https://i.scdn.co/image/example",
            artworkColors: MusicArtworkColors(dominantHex: "#EFE9DF", secondaryHex: "#7A7468"),
            deepLinkURL: "spotify:album:2noRn2Aes5aoNVsU6iWThc",
            webURL: "https://open.spotify.com/album/2noRn2Aes5aoNVsU6iWThc",
            canonicalURL: "https://open.spotify.com/album/2noRn2Aes5aoNVsU6iWThc",
            appURL: "spotify:album:2noRn2Aes5aoNVsU6iWThc",
            explicit: false,
            durationMs: nil,
            requiresAccount: true,
            mayRequireSubscription: false,
            metadataVersion: 2,
            addedAt: Date(timeIntervalSince1970: 123),
            resolvedAt: Date(timeIntervalSince1970: 456)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorshipSongReference.self, from: data)

        #expect(decoded.provider == .spotify)
        #expect(decoded.entityType == .album)
        #expect(decoded.providerID == original.providerID)
        #expect(decoded.artworkColors?.dominantHex == "#EFE9DF")
        #expect(decoded.appURL == original.appURL)
        #expect(decoded.canonicalURL == original.canonicalURL)
    }

    @Test("Router uses web fallback when native app is unavailable")
    func routerFallsBackToWeb() {
        let attachment = WorshipSongReference(
            provider: .spotify,
            entityType: .song,
            providerID: "6rqhFgbbKwnb9MLmUQDhG6",
            title: "Jireh",
            artist: "Maverick City Music",
            deepLinkURL: "spotify:track:6rqhFgbbKwnb9MLmUQDhG6",
            webURL: "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6",
            canonicalURL: "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6",
            appURL: "spotify:track:6rqhFgbbKwnb9MLmUQDhG6",
            requiresAccount: true,
            mayRequireSubscription: false
        )

        let route = ChurchNoteMusicOpenRouter.route(for: attachment, nativeAppAvailable: false)
        #expect(route.state == .webFallback)
        #expect(route.primaryCTA == "View on web")
    }

    @Test("Presentation state marks missing artwork gracefully")
    func missingArtworkState() {
        let attachment = WorshipSongReference(
            provider: .appleMusic,
            entityType: .song,
            providerID: "1499302437",
            storefront: "us",
            title: "Goodness of God",
            artist: "CeCe Winans",
            canonicalURL: "https://music.apple.com/us/song/1499302437",
            appURL: "https://music.apple.com/us/song/1499302437",
            requiresAccount: true,
            mayRequireSubscription: true
        )

        let route = ChurchNoteMusicOpenRouter.route(for: attachment, nativeAppAvailable: true)
        #expect(route.state == .missingArtwork)
    }

    @Test("Unavailable attachments produce a non-broken state")
    func unavailableAttachmentState() {
        let attachment = WorshipSongReference(
            provider: .spotify,
            entityType: .song,
            providerID: "broken",
            title: "Unavailable",
            artist: "Unknown",
            canonicalURL: nil,
            appURL: nil,
            requiresAccount: false,
            mayRequireSubscription: false
        )

        let route = ChurchNoteMusicOpenRouter.route(for: attachment, nativeAppAvailable: false)
        #expect(route.state == .unavailable)
        #expect(route.primaryCTA == "Unavailable")
    }

    // MARK: - Additional URL parsing coverage

    @Test("Spotify URI scheme (spotify:track:ID) parses correctly")
    func spotifyURIParses() throws {
        let parsed = try ChurchNoteMusicURLParser.parse("spotify:track:6rqhFgbbKwnb9MLmUQDhG6")
        #expect(parsed.provider == .spotify)
        #expect(parsed.entityType == .song)
        #expect(parsed.providerID == "6rqhFgbbKwnb9MLmUQDhG6")
        #expect(parsed.sanitizedURL == "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6")
    }

    @Test("Spotify album URI scheme parses correctly")
    func spotifyAlbumURIParses() throws {
        let parsed = try ChurchNoteMusicURLParser.parse("spotify:album:2noRn2Aes5aoNVsU6iWThc")
        #expect(parsed.provider == .spotify)
        #expect(parsed.entityType == .album)
        #expect(parsed.providerID == "2noRn2Aes5aoNVsU6iWThc")
    }

    @Test("Spotify album URL parses correctly")
    func spotifyAlbumURLParses() throws {
        let parsed = try ChurchNoteMusicURLParser.parse("https://open.spotify.com/album/2noRn2Aes5aoNVsU6iWThc?si=abc")
        #expect(parsed.provider == .spotify)
        #expect(parsed.entityType == .album)
        #expect(parsed.providerID == "2noRn2Aes5aoNVsU6iWThc")
        // query stripped
        #expect(!parsed.sanitizedURL.contains("si="))
    }

    @Test("Apple Music direct song URL (no ?i= parameter) parses correctly")
    func appleMusicDirectSongURLParses() throws {
        let parsed = try ChurchNoteMusicURLParser.parse("https://music.apple.com/us/song/goodness-of-god/1499302437")
        #expect(parsed.provider == .appleMusic)
        #expect(parsed.entityType == .song)
        #expect(parsed.storefront == "us")
        #expect(parsed.providerID == "1499302437")
    }

    @Test("Apple Music album URL parses correctly")
    func appleMusicAlbumURLParses() throws {
        let parsed = try ChurchNoteMusicURLParser.parse("https://music.apple.com/gb/album/old-church-basement/1553944672")
        #expect(parsed.provider == .appleMusic)
        #expect(parsed.entityType == .album)
        #expect(parsed.storefront == "gb")
        #expect(parsed.providerID == "1553944672")
    }

    @Test("Empty string throws empty error")
    func emptyStringThrows() {
        #expect(throws: MusicAttachmentValidationError.empty) {
            try ChurchNoteMusicURLParser.parse("")
        }
    }

    @Test("Whitespace-only string throws empty error")
    func whitespaceOnlyStringThrows() {
        #expect(throws: MusicAttachmentValidationError.empty) {
            try ChurchNoteMusicURLParser.parse("   ")
        }
    }

    @Test("Malformed URL throws malformed error")
    func malformedURLThrows() {
        #expect(throws: MusicAttachmentValidationError.malformed) {
            try ChurchNoteMusicURLParser.parse("not a url at all ://")
        }
    }

    @Test("Router produces correct native CTA when app is available")
    func routerNativeCTA() {
        let attachment = WorshipSongReference(
            provider: .appleMusic,
            entityType: .song,
            providerID: "1499302437",
            storefront: "us",
            title: "Goodness of God",
            artist: "CeCe Winans",
            albumArtURL: "https://example.com/art.jpg",
            canonicalURL: "https://music.apple.com/us/song/1499302437",
            appURL: "https://music.apple.com/us/song/1499302437",
            requiresAccount: true,
            mayRequireSubscription: true
        )

        let route = ChurchNoteMusicOpenRouter.route(for: attachment, nativeAppAvailable: true)
        #expect(route.state == .attached)
        #expect(route.primaryCTA == "Open in Apple Music")
    }

    @Test("Router account-required copy is accurate for Spotify")
    func routerSpotifyAccountCopy() {
        let attachment = WorshipSongReference(
            provider: .spotify,
            entityType: .song,
            providerID: "6rqhFgbbKwnb9MLmUQDhG6",
            title: "Jireh",
            artist: "Maverick City Music",
            albumArtURL: "https://example.com/art.jpg",
            canonicalURL: "https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6",
            appURL: "spotify:track:6rqhFgbbKwnb9MLmUQDhG6",
            requiresAccount: true,
            mayRequireSubscription: false
        )

        let route = ChurchNoteMusicOpenRouter.route(for: attachment, nativeAppAvailable: true)
        #expect(route.helperText.contains("Spotify"))
    }
}
