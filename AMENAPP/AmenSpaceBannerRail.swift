import SwiftUI
import UIKit
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
    case userProfile

    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .jobs: return "OPEN ROLES"
        case .events: return "FEATURED"
        case .messagesRooms: return "ACTIVE DISCUSSIONS"
        case .discovery, .churchProfile, .schoolProfile, .businessProfile: return "NEAR YOU"
        case .userProfile: return "FEATURED"
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

    var actionValue: String {
        switch self {
        case .join: return "join"
        case .rsvp: return "rsvp"
        case .apply: return "apply"
        case .open: return "open"
        case .pray: return "pray"
        case .watch: return "watch"
        }
    }

    init?(actionValue: String) {
        switch actionValue {
        case "join": self = .join
        case "rsvp": self = .rsvp
        case "apply": self = .apply
        case "open": self = .open
        case "pray": self = .pray
        case "watch": self = .watch
        default: return nil
        }
    }
}

enum AmenSpaceBannerAnalyticsEvent: String, CaseIterable, Codable {
    case impression = "banner_impression"
    case tap = "banner_tap"
    case dismiss = "banner_dismiss"
    case ctaComplete = "banner_cta_complete"
    case hiddenReason = "banner_hidden_reason"
}

struct AmenSpaceBannerItem: Identifiable, Hashable, Codable {
    var id: String
    var sourceId: String = ""
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
    var rank: Int = 0
    var score: Double = 0

