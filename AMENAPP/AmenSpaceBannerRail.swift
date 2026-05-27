import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - Models

enum AmenSpaceBannerType: String, CaseIterable, Codable, Identifiable {
    case group
    case job
    case event
    case discussion
    case prayer
    case sermon
    case school
    case business
    case announcement

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .group: return "person.2.fill"
        case .job: return "briefcase.fill"
        case .event: return "calendar"
        case .discussion: return "bubble.left.and.bubble.right.fill"
        case .prayer: return "hands.sparkles.fill"
        case .sermon: return "play.rectangle.fill"
        case .school: return "graduationcap.fill"
        case .business: return "building.2.fill"
        case .announcement: return "megaphone.fill"
        }
    }
}

enum AmenSpaceBannerSize: String, CaseIterable, Codable, Identifiable {
    case compact
    case standard
    case large
    case hero

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .large: return "Large"
        case .hero: return "Hero"
        }
    }

    var cardHeight: CGFloat {
        switch self {
        case .compact: return 148
        case .standard: return 190
        case .large: return 236
        case .hero: return 292
        }
    }

    var cardWidth: CGFloat {
        switch self {
        case .compact: return 280
        case .standard: return 318
        case .large: return 342
        case .hero: return 360
        }
    }
}

enum AmenSpaceBannerSurface: String, CaseIterable, Codable, Identifiable {
    case spacesHome
    case spaceDetail
    case churchProfile
    case schoolProfile
    case businessProfile
    case discovery
    case events
    case jobs
    case messagesRooms
    case bereanSuggestions
    case homeFeed

    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .jobs: return "OPEN ROLES"
        case .events: return "FEATURED"
        case .messagesRooms: return "ACTIVE DISCUSSIONS"
        case .discovery, .churchProfile, .schoolProfile, .businessProfile: return "NEAR YOU"
        default: return "HAPPENING NOW"
        }
    }

    var defaultSize: AmenSpaceBannerSize {
        switch self {
        case .spaceDetail, .churchProfile, .schoolProfile, .businessProfile: return .large
        case .homeFeed: return .compact
        default: return .standard
        }
    }
}

enum AmenSpaceBannerCTA: String, CaseIterable, Codable {
    case join = "Join"
    case rsvp = "RSVP"
    case apply = "Apply"
    case open = "Open"
    case pray = "Pray"
    case watch = "Watch"
}

struct AmenSpaceBannerItem: Identifiable, Hashable, Codable {
    var id: String
    var type: AmenSpaceBannerType
    var title: String
    var subtitle: String
    var imageURL: String?
    var iconURL: String?
    var spaceId: String?
    var targetRoute: String
    var ctaLabel: AmenSpaceBannerCTA
    var priority: Double
    var startsAt: Date?
    var endsAt: Date?
    var location: String?
    var moderationStatus: String
    var visibility: String
    var createdBy: String?
    var trustedContext: String?
    var rankingReason: String
    var resolvedSize: AmenSpaceBannerSize

