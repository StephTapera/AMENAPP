import SwiftUI
import UIKit
import FirebaseFunctions

enum MusicAttachmentValidationError: LocalizedError, Equatable {
    case empty
    case unsupported
    case malformed

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Paste an Apple Music or Spotify link to attach music."
        case .unsupported:
            return "That link isn’t a supported Apple Music or Spotify song or album link."
        case .malformed:
            return "We couldn’t read that music link. Check the URL and try again."
        }
    }
}

struct ParsedMusicLink: Equatable {
    let provider: MusicProvider
    let entityType: MusicEntityType
    let providerID: String
    let storefront: String?
    let sanitizedURL: String
}

enum ChurchNoteMusicURLParser {
    static func parse(_ rawValue: String) throws -> ParsedMusicLink {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MusicAttachmentValidationError.empty }

        if trimmed.lowercased().hasPrefix("spotify:") {
            return try parseSpotifyURI(trimmed)
        }

        guard var components = URLComponents(string: trimmed),
              let host = components.host?.lowercased() else {
            throw MusicAttachmentValidationError.malformed
        }

        if host == "open.spotify.com" {
            components.query = nil
            components.fragment = nil
            return try parseSpotifyURL(components)
        }

        if host == "music.apple.com" || host == "itunes.apple.com" {
            return try parseAppleMusicURL(components)
        }

        throw MusicAttachmentValidationError.unsupported
    }

    private static func parseSpotifyURI(_ rawValue: String) throws -> ParsedMusicLink {
        let components = rawValue.split(separator: ":")
        guard components.count >= 3 else { throw MusicAttachmentValidationError.malformed }

        let entity: MusicEntityType
        switch components[1].lowercased() {
        case "track":
            entity = .song
        case "album":
            entity = .album
        default:
            throw MusicAttachmentValidationError.unsupported
        }

        let identifier = String(components[2])
        guard !identifier.isEmpty else { throw MusicAttachmentValidationError.malformed }

        let webURL = "https://open.spotify.com/\(entity == .album ? "album" : "track")/\(identifier)"
        return ParsedMusicLink(
            provider: .spotify,
            entityType: entity,
            providerID: identifier,
            storefront: nil,
            sanitizedURL: webURL
        )
    }

    private static func parseSpotifyURL(_ components: URLComponents) throws -> ParsedMusicLink {
        let pathComponents = components.path.split(separator: "/")
        guard pathComponents.count >= 2 else { throw MusicAttachmentValidationError.malformed }

        let entity: MusicEntityType
        switch pathComponents[0].lowercased() {
        case "track":
            entity = .song
        case "album":
            entity = .album
        default:
            throw MusicAttachmentValidationError.unsupported
        }

        let identifier = String(pathComponents[1])
        guard !identifier.isEmpty else { throw MusicAttachmentValidationError.malformed }

        return ParsedMusicLink(
            provider: .spotify,
            entityType: entity,
            providerID: identifier,
            storefront: nil,
            sanitizedURL: "https://open.spotify.com/\(entity == .album ? "album" : "track")/\(identifier)"
        )
    }

    private static func parseAppleMusicURL(_ components: URLComponents) throws -> ParsedMusicLink {
        let pathComponents = components.path.split(separator: "/")
        guard pathComponents.count >= 3 else { throw MusicAttachmentValidationError.malformed }

        let storefront = String(pathComponents[0])
        let resourceType = pathComponents[1].lowercased()
        let trailingIdentifier = String(pathComponents.last ?? "")
        guard !trailingIdentifier.isEmpty else { throw MusicAttachmentValidationError.malformed }

        let queryItems = components.queryItems ?? []
        let songIdentifier = queryItems.first(where: { $0.name == "i" })?.value

        let entityType: MusicEntityType
        let providerID: String

        if let songIdentifier, !songIdentifier.isEmpty {
            entityType = .song
            providerID = songIdentifier
        } else {
            switch resourceType {
            case "song":
                entityType = .song
                providerID = trailingIdentifier
            case "album":
                entityType = .album
                providerID = trailingIdentifier
            default:
                throw MusicAttachmentValidationError.unsupported
            }
        }

        var sanitized = components
        sanitized.fragment = nil
        sanitized.queryItems = songIdentifier.map { [URLQueryItem(name: "i", value: $0)] } ?? []

        return ParsedMusicLink(
            provider: .appleMusic,
            entityType: entityType,
            providerID: providerID,
            storefront: storefront,
            sanitizedURL: sanitized.string ?? components.string ?? ""
        )
    }
}

enum ChurchNoteMusicEnvironment {
    static var defaultStorefront: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "APPLE_MUSIC_DEFAULT_STOREFRONT") as? String
        let normalized = configured?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized?.isEmpty == false ? normalized! : "us"
    }
}

actor ChurchNoteMusicAttachmentCache {
    static let shared = ChurchNoteMusicAttachmentCache()

    private var attachments: [String: WorshipSongReference] = [:]

    func attachment(forKey key: String) -> WorshipSongReference? {
        attachments[key]
    }

    func store(_ attachment: WorshipSongReference, forKey key: String) {
        attachments[key] = attachment
    }
}

