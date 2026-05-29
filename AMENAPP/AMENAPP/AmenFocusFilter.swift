//
//  AmenFocusFilter.swift
//  AMENAPP
//
//  iOS Focus Filters integration — adapts AMEN to the user's current
//  spiritual context when a Focus mode is active on their device.
//
//  WIRING REQUIRED: Register AmenFocusFilter in app Info.plist under
//  NSExtension > NSExtensionAttributes > Intents > AmenFocusFilter
//

import AppIntents

#if canImport(AppIntents)

// MARK: - AmenFocusMode

/// The spiritual/contextual mode that maps to an iOS Focus configuration.
@available(iOS 16, *)
enum AmenFocusMode: String, AppEnum {

    case general
    case church
    case prayer
    case study
    case rest

    // MARK: AppEnum conformance

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "AMEN Mode"

    static let caseDisplayRepresentations: [AmenFocusMode: DisplayRepresentation] = [
        .general : "General",
        .church  : "At Church",
        .prayer  : "Prayer Time",
        .study   : "Bible Study",
        .rest    : "Rest Mode"
    ]
}

// MARK: - AmenFocusFilter

/// SetFocusFilterIntent that configures AMEN when an iOS Focus becomes active.
/// Each case maps to a meaningful spiritual context with appropriate app behaviour.
@available(iOS 16, *)
struct AmenFocusFilter: SetFocusFilterIntent {

    // MARK: Metadata

    static let title: LocalizedStringResource = "AMEN Mode"
    static let description: IntentDescription = IntentDescription(
        "Adapts AMEN to your current spiritual context"
    )

    // MARK: Parameter

    @Parameter(title: "Mode")
    var mode: AmenFocusMode

    // MARK: DisplayRepresentation

    var displayRepresentation: DisplayRepresentation {
        AmenFocusMode.caseDisplayRepresentations[mode]
            ?? DisplayRepresentation(title: "AMEN Mode")
    }

    // MARK: Perform

    func perform() async throws -> some IntentResult {
        switch mode {

        case .general:
            // Restore all calm mode settings to their defaults
            await MainActor.run {
                CalmModeManager.shared.reset()
            }
            dlog("AmenFocusFilter: general mode — defaults restored")

        case .church:
            // Church is an active, participatory context — disable calm mode,
            // notify the app to surface church-specific UI.
            await MainActor.run {
                CalmModeManager.shared.isEnabled = false
            }
            NotificationCenter.default.post(
                name: Notification.Name("openChurchMode"),
                object: nil
            )
            dlog("AmenFocusFilter: church mode — active mode, calm off")

        case .prayer:
            // Prayer time calls for calm, reduced distraction.
            await MainActor.run {
                CalmModeManager.shared.isEnabled = true
                CalmModeManager.shared.reducedAnimations = true
            }
            dlog("AmenFocusFilter: prayer mode — calm on, reduced animations")

        case .study:
            // Bible study — route to Berean, leave calm mode state untouched.
            NotificationCenter.default.post(
                name: Notification.Name("openBereanStudy"),
                object: nil
            )
            dlog("AmenFocusFilter: study mode — Berean study opened")

        case .rest:
            // Rest mode — full calm, grayscale, audio-first.
            await MainActor.run {
                CalmModeManager.shared.isEnabled = true
                CalmModeManager.shared.grayscaleMode = true
                CalmModeManager.shared.audioFirstMode = true
            }
            dlog("AmenFocusFilter: rest mode — calm on, grayscale, audio-first")
        }

        return .result()
    }
}

#endif // canImport(AppIntents)
