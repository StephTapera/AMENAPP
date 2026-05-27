import SwiftUI
import FirebaseFunctions

enum AmenDeepLinkDestination: Equatable {
    case organization(id: String)
    case supportGroup(id: String, inviteCode: String?)
    case wellness(id: String)
    case crisisResources
    case givingGoal(id: String)
    case post(id: String)
    case userProfile(id: String)
    case feed(context: String?)
    case unknown
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var destination: AmenDeepLinkDestination? = nil
    private let functions = Functions.functions()

    func handle(url: URL) {
        guard url.scheme == "amen" else {
            if url.host == "amen.app", let code = url.pathComponents.last {
                Task { await resolveShortLink(code: code) }
            }
            return
        }
        destination = parse(url: url)
        trackClick(url: url)
    }

    private func parse(url: URL) -> AmenDeepLinkDestination {
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch host {
        case "organization":
            guard let id = pathComponents.first else { return .unknown }
            return .organization(id: id)
        case "supportGroup":
            guard let id = pathComponents.first else { return .unknown }
            let inviteCode = queryItems.first(where: { $0.name == "inviteCode" })?.value
            return .supportGroup(id: id, inviteCode: inviteCode)
        case "wellness":
            guard let id = pathComponents.first else { return .unknown }
            return .wellness(id: id)
        case "crisis":
            return .crisisResources
        case "goal":
            guard let id = pathComponents.first else { return .unknown }
            return .givingGoal(id: id)
        case "post":
            guard let id = pathComponents.first else { return .unknown }
            return .post(id: id)
        case "user":
            guard let id = pathComponents.first else { return .unknown }
            return .userProfile(id: id)
        case "feed":
            let context = queryItems.first(where: { $0.name == "context" })?.value
            return .feed(context: context)
        default:
            return .unknown
        }
    }

    private func resolveShortLink(code: String) async {
        do {
            let result = try await functions.httpsCallable("resolveDeepLink").call(["shortCode": code])
            if let data = result.data as? [String: Any],
               let deepLinkString = data["deepLinkUrl"] as? String,
               let url = URL(string: deepLinkString) {
                destination = parse(url: url)
            }
        } catch {
            destination = .unknown
        }
    }

    private func trackClick(url: URL) {
        Task {
            _ = try? await functions.httpsCallable("trackDeepLinkClick").call(["url": url.absoluteString])
        }
    }

    func clear() { destination = nil }
}

struct DeepLinkNavigationModifier: ViewModifier {
    @ObservedObject var router: DeepLinkRouter

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in router.handle(url: url) }
            .sheet(item: Binding(
                get: { router.destination.flatMap { dest -> AmenDeepLinkSheetItem? in
                    switch dest {
                    case .crisisResources: return .crisisResources
                    case .wellness(let id): return .wellness(id: id)
                    default: return nil
                    }
                }},
                set: { if $0 == nil { router.clear() } }
            )) { item in
                switch item {
                case .crisisResources: CrisisNotificationSettingsView()
                case .wellness(let id): Text("Wellness content: \(id)").padding()
                }
            }
    }
}

enum AmenDeepLinkSheetItem: Identifiable, Equatable {
    case crisisResources
    case wellness(id: String)
    var id: String {
        switch self { case .crisisResources: return "crisis"; case .wellness(let id): return "wellness_\(id)" }
    }
}

extension View {
    func amenDeepLinkHandler(router: DeepLinkRouter) -> some View {
        modifier(DeepLinkNavigationModifier(router: router))
    }
}