private struct MusicAttachmentResolvedPayload: Decodable {
    let provider: MusicProvider
    let entityType: MusicEntityType
    let providerID: String
    let storefront: String?
    let canonicalURL: String
    let appURL: String?
    let title: String
    let subtitle: String?
    let artistName: String
    let artworkURL: String?
    let artworkColors: MusicArtworkColors?
    let explicit: Bool?
    let durationMs: Int?
    let requiresAccount: Bool
    let mayRequireSubscription: Bool
    let metadataVersion: Int
    let attachedAt: Date?
    let resolvedAt: Date?
}

@MainActor
final class ChurchNoteMusicAttachmentResolverService {
    static let shared = ChurchNoteMusicAttachmentResolverService()

    private let functions = Functions.functions()
    private let cache = ChurchNoteMusicAttachmentCache.shared

    private init() {}

    func resolve(urlString: String, storefront: String? = nil) async throws -> WorshipSongReference {
        let parsed = try ChurchNoteMusicURLParser.parse(urlString)
        let resolvedStorefront = storefront?.lowercased() ?? parsed.storefront ?? ChurchNoteMusicEnvironment.defaultStorefront
        let cacheKey = "\(parsed.provider.rawValue)|\(parsed.entityType.rawValue)|\(parsed.providerID)|\(resolvedStorefront)"

        if let cached = await cache.attachment(forKey: cacheKey) {
            return cached
        }

        let result = try await functions
            .httpsCallable("resolveMusicAttachment")
            .safeCall([
                "url": parsed.sanitizedURL,
                "storefront": resolvedStorefront,
            ])

        guard let data = result.data as? [String: Any] else {
            throw MusicAttachmentValidationError.malformed
        }

        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(MusicAttachmentResolvedPayload.self, from: jsonData)

        let attachment = WorshipSongReference(
            provider: payload.provider,
            entityType: payload.entityType,
            providerID: payload.providerID,
            storefront: payload.storefront,
            title: payload.title,
            artist: payload.artistName,
            subtitle: payload.subtitle,
            musicKitID: payload.provider == .appleMusic ? payload.providerID : nil,
            deepLinkURL: payload.appURL,
            webURL: payload.canonicalURL,
            canonicalURL: payload.canonicalURL,
            appURL: payload.appURL,
            albumArtURL: payload.artworkURL,
            artworkColors: payload.artworkColors,
            explicit: payload.explicit,
            durationMs: payload.durationMs,
            requiresAccount: payload.requiresAccount,
            mayRequireSubscription: payload.mayRequireSubscription,
            metadataVersion: payload.metadataVersion,
            addedAt: payload.attachedAt ?? Date(),
            resolvedAt: payload.resolvedAt ?? Date()
        )

        await cache.store(attachment, forKey: cacheKey)
        return attachment
    }
}

enum MusicAttachmentPresentationState: Equatable {
    case attached
    case missingArtwork
    case webFallback
    case unavailable
}

struct MusicAttachmentOpenRoute: Equatable {
    let nativeURL: URL?
    let webURL: URL?
    let state: MusicAttachmentPresentationState
    let primaryCTA: String
    let helperText: String
    let accessibilityText: String
}

enum ChurchNoteMusicOpenRouter {
    static func route(for attachment: WorshipSongReference, nativeAppAvailable: Bool) -> MusicAttachmentOpenRoute {
        let nativeURL = attachment.appURL.flatMap(URL.init(string:))
        let webURL = attachment.canonicalURL.flatMap(URL.init(string:))
        let providerName = attachment.provider.displayName
        let requiresAccountCopy = attachment.provider == .appleMusic
            ? "Apple Music account may be required"
            : "Spotify login may be required"

        let state: MusicAttachmentPresentationState
        if nativeURL == nil && webURL == nil {
            state = .unavailable
        } else if nativeAppAvailable || nativeURL == nil {
            state = attachment.artworkURL == nil ? .missingArtwork : .attached
        } else if webURL != nil {
            state = .webFallback
        } else {
            state = .unavailable
        }

        let primaryCTA: String
        if nativeAppAvailable, nativeURL != nil {
            primaryCTA = "Open in \(providerName)"
        } else if webURL != nil {
            primaryCTA = "View on web"
        } else {
            primaryCTA = "Unavailable"
        }

        let helperText: String
        switch state {
        case .attached, .missingArtwork:
            helperText = attachment.requiresAccount || attachment.mayRequireSubscription
                ? requiresAccountCopy
                : "Open in \(providerName)"
        case .webFallback:
            helperText = attachment.requiresAccount || attachment.mayRequireSubscription
                ? "\(requiresAccountCopy) · Web fallback"
                : "Opens on web if the app is unavailable"
        case .unavailable:
            helperText = "Music unavailable"
        }

        let accessibilityText = "Music attachment. \(attachment.title) by \(attachment.artist). \(primaryCTA)."

        return MusicAttachmentOpenRoute(
            nativeURL: nativeURL,
            webURL: webURL,
            state: state,
            primaryCTA: primaryCTA,
            helperText: helperText,
            accessibilityText: accessibilityText
        )
    }
}

