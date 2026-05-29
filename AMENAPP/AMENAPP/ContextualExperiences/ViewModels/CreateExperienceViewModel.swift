// CreateExperienceViewModel.swift
// AMENAPP — Multi-Tenant Contextual Experience System
//
// Step-based creation wizard view model.
// Calls ContextualExperienceService.createExperience with the exact signature
// defined in ContextualExperienceService.swift (no publishImmediately param).

import SwiftUI

// MARK: - CreateExperienceViewModel

@MainActor
final class CreateExperienceViewModel: ObservableObject {

    // MARK: - Step enum

    enum CreateStep: CaseIterable {
        case type, configure, theme, modules, review

        var title: String {
            switch self {
            case .type:      return "Experience Type"
            case .configure: return "Configure"
            case .theme:     return "Theme"
            case .modules:   return "Modules"
            case .review:    return "Review"
            }
        }

        var index: Int {
            switch self {
            case .type:      return 1
            case .configure: return 2
            case .theme:     return 3
            case .modules:   return 4
            case .review:    return 5
            }
        }
    }

    // MARK: - Step state

    @Published var currentStep: CreateStep = .type

    // MARK: - Form fields

    @Published var selectedType: ExperienceType = .celebration
    @Published var title = ""
    @Published var description = ""
    @Published var region: String? = nil
    @Published var startDate = Date()
    @Published var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @Published var visibility: ExperienceScope = .organization
    @Published var theme = ExperienceThemeConfig.defaultTheme
    @Published var selectedModules: Set<ExperienceModuleType> = [.prayer, .discussion]
    @Published var safety = ExperienceSafetyConfig.standard

    // MARK: - State

    @Published var isSaving = false
    @Published var savedExperienceId: String?
    @Published var error: String?

    // MARK: - Computed: Validation

    var canAdvance: Bool {
        switch currentStep {
        case .type:
            return true
        case .configure:
            return title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                && description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
                && endDate > startDate
        case .theme:
            return true
        case .modules:
            return !selectedModules.isEmpty
        case .review:
            return true
        }
    }

    var isLastStep: Bool { currentStep == .review }

    // MARK: - Navigation

    func advance() {
        guard canAdvance else { return }
        switch currentStep {
        case .type:      currentStep = .configure
        case .configure: currentStep = .theme
        case .theme:     currentStep = .modules
        case .modules:   currentStep = .review
        case .review:    break
        }
    }

    func back() {
        switch currentStep {
        case .type:      break
        case .configure: currentStep = .type
        case .theme:     currentStep = .configure
        case .modules:   currentStep = .theme
        case .review:    currentStep = .modules
        }
    }

    // MARK: - Save

    func save(orgId: String, orgType: OrganizationType) async {
        isSaving = true
        error = nil
        do {
            let expId = try await ContextualExperienceService.shared.createExperience(
                orgId: orgId,
                orgType: orgType,
                type: selectedType,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                region: region,
                startDate: startDate,
                endDate: endDate,
                visibility: visibility,
                theme: theme,
                modules: Array(selectedModules),
                safety: safety
            )
            savedExperienceId = expId
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    // MARK: - Theme preview color

    /// Uses the project-wide non-failable Color(hex:) from Color+Hex.swift.
    var themePreviewColor: Color {
        Color(hex: theme.accentColorHex)
    }
}