    var accessibilitySummary: String {
        [title, subtitle, ctaLabel.rawValue, rankingReason]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

enum AmenSpaceBannerRoute: Equatable, Hashable {
    case joinGroup(id: String)
    case rsvpEvent(id: String)
    case applyJob(id: String)
    case openSpace(id: String)
    case pray(id: String)
    case watchSermon(id: String)

    var completionSource: String {
        switch self {
        case .joinGroup: return "group_join"
        case .rsvpEvent: return "event_rsvp"
        case .applyJob: return "job_apply"
        case .openSpace: return "space_open"
        case .pray: return "prayer"
        case .watchSermon: return "sermon_watch"
        }
    }

    var entityId: String {
        switch self {
        case .joinGroup(let id), .rsvpEvent(let id), .applyJob(let id), .openSpace(let id), .pray(let id), .watchSermon(let id):
            return id
        }
    }

    var completionKey: String {
        "\(completionSource):\(entityId)"
    }

    init?(route: String, cta: AmenSpaceBannerCTA) {
        guard
            let components = URLComponents(string: route),
            components.scheme == "selah",
            components.query == nil,
            components.fragment == nil,
            let host = components.host
        else { return nil }

        let parts = components.path.split(separator: "/").map(String.init)
        guard let id = parts.first, Self.isValidIdentifier(id) else { return nil }

        switch (cta, host, parts) {
        case (.join, "group", [id]):
            self = .joinGroup(id: id)
        case (.rsvp, "event", [id, "rsvp"]):
            self = .rsvpEvent(id: id)
        case (.apply, "job", [id, "apply"]):
            self = .applyJob(id: id)
        case (.open, "space", [id]):
            self = .openSpace(id: id)
        case (.pray, "prayer", [id]):
            self = .pray(id: id)
        case (.watch, "sermon", [id]):
            self = .watchSermon(id: id)
        default:
            return nil
        }
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }
}

@MainActor
final class AmenSpaceBannerCTACompletionCenter {
    static let shared = AmenSpaceBannerCTACompletionCenter()

    private struct PendingCompletion {
        let item: AmenSpaceBannerItem
        let surface: AmenSpaceBannerSurface
        let service: AmenSpaceBannerServicing
    }

    private var pending: [String: PendingCompletion] = [:]

    private init() {}

    func begin(item: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface, service: AmenSpaceBannerServicing, route: AmenSpaceBannerRoute) {
        pending[route.completionKey] = PendingCompletion(item: item, surface: surface, service: service)
    }

    func complete(route: AmenSpaceBannerRoute) {
        complete(completionSource: route.completionSource, entityId: route.entityId)
    }

    func complete(completionSource: String, entityId: String) {
        let key = "\(completionSource):\(entityId)"
        guard let completion = pending.removeValue(forKey: key) else { return }
        Task {
            await completion.service.recordEvent(.ctaComplete, banner: completion.item, surface: completion.surface, detail: completionSource)
        }
    }

    static func completeEventRSVP(eventId: String) {
        shared.complete(completionSource: "event_rsvp", entityId: eventId)
    }

    static func completeJobApply(jobId: String) {
        shared.complete(completionSource: "job_apply", entityId: jobId)
    }
}

@MainActor
enum AmenSpaceBannerRouteOpener {
    static func open(_ route: AmenSpaceBannerRoute) {
        switch route {
        case .joinGroup(let id), .openSpace(let id):
            NotificationDeepLinkRouter.shared.navigate(to: .groupDetail(groupId: id))
        case .rsvpEvent(let id):
            NotificationDeepLinkRouter.shared.navigate(to: .event(eventId: id))
        case .applyJob(let id):
            NotificationDeepLinkRouter.shared.navigate(to: .job(jobId: id))
        case .pray(let id):
            NotificationDeepLinkRouter.shared.navigate(to: .prayer(prayerId: id))
        case .watchSermon(let id):
            NotificationDeepLinkRouter.shared.navigate(to: .churchNote(noteId: id))
        }
    }
}

// MARK: - Service

enum AmenSpaceBannerCallable: String, CaseIterable, Identifiable {
    case resolveBannerRail
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
    func setSpaceDefaultSize(_ size: AmenSpaceBannerSize, spaceId: String) async throws
    func dismissBanner(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async throws
    func recordImpression(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async
    func recordEvent(_ event: AmenSpaceBannerAnalyticsEvent, banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface, detail: String?) async
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
        let result = try await functions.httpsCallable(AmenSpaceBannerCallable.resolveBannerRail.rawValue).call(payload)
        guard let dict = result.data as? [String: Any] else { return [] }
        let rawItems = (dict["banners"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) ?? []
        return rawItems.compactMap(Self.item(from:))
    }

    func setUserPreferredSize(_ size: AmenSpaceBannerSize, surface: AmenSpaceBannerSurface) async throws {
        guard Auth.auth().currentUser != nil else { throw URLError(.userAuthenticationRequired) }
        _ = try await functions.httpsCallable(AmenSpaceBannerCallable.setAmenSpaceBannerDisplayPreference.rawValue).call([
            "surface": surface.rawValue,
            "bannerSize": size.rawValue
        ])
    }

    func setSpaceDefaultSize(_ size: AmenSpaceBannerSize, spaceId: String) async throws {
        guard Auth.auth().currentUser != nil else { throw URLError(.userAuthenticationRequired) }
        _ = try await functions.httpsCallable(AmenSpaceBannerCallable.setAmenSpaceDefaultBannerSize.rawValue).call([
            "spaceId": spaceId,
            "defaultBannerSize": size.rawValue
        ])
    }

    func dismissBanner(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async throws {
        await recordEvent(.dismiss, banner: banner, surface: surface, detail: nil)
    }

    func recordImpression(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async {
        guard Auth.auth().currentUser != nil else { return }
        await recordEvent(.impression, banner: banner, surface: surface, detail: nil)
    }

    func recordEvent(_ event: AmenSpaceBannerAnalyticsEvent, banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface, detail: String? = nil) async {
        guard Auth.auth().currentUser != nil else { return }
        var payload: [String: Any] = [
            "bannerId": banner.id,
            "sourceId": banner.sourceId.isEmpty ? banner.id : banner.sourceId,
            "surface": surface.rawValue,
            "spaceId": banner.spaceId ?? "",
            "route": banner.targetRoute,
            "targetRoute": banner.targetRoute,
            "resolvedSize": banner.resolvedSize.rawValue,
            "ctaAction": banner.ctaLabel.actionValue,
            "ctaLabel": banner.ctaLabel.rawValue,
            "eventName": event.rawValue,
            "rank": banner.rank
        ]
        if let detail, !detail.isEmpty {
            payload["detail"] = detail
            if event == .hiddenReason {
                payload["reason"] = detail
                payload["stage"] = "client_route_validation"
            }
        }
        _ = try? await functions.httpsCallable(AmenSpaceBannerCallable.logAmenSpaceBannerEvent.rawValue).call(payload)
    }

    func validateCTA(_ banner: AmenSpaceBannerItem, surface: AmenSpaceBannerSurface) async throws -> URL? {
        guard Auth.auth().currentUser != nil else { throw URLError(.userAuthenticationRequired) }
        let result = try await functions.httpsCallable(AmenSpaceBannerCallable.validateAmenSpaceBannerCTA.rawValue).call([
            "bannerId": banner.id,
            "surface": surface.rawValue,
            "route": banner.targetRoute,
            "targetRoute": banner.targetRoute,
            "ctaAction": banner.ctaLabel.actionValue,
            "ctaLabel": banner.ctaLabel.rawValue
        ])
        guard let dict = result.data as? [String: Any] else { return URL(string: banner.targetRoute) }
        let route = (dict["route"] as? String) ?? (dict["targetRoute"] as? String) ?? banner.targetRoute
        return URL(string: route)
    }

    private static func item(from data: [String: Any]) -> AmenSpaceBannerItem? {
        let id = string(data, "id")
        let title = string(data, "title")
        let cta = data["cta"] as? [String: Any]
        let ctaAction = string(cta ?? [:], "action")
        let targetRoute = string(cta ?? [:], "route", string(data, "targetRoute"))
        guard !id.isEmpty, !title.isEmpty, !targetRoute.isEmpty else { return nil }
        let ctaLabel = AmenSpaceBannerCTA(actionValue: ctaAction)
            ?? AmenSpaceBannerCTA(rawValue: string(cta ?? [:], "label", string(data, "ctaLabel", "Open")))
            ?? .open
        return AmenSpaceBannerItem(
            id: id,
            sourceId: string(data, "sourceId", id),
            type: AmenSpaceBannerType(rawValue: string(data, "type", "announcement")) ?? .announcement,
            title: title,
            subtitle: string(data, "subtitle"),
            imageURL: data["imageURL"] as? String,
            iconURL: data["iconURL"] as? String,
            spaceId: data["spaceId"] as? String,
            targetRoute: targetRoute,
            ctaLabel: ctaLabel,
            priority: double(data, "priority"),
            startsAt: date(data, "startsAt"),
            endsAt: date(data, "endsAt"),
            location: data["location"] as? String,
            moderationStatus: string(data, "moderationStatus", "approved"),
            visibility: string(data, "visibility", "authenticated"),
            createdBy: data["createdBy"] as? String,
            trustedContext: data["trustedContext"] as? String,
            rankingReason: string(data, "rankingReason"),
            resolvedSize: AmenSpaceBannerSize(rawValue: string(data, "resolvedSize", "standard")) ?? .standard,
            rank: int(data, "rank"),
            score: double(data, "score")
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

    private static func int(_ data: [String: Any], _ key: String) -> Int {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? NSNumber { return value.intValue }
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
    private var recordedImpressionIds: Set<String> = []

    var shouldRender: Bool {
        AMENFeatureFlags.shared.bannerRailEnabled && (isLoading || errorMessage != nil || !items.isEmpty)
    }

    init(surface: AmenSpaceBannerSurface, spaceId: String? = nil, service: AmenSpaceBannerServicing? = nil) {
        self.surface = surface
        self.spaceId = spaceId
        self.service = service ?? AmenSpaceBannerService()
        self.selectedSize = Self.storedUserPreferredSize(surface: surface) ?? surface.defaultSize
    }

    func load() async {
        guard AMENFeatureFlags.shared.bannerRailEnabled else {
            items = []
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await service.loadBanners(surface: surface, spaceId: spaceId)
            let renderable = await filterRenderableRoutes(Self.deduplicated(loaded))
            items = renderable.filter { !dismissedIds.contains($0.id) }
            selectedSize = Self.resolvedSize(
                userPreference: Self.storedUserPreferredSize(surface: surface),
                serverResolvedSize: items.first?.resolvedSize,
                surfaceDefault: surface.defaultSize
            )
            if items.isEmpty {
                await recordHiddenReason("empty_ranked_payload")
            }
        } catch {
            errorMessage = "Featured banners are unavailable."
            await recordHiddenReason("load_failed")
        }
        isLoading = false
    }

    func setSize(_ size: AmenSpaceBannerSize) {
        selectedSize = size
        Self.storeUserPreferredSize(size, surface: surface)
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
        guard !recordedImpressionIds.contains(item.id) else { return }
        recordedImpressionIds.insert(item.id)
        Task { await service.recordImpression(item, surface: surface) }
    }

    func route(for item: AmenSpaceBannerItem) async -> URL? {
        guard let parsedRoute = AmenSpaceBannerRoute(route: item.targetRoute, cta: item.ctaLabel) else {
            await service.recordEvent(.hiddenReason, banner: item, surface: surface, detail: "unresolvable_route")
            return nil
        }
        await service.recordEvent(.tap, banner: item, surface: surface, detail: nil)
        do {
            let url = try await service.validateCTA(item, surface: surface)
            await MainActor.run {
                AmenSpaceBannerCTACompletionCenter.shared.begin(item: item, surface: surface, service: service, route: parsedRoute)
            }
            return url
        } catch {
            await MainActor.run { errorMessage = "That banner is no longer available." }
            await service.recordEvent(.hiddenReason, banner: item, surface: surface, detail: "cta_validation_failed")
            return nil
        }
    }

    func recordCTAComplete(_ item: AmenSpaceBannerItem, route: AmenSpaceBannerRoute) {
        Task {
            await service.recordEvent(.ctaComplete, banner: item, surface: surface, detail: route.completionSource)
        }
    }

    nonisolated static func deduplicated(_ items: [AmenSpaceBannerItem]) -> [AmenSpaceBannerItem] {
        var seenRoutes = Set<String>()
        return items.filter { item in
            guard !seenRoutes.contains(item.targetRoute) else { return false }
            seenRoutes.insert(item.targetRoute)
            return true
        }
    }

    nonisolated static func resolvedSize(
        userPreference: AmenSpaceBannerSize?,
        serverResolvedSize: AmenSpaceBannerSize?,
        surfaceDefault: AmenSpaceBannerSize
    ) -> AmenSpaceBannerSize {
        userPreference ?? serverResolvedSize ?? surfaceDefault
    }

    private static func storedUserPreferredSize(surface: AmenSpaceBannerSurface) -> AmenSpaceBannerSize? {
        let key = storageKey(surface: surface)
        guard let rawValue = UserDefaults.standard.string(forKey: key) else { return nil }
        return AmenSpaceBannerSize(rawValue: rawValue)
    }

    private static func storeUserPreferredSize(_ size: AmenSpaceBannerSize, surface: AmenSpaceBannerSurface) {
        UserDefaults.standard.set(size.rawValue, forKey: storageKey(surface: surface))
    }

    private static func storageKey(surface: AmenSpaceBannerSurface) -> String {
        "amen.spaceBanner.userPreferredSize.\(surface.rawValue)"
    }

    private func recordHiddenReason(_ reason: String) async {
        let placeholder = AmenSpaceBannerItem(
            id: "hidden-\(surface.rawValue)",
            sourceId: "unknown",
            type: .announcement,
            title: "Hidden banner rail",
            subtitle: "",
            imageURL: nil,
            iconURL: nil,
            spaceId: spaceId,
            targetRoute: "amen://spaces",
            ctaLabel: .open,
            priority: 0,
            startsAt: nil,
            endsAt: nil,
            location: nil,
            moderationStatus: "approved",
            visibility: "authenticated",
            createdBy: nil,
            trustedContext: nil,
            rankingReason: reason,
            resolvedSize: selectedSize
        )
        await service.recordEvent(.hiddenReason, banner: placeholder, surface: surface, detail: reason)
    }

    private func filterRenderableRoutes(_ loaded: [AmenSpaceBannerItem]) async -> [AmenSpaceBannerItem] {
        var renderable: [AmenSpaceBannerItem] = []
        for item in loaded {
            if AmenSpaceBannerRoute(route: item.targetRoute, cta: item.ctaLabel) != nil {
                renderable.append(item)
            } else {
                await service.recordEvent(.hiddenReason, banner: item, surface: surface, detail: "unresolvable_route")
            }
        }
        return renderable
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
        Group {
            if viewModel.shouldRender {
                VStack(alignment: .leading, spacing: 12) {
                    header
                        .padding(.horizontal, 20)

                    content
                }
            }
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
                        .background {
                            AmenSpaceBannerVisibilityReporter {
                                viewModel.recordImpression(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
    }

    private func open(_ item: AmenSpaceBannerItem) async {
        // validateCTA via server + record tap event — returns nil on failure
        guard await viewModel.route(for: item) != nil,
              let route = AmenSpaceBannerRoute(route: item.targetRoute, cta: item.ctaLabel)
        else { return }

        // Route to existing in-app flows via BannerRouter.
        // completion fires banner_cta_complete only on confirmed success.
        let vm = viewModel
        await MainActor.run {
            BannerRouter.shared.navigate(to: route, item: item) { success in
                guard success else { return }
                Task { @MainActor in vm.recordCTAComplete(item, route: route) }
            }
        }
    }
}

private struct AmenSpaceBannerVisibilityReporter: View {
    let onVisible: () -> Void
    @State private var didReport = false
    @State private var pendingTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { evaluate(proxy) }
                .onChange(of: proxy.frame(in: .global)) { _, _ in evaluate(proxy) }
                .onDisappear {
                    pendingTask?.cancel()
                    pendingTask = nil
                }
        }
        .allowsHitTesting(false)
    }

    private func evaluate(_ proxy: GeometryProxy) {
        guard !didReport else { return }
        let frame = proxy.frame(in: .global)
        guard frame.width > 0 else { return }
        let screenWidth = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first ?? 390
        let visibleWidth = max(0, min(frame.maxX, screenWidth) - max(frame.minX, 0))
        let visibleRatio = visibleWidth / frame.width
        if visibleRatio >= 0.5 {
            guard pendingTask == nil else { return }
            pendingTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                didReport = true
                onVisible()
            }
        } else {
            pendingTask?.cancel()
            pendingTask = nil
        }
    }
}

struct AmenSpaceBannerAdminSizePicker: View {
    let spaceId: String
    @State private var selectedSize: AmenSpaceBannerSize
    @State private var isSaving = false
    @State private var saveFailed = false
    private let service: AmenSpaceBannerServicing

    init(spaceId: String, defaultSize: AmenSpaceBannerSize = .standard, service: AmenSpaceBannerServicing? = nil) {
        self.spaceId = spaceId
        self.service = service ?? AmenSpaceBannerService()
        _selectedSize = State(initialValue: defaultSize)
    }

    var body: some View {
        Picker("Default banner size", selection: $selectedSize) {
            ForEach(AmenSpaceBannerSize.allCases) { size in
                Text(size.displayName).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isSaving)
        .onChange(of: selectedSize) { _, newValue in
            Task { await save(newValue) }
        }
        .accessibilityHint("Sets the default editorial banner size for this Space. User display preferences still override this default.")
        .overlay(alignment: .trailing) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }
        }
        .alert("Could not save banner size", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your admin access and try again.")
        }
    }

    @MainActor
    private func save(_ size: AmenSpaceBannerSize) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.setSpaceDefaultSize(size, spaceId: spaceId)
        } catch {
            saveFailed = true
        }
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
            .frame(width: size.cardWidth, height: size.cardHeight)
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
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.7))
    }
}
