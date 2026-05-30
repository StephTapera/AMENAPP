import Foundation
import SwiftUI

@MainActor
final class SpatialSocialViewModel: ObservableObject {
    static let shared = SpatialSocialViewModel()

    @Published private(set) var currentEnvironment: SpatialEnvironment = .unknown
    @Published private(set) var nearbyGatherings: [NearbyGathering] = []
    @Published private(set) var activeEphemeralSpaces: [EphemeralLiveSpace] = []
    @Published private(set) var ambientSignals: [AmbientSignal] = []
    @Published private(set) var topAmbientSignal: AmbientSignal?
    @Published private(set) var smartIntroductions: [SmartIntroduction] = []
    @Published private(set) var isInitializing = false
    @Published var showEphemeralSpaceCreation = false
    @Published var selectedGatheringForSpace: NearbyGathering?

    private let environmentService = EnvironmentContextService.shared
    private let gatheringService = SmartGatheringDetectionService.shared
    private let ambientController = AmbientIntelligenceController.shared
    private let relationshipService = SmartRelationshipService.shared
    private let locationService = LocationContextService.shared

    private init() {}

    func initialize() async {
        isInitializing = true
        defer { isInitializing = false }

        let location = locationService.currentContext
        if location.city.isEmpty { return }

        // Classify environment
        await environmentService.classifyEnvironment(location: location)
        currentEnvironment = environmentService.currentEnvironment

        // Detect nearby gatherings
        await gatheringService.detectNearbyGatherings(broadArea: location.broadAreaLabel)
        nearbyGatherings = gatheringService.detectedNearbyGatherings

        // Start listening for ephemeral spaces
        gatheringService.startListeningForActiveSpaces(broadArea: location.broadAreaLabel)
        activeEphemeralSpaces = gatheringService.activeEphemeralSpaces

        // Evaluate ambient signals
        ambientController.evaluate(
            environment: currentEnvironment,
            nearbyGatherings: nearbyGatherings,
            locationContext: location
        )
        ambientSignals = ambientController.activeSignals
        topAmbientSignal = ambientController.topSignal

        // Fetch smart introductions based on context
        await relationshipService.fetchSmartIntroductions(
            context: ComposerContextEngine.shared.currentContext,
            broadArea: location.broadAreaLabel
        )
        smartIntroductions = relationshipService.pendingIntroductions
    }

    func dismissAmbientSignal(_ signal: AmbientSignal) {
        ambientController.dismissSignal(id: signal.id)
        ambientSignals = ambientController.activeSignals
        topAmbientSignal = ambientController.topSignal
    }

    func createEphemeralSpace(for gathering: NearbyGathering) async {
        do {
            let space = try await gatheringService.createEphemeralSpace(for: gathering)
            activeEphemeralSpaces.insert(space, at: 0)
        } catch {
            print("[ERROR] SpatialSocialViewModel.createEphemeralSpace: \(error)")
        }
    }

    func dismissIntroduction(_ intro: SmartIntroduction) {
        relationshipService.dismissIntroduction(id: intro.id)
        smartIntroductions = relationshipService.pendingIntroductions
    }
}
