import Foundation
import CoreLocation
import FirebaseFunctions

// Detects the physical environment (airport, conference, campus, etc.) and
// publishes surface adaptation hints. Uses fuzzy location classification,
// not precise tracking.
@MainActor
final class EnvironmentContextService: ObservableObject {
    static let shared = EnvironmentContextService()

    @Published private(set) var currentEnvironment: SpatialEnvironment = .unknown
    @Published private(set) var suggestedAdaptations: EnvironmentSurfaceAdaptation = EnvironmentSurfaceAdaptation(
        showLocalRecs: false, enableQuietMode: false, showNearbyEvents: false, showChurchDiscovery: false
    )

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    func classifyEnvironment(location: LocationContext, placeName: String? = nil) async {
        guard AmenAIConsentStore.shared.hasFabricConsent(for: .personalization) else { return }
        let type = await classify(location: location, placeName: placeName)
        let env = SpatialEnvironment(
            type: type,
            broadArea: location.broadAreaLabel,
            isNew: location.isNewArea,
            detectedAt: Date(),
            confidence: confidenceForType(type),
            suggestedAdaptations: type.surfaceAdaptation
        )
        currentEnvironment = env
        suggestedAdaptations = type.surfaceAdaptation
    }

    private func classify(location: LocationContext, placeName: String?) async -> EnvironmentType {
        // Use local heuristics first (no network call needed for basics)
        if let placeName {
            let lower = placeName.lowercased()
            if lower.contains("airport") || lower.contains("terminal") || lower.contains("concourse") { return .airport }
            if lower.contains("university") || lower.contains("college") || lower.contains("campus") { return .campus }
            if lower.contains("convention") || lower.contains("conference") || lower.contains("expo") { return .conference }
            if lower.contains("stadium") || lower.contains("arena") || lower.contains("ballpark") { return .stadium }
            if lower.contains("hospital") || lower.contains("medical") || lower.contains("clinic") { return .hospital }
            if lower.contains("church") || lower.contains("chapel") || lower.contains("cathedral") { return .church }
            if lower.contains("cowork") || lower.contains("wework") || lower.contains("office") { return .coworking }
        }

        // International detection from location context
        if location.country != "US" && !location.country.isEmpty {
            return .international
        }

        // Try AI classification for ambiguous cases
        if !location.city.isEmpty {
            do {
                let result = try await functions.httpsCallable("classifyEnvironment").call([
                    "city": location.city,
                    "state": location.state,
                    "country": location.country
                ])
                if let data = result.data as? [String: Any],
                   let typeString = data["environmentType"] as? String,
                   let envType = EnvironmentType(rawValue: typeString) {
                    return envType
                }
            } catch {
                    print("[ERROR] EnvironmentContextService.classify: AI environment classification failed — \(error)")
                }
        }

        return .unknown
    }

    private func confidenceForType(_ type: EnvironmentType) -> Double {
        switch type {
        case .airport, .campus, .conference, .stadium: return 0.85
        case .hospital, .church: return 0.80
        case .international: return 0.95
        case .coworking: return 0.70
        case .home: return 0.60
        case .unknown: return 0.30
        }
    }
}