    var accessibilitySummary: String {
        [title, subtitle, ctaLabel.rawValue, rankingReason]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Service

enum AmenSpaceBannerCallable: String, CaseIterable, Identifiable {
    case getAmenSpaceBanners
    case setAmenSpaceBannerDisplayPreference
    case setAmenSpaceDefaultBannerSize
    case logAmenSpaceBannerEvent
    case validateAmenSpaceBannerCTA

    var id: String { rawValue }
}

protocol AmenSpaceBannerServicing: AnyObject {
    func loadBanners(surface: AmenSpaceBannerSurface, spaceId: String?) async throws -> [AmenSpaceBannerItem]
    func setUserPreferredSize(_ size: AmenSpaceBannerSize, surface: AmenSpaceBannerSurface) async throws
    func dismissBanner(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async throws
    func recordImpression(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async
    func validateCTA(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async throws -> URL?
}

final class AmenSpaceBannerService: AmenSpaceBannerServicing {
    private lazy var functions = Functions.functions()

    static let callableContracts = AmenSpaceBannerCallable.allCases

    func loadBanners(surface: AmenSpaceBannerSurface, spaceId: String?) async throws -> [AmenSpaceBannerItem] {
        guard Auth.auth().currentUser != nil else { return [] }
        var payload: [String: Any] = [
            "surface": surface.rawValue,
            "surfaceDefaultSize": surface.defaultSize.rawValue
        ]
        if let spaceId { payload["spaceId"] = spaceId }
        let result = try await functions.httpsCallable(AmenSpaceBannerCallable.getAmenSpaceBanners.rawValue).call(payload)
        guard let dict = result.data as? [String: Any], let rawItems = dict["items"] as? [[String: Any]] else { return [] }
        return rawItems.compactMap(Self.item(from:))
    }

    func setUserPreferredSize(_ size: AmenSpaceBannerSize, surface: AmenSpaceBannerSurface) async throws {
        guard Auth.auth().currentUser != nil else { throw URLError(.userAuthenticationRequired) }
        try await functions.httpsCallable(AmenSpaceBannerCallable.setAmenSpaceBannerDisplayPreference.rawValue).call([
            "surface": surface.rawValue,
            "bannerSize": size.rawValue
        ])
    }

    func dismissBanner(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async throws {
        try await functions.httpsCallable(AmenSpaceBannerCallable.logAmenSpaceBannerEvent.rawValue).call([
            "bannerId": banner.id,
            "surface": surface.rawValue,
            "eventName": "banner_dismiss"
        ])
    }

    func recordImpression(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async {
        guard Auth.auth().currentUser != nil else { return }
        try? await functions.httpsCallable(AmenSpaceBannerCallable.logAmenSpaceBannerEvent.rawValue).call([
            "bannerId": banner.id,
            "surface": surface.rawValue,
            "eventName": "banner_impression"
        ])
    }

    func validateCTA(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async throws -> URL? {
        guard Auth.auth().currentUser != nil else { throw URLError(.userAuthenticationRequired) }
        let result = try await functions.httpsCallable(AmenSpaceBannerCallable.validateAmenSpaceBannerCTA.rawValue).call([
            "bannerId": banner.id,
            "surface": surface.rawValue,
            "targetRoute": banner.targetRoute,
            "ctaLabel": banner.ctaLabel.rawValue
        ])
        guard let dict = result.data as? [String: Any], let route = dict["targetRoute"] as? String else { return URL(string: banner.targetRoute) }
        return URL(string: route)
    }

    private static func item(from data: [String: Any]) -> AmenSpaceBannerItem? {
        let id = string(data, "id")
        let title = string(data, "title")
        let targetRoute = string(data, "targetRoute")
        guard !id.isEmpty, !title.isEmpty, !targetRoute.isEmpty else { return nil }
        return AmenSpaceBannerItem(
            id: id,
            type: AmenSpaceBannerType(rawValue: string(data, "type", "announcement")) ?? .announcement,
            title: title,
            subtitle: string(data, "subtitle"),
            imageURL: data["imageURL"] as? String,
            iconURL: data["iconURL"] as? String,
            spaceId: data["spaceId"] as? String,
            targetRoute: targetRoute,
            ctaLabel: AmenSpaceBannerCTA(rawValue: string(data, "ctaLabel", "Open")) ?? .open,
            priority: double(data, "priority"),
            startsAt: date(data, "startsAt"),
            endsAt: date(data, "endsAt"),
            location: data["location"] as? String,
            moderationStatus: string(data, "moderationStatus", "approved"),
            visibility: string(data, "visibility", "authenticated"),
            createdBy: data["createdBy"] as? String,
            trustedContext: data["trustedContext"] as? String,
            rankingReason: string(data, "rankingReason"),
            resolvedSize: AmenSpaceBannerSize(rawValue: string(data, "resolvedSize", "standard")) ?? .standard
        )
    }

    private static func string(_ data: [String: Any], _ key: String, _ fallback: String = "") -> String {
        data[key] as? String ?? fallback
    }

    private static func double(_ data: [String: Any], _ key: String) -> Double {
        if let value = data[key] as? Double { return value }
        if let value = data[key] as? NSNumber { return value.doubleValue }
        return 0
    }

    private static func date(_ data: [String: Any], _ key: String) -> Date? {
        if let value = data[key] as? TimeInterval { return Date(timeIntervalSince1970: value) }
        if let value = data[key] as? NSNumber { return Date(timeIntervalSince1970: value.doubleValue) }
        return nil
    }
}

// MARK: - View Model

@MainActor
final class AmenSpaceBannerRailViewModel: ObservableObject {
    @Published private(set) var items: [AmenSpaceBannerItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSize: AmenSpaceBannerSize

    private let surface: AmenSpaceBannerSurface
    private let spaceId: String?
    private let service: AmenSpaceBannerServicing
    private var dismissedIds: Set<String> = []

    init(surface: AmenSpaceBannerSurface, spaceId: String? = nil, service: AmenSpaceBannerServicing = AmenSpaceBannerService()) {
        self.surface = surface
        self.spaceId = spaceId
        self.service = service
        self.selectedSize = surface.defaultSize
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await service.loadBanners(surface: surface, spaceId: spaceId)
            items = Self.deduplicated(loaded).filter { !dismissedIds.contains($0.id) }
            selectedSize = items.first?.resolvedSize ?? selectedSize
        } catch {
            errorMessage = "Featured banners are unavailable."
        }
        isLoading = false
    }

    func setSize(_ size: AmenSpaceBannerSize) {
        selectedSize = size
        Task {
            try? await service.setUserPreferredSize(size, surface: surface)
            await load()
        }
    }

    func dismiss(_ item: AmenSpaceBannerItem) {
        dismissedIds.insert(item.id)
        items.removeAll { $0.id == item.id }
        Task { try? await service.dismissBanner(item, surface: surface) }
    }

    func recordImpression(_ item: AmenSpaceBannerItem) {
        Task { await service.recordImpression(item, surface: surface) }
    }

    func route(for item: AmenSpaceBannerItem) async -> URL? {
        do {
            return try await service.validateCTA(item, surface: surface)
        } catch {
            await MainActor.run { errorMessage = "That banner is no longer available." }
            return nil
        }
    }

    static func deduplicated(_ items: [AmenSpaceBannerItem]) -> [AmenSpaceBannerItem] {
        var seenRoutes = Set<String>()
        return items.filter { item in
            guard !seenRoutes.contains(item.targetRoute) else { return false }
            seenRoutes.insert(item.targetRoute)
            return true
        }
    }
}

// MARK: - Views

struct AmenSpaceBannerRail: View {
    let surface: AmenSpaceBannerSurface
    let title: String?
    @StateObject private var viewModel: AmenSpaceBannerRailViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(surface: AmenSpaceBannerSurface, spaceId: String? = nil, title: String? = nil) {
        self.surface = surface
        self.title = title
        _viewModel = StateObject(wrappedValue: AmenSpaceBannerRailViewModel(surface: surface, spaceId: spaceId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 20)

            content
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(surface.eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.blue)
                Text(title ?? "Featured in Amen Spaces")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(AmenSpaceBannerSize.allCases) { size in
                    Button(size.displayName) { viewModel.setSize(size) }
                }
            } label: {
                Image(systemName: "rectangle.resize")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.7))
            }
            .accessibilityLabel("Banner size")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            AmenSpaceBannerLoadingCard(size: viewModel.selectedSize)
                .padding(.horizontal, 20)
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            AmenSpaceBannerUnavailableCard(message: error)
                .padding(.horizontal, 20)
        } else if !viewModel.items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.items) { item in
                        AmenSpaceBannerCard(
                            item: item,
                            size: viewModel.selectedSize,
                            reduceMotion: reduceMotion,
                            onDismiss: { viewModel.dismiss(item) },
                            onTap: { Task { await open(item) } }
                        )
                        .onAppear { viewModel.recordImpression(item) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }

    private func open(_ item: AmenSpaceBannerItem) async {
        guard let url = await viewModel.route(for: item) else { return }
        await MainActor.run { openURL(url) }
    }
}

private struct AmenSpaceBannerCard: View {
    let item: AmenSpaceBannerItem
    let size: AmenSpaceBannerSize
    let reduceMotion: Bool
    let onDismiss: () -> Void
    let onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                media

                LinearGradient(
                    colors: [.clear, .black.opacity(0.56)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(alignment: .center, spacing: 10) {
                    icon

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(size == .compact ? 1 : 2)
                            .minimumScaleFactor(0.82)
                        Text(item.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(size == .hero ? 2 : 1)
                            .minimumScaleFactor(0.84)
                        if !item.rankingReason.isEmpty && size != .compact {
                            Text(item.rankingReason)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)

                    Text(item.ctaLabel.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Color.white, in: Capsule())
                }
                .padding(12)
                .background(metadataBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(contrast == .increased ? 0.5 : 0.28), lineWidth: 0.7))
                .padding(10)
            }
            .frame(width: min(size.cardWidth, UIScreen.main.bounds.width - 40), height: size.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("Dismiss banner")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilitySummary)
        .accessibilityHint("Opens \(item.ctaLabel.rawValue.lowercased()) action")
    }

    @ViewBuilder
    private var media: some View {
        if let imageURL = item.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.white, Color.blue.opacity(0.18), Color.black.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Image(systemName: item.type.systemImage)
                .font(.system(size: size == .compact ? 34 : 48, weight: .semibold))
                .foregroundStyle(Color.blue.opacity(0.85))
                .padding(18)
        }
    }

    private var icon: some View {
        Group {
            if let iconURL = item.iconURL, let url = URL(string: iconURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Image(systemName: item.type.systemImage).foregroundStyle(.white)
                    }
                }
            } else {
                Image(systemName: item.type.systemImage)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 34, height: 34)
        .background(Color.black.opacity(0.22), in: Circle())
        .clipShape(Circle())
    }

    private var metadataBackground: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.black.opacity(0.82)) : AnyShapeStyle(.ultraThinMaterial)
    }
}

private struct AmenSpaceBannerLoadingCard: View {
    let size: AmenSpaceBannerSize

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.black.opacity(0.06))
            .frame(height: size.cardHeight)
            .overlay(ProgressView().tint(Color.blue))
            .accessibilityLabel("Loading featured banners")
    }
}

private struct AmenSpaceBannerUnavailableCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .foregroundStyle(Color.blue)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.7))
    }
}
