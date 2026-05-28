// SpaceCreationViewModel.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// @MainActor view model driving the 4-step Liquid Glass creation wizard.
// Step machine: .intent → .scaffold → .access → .confirm
//
// AI scaffolding routes through Firebase Callable `scaffoldSpaceWithBerean`.
// Fee math delegates entirely to SpacesFeeCalculatorE — never recomputed here.
// No Combine. Async/await only. No hard-deletes.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - SpaceBereanScaffold

/// Structured scaffold returned by the `scaffoldSpaceWithBerean` callable.
struct SpaceBereanScaffold: Codable, Equatable {
    /// Berean-generated description for the Space.
    var description: String
    /// Passage references — present for bibleStudy type only.
    var passageRefs: [String]?
    /// Cadence suggestion, e.g. "5-week study" or "weekly meeting".
    var cadenceSuggestion: String?
    /// Always 3 discussion prompts.
    var discussionPrompts: [String]
    /// Optional alternative title if Berean suggests one.
    var suggestedTitle: String?
}

// MARK: - SpaceCreationViewModel

@MainActor
final class SpaceCreationViewModel: ObservableObject {

    // MARK: - Step enum

    enum WizardStep: CaseIterable {
        case intent, scaffold, access, confirm
    }

    // MARK: - Step 1: Intent

    @Published var currentStep: WizardStep = .intent
    @Published var selectedType: AmenSpace.SpaceType? = nil   // nil = not yet chosen
    @Published var title: String = ""

    // MARK: - Step 2: Scaffold

    @Published var scaffold: SpaceBereanScaffold? = nil
    @Published var isScaffolding: Bool = false
    @Published var scaffoldError: Error? = nil

    // MARK: - Step 3: Access

    @Published var accessPolicy: AmenSpace.AccessPolicy = .free
    @Published var amountCents: Int = 0
    @Published var selectedInterval: String? = nil   // "monthly" | "yearly" | "weekly"

    // MARK: - Step 4: Confirm / Create

    @Published var isCreating: Bool = false
    @Published var createError: Error? = nil
    @Published var createdSpaceId: String? = nil

    // MARK: - Private

    private let functions = Functions.functions()

    // MARK: - Computed: Validation

    /// Returns true when the current step's required fields are filled.
    var isCurrentStepValid: Bool {
        switch currentStep {
        case .intent:
            guard selectedType != nil else { return false }
            return title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        case .scaffold:
            return scaffold != nil
        case .access:
            switch accessPolicy {
            case .free:
                return true
            case .oneTime, .recurring:
                return amountCents >= 100
            }
        case .confirm:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && selectedType != nil
        }
    }

    /// True when the step is valid AND no async operation is running.
    var canAdvance: Bool {
        isCurrentStepValid && !isScaffolding && !isCreating
    }

    // MARK: - Computed: Fee preview

    /// Live fee preview string using SpacesFeeCalculatorE. Empty when free.
    var feePreviewString: String {
        guard accessPolicy != .free, amountCents >= 100 else { return "" }
        return SpacesFeeCalculatorE.feePreviewString(grossCents: amountCents, currency: "usd")
    }

    // MARK: - Navigation

    /// Validate + advance to next step. On .intent, fires requestScaffold() after advancing.
    func advance() {
        guard isCurrentStepValid else { return }
        switch currentStep {
        case .intent:
            currentStep = .scaffold
            Task { await requestScaffold() }
        case .scaffold:
            currentStep = .access
        case .access:
            currentStep = .confirm
        case .confirm:
            break   // caller drives createSpace(communityId:)
        }
    }

    /// Step back. Clears scaffold when retreating from .scaffold to .intent.
    func back() {
        switch currentStep {
        case .intent:
            break
        case .scaffold:
            scaffold = nil
            scaffoldError = nil
            currentStep = .intent
        case .access:
            currentStep = .scaffold
        case .confirm:
            currentStep = .access
        }
    }

    // MARK: - Berean scaffold

    /// Calls `scaffoldSpaceWithBerean` Firebase callable.
    func requestScaffold() async {
        guard let type = selectedType else { return }
        guard !isScaffolding else { return }

        isScaffolding = true
        scaffold = nil
        scaffoldError = nil

        let payload: [String: Any] = [
            "type": spaceTypeRawValue(type),
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        do {
            let result = try await functions
                .httpsCallable("scaffoldSpaceWithBerean")
                .call(payload)

            guard let data = result.data as? [String: Any] else {
                throw SpaceCreationError.invalidScaffoldResponse
            }

            let built = SpaceBereanScaffold(
                description: data["description"] as? String ?? "",
                passageRefs: data["passageRefs"] as? [String],
                cadenceSuggestion: data["cadenceSuggestion"] as? String,
                discussionPrompts: data["discussionPrompts"] as? [String] ?? [],
                suggestedTitle: data["suggestedTitle"] as? String
            )
            scaffold = built
        } catch {
            scaffoldError = error
        }

        isScaffolding = false
    }

    // MARK: - Create Space

    /// Calls `SpacesService.shared.createSpace(...)`.
    /// On error: sets `createError` — does NOT dismiss the wizard.
    func createSpace(communityId: String) async {
        guard let type = selectedType else { return }
        guard !isCreating else { return }

        isCreating = true
        createError = nil

        let description = scaffold?.description ?? ""
        let priceConfig: SpacePriceConfig? = buildPriceConfig()

        do {
            let newSpaceId = try await SpacesService.shared.createSpace(
                communityId: communityId,
                type: type,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description,
                accessPolicy: accessPolicy,
                priceConfig: priceConfig,
                passageRefs: scaffold?.passageRefs,
                cadence: scaffold?.cadenceSuggestion
            )
            createdSpaceId = newSpaceId
        } catch {
            createError = error
        }

        isCreating = false
    }

    // MARK: - Helpers

    private func spaceTypeRawValue(_ type: AmenSpace.SpaceType) -> String {
        switch type {
        case .chat:         return "chat"
        case .bibleStudy:   return "bibleStudy"
        case .group:        return "group"
        case .announcement: return "announcement"
        }
    }

    private func buildPriceConfig() -> SpacePriceConfig? {
        guard accessPolicy != .free, amountCents >= 100 else { return nil }
        let interval: String?
        switch selectedInterval {
        case "weekly":  interval = "week"
        case "monthly": interval = "month"
        case "yearly":  interval = "year"
        default:        interval = nil
        }
        return SpacePriceConfig(amountCents: amountCents, currency: "usd", interval: interval)
    }
}

// MARK: - SpaceCreationError

enum SpaceCreationError: LocalizedError {
    case invalidScaffoldResponse
    case missingSpaceType

    var errorDescription: String? {
        switch self {
        case .invalidScaffoldResponse:
            return "Berean returned an unexpected response. Please try again."
        case .missingSpaceType:
            return "Please choose a Space type to continue."
        }
    }
}