struct ChurchNoteMusicAttachmentSheet: View {
    let currentAttachment: WorshipSongReference?
    let onAttach: (WorshipSongReference) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rawURL = ""
    @State private var resolvedAttachment: WorshipSongReference?
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCopy
                    providerButtons
                    pasteField

                    if isResolving {
                        MusicAttachmentComposerSkeleton()
                    } else if let resolvedAttachment {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Preview")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ComposerMusicAttachmentPreview(attachment: resolvedAttachment)

                            Button("Use Attachment") {
                                onAttach(resolvedAttachment)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.black)
                        }
                    } else if let currentAttachment {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Current attachment")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ComposerMusicAttachmentPreview(attachment: currentAttachment)

                            HStack(spacing: 10) {
                                Button("Remove music", role: .destructive) {
                                    onRemove()
                                    dismiss()
                                }
                                .buttonStyle(.bordered)

                                Spacer()
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.black.opacity(0.04))
                            )
                    }

                    honestCopy
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Attach Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attach Apple Music or Spotify")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Paste a song or album link. The note stays primary, and the music is attached as supporting context.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var providerButtons: some View {
        HStack(spacing: 10) {
            pasteButton(title: "Paste Apple Music link", expectedProvider: .appleMusic)
            pasteButton(title: "Paste Spotify link", expectedProvider: .spotify)
        }
    }

    private func pasteButton(title: String, expectedProvider: MusicProvider) -> some View {
        Button(title) {
            guard let clipboard = UIPasteboard.general.string else {
                errorMessage = MusicAttachmentValidationError.empty.errorDescription
                return
            }

            rawURL = clipboard
            do {
                let parsed = try ChurchNoteMusicURLParser.parse(clipboard)
                guard parsed.provider == expectedProvider else {
                    errorMessage = MusicAttachmentValidationError.unsupported.errorDescription
                    return
                }
                resolveAttachment()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        .buttonStyle(.bordered)
        .tint(.black)
    }

    private var pasteField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste music link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                TextField("https://music.apple.com/... or https://open.spotify.com/...", text: $rawURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15))
                    .lineLimit(2 ... 4)

                HStack {
                    Button(currentAttachment == nil ? "Attach Music" : "Replace music") {
                        resolveAttachment()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                    .disabled(isResolving)

                    if currentAttachment != nil || resolvedAttachment != nil {
                        Button("Remove music", role: .destructive) {
                            resolvedAttachment = nil
                            rawURL = ""
                            onRemove()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.62))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
    }

    private var honestCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Opening may require the provider app, login, or subscription.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Text("AMEN attaches the real destination. If the app isn’t available, the link falls back to the canonical web page.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func resolveAttachment() {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = MusicAttachmentValidationError.empty.errorDescription
            return
        }

        errorMessage = nil
        isResolving = true
        resolvedAttachment = nil

        Task {
            do {
                let attachment = try await ChurchNoteMusicAttachmentResolverService.shared.resolve(
                    urlString: value,
                    storefront: ChurchNoteMusicEnvironment.defaultStorefront
                )
                await MainActor.run {
                    resolvedAttachment = attachment
                    isResolving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "We couldn’t load that music right now. Try again or use a different link."
                    isResolving = false
                }
            }
        }
    }
}

private struct MusicAttachmentComposerSkeleton: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 150, height: 12)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 110, height: 10)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.03))
        )
        .opacity(isAnimating ? 0.62 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .accessibilityLabel("Loading music")
    }
}

private struct ComposerMusicAttachmentPreview: View {
    let attachment: WorshipSongReference

    var body: some View {
        HStack(spacing: 12) {
            MusicAttachmentArtworkView(
                artworkURL: attachment.artworkURL,
                artworkColors: attachment.artworkColors,
                size: CGSize(width: 52, height: 52),
                cornerRadius: 14
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(attachment.subtitle ?? attachment.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(attachment.provider.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.58))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
                )
        )
    }
}

struct MusicAttachmentArtworkView: View {
    let artworkURL: String?
    let artworkColors: MusicArtworkColors?
    let size: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artworkURL, let url = URL(string: artworkURL) {
                CachedAsyncImage(url: url, size: size) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.7)
        )
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fallbackGradient)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: min(size.width, size.height) * 0.34, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.68))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.32), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var fallbackGradient: LinearGradient {
        let dominant = artworkColors?.dominantHex.flatMap(Color.init(hex:)) ?? Color.black.opacity(0.07)
        let secondary = artworkColors?.secondaryHex.flatMap(Color.init(hex:)) ?? Color.white.opacity(0.92)
        return LinearGradient(
            colors: [secondary, dominant.opacity(0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
