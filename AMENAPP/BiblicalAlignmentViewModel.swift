import Foundation
import SwiftUI

@MainActor
final class BiblicalAlignmentViewModel: ObservableObject {
    enum PublishDecision: Equatable {
        case allow
        case allowWithPrompt
        case revise
        case block
        case holdForReview
    }

    @Published var isLoading = false
    @Published var result: BiblicalAlignmentCheckResult?
    @Published var errorMessage: String?
    @Published var rewrittenText: String?
    @Published var discernmentPrompt: DiscernmentPromptResult?

    var currentDecision: PublishDecision {
        guard let result else { return .allow }
        switch result.status {
        case .aligned:
            return .allow
        case .contextNeeded:
            return .allowWithPrompt
        case .needsDiscernment:
            return .revise
        case .blocked:
            return .block
        case .humanReview:
            return .holdForReview
        }
    }

    func scan(
        text: String,
        targetType: String,
        targetId: String? = nil,
        sourceSurface: String,
        requestedLens: AlignmentLens? = nil,
        hasMedia: Bool = false
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            result = try await BiblicalAlignmentService.shared.checkBiblicalAlignment(
                text: text,
                targetType: targetType,
                targetId: targetId,
                sourceSurface: sourceSurface,
                requestedLens: requestedLens,
                hasMedia: hasMedia
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestRewrite(for text: String, lens: AlignmentLens, targetType: String) async {
        do {
            let response = try await BiblicalAlignmentService.shared.suggestBiblicalRewrite(
                originalText: text,
                lens: lens,
                targetType: targetType
            )
            rewrittenText = response.rewrittenText
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCorrection(
        originalText: String?,
        correctionText: String,
        targetType: String,
        targetId: String? = nil,
        lens: AlignmentLens,
        correctionIntent: String,
        savedToProfile: Bool
    ) async -> Bool {
        do {
            return try await BiblicalAlignmentService.shared.saveAICorrection(
                originalCheckId: result?.checkId,
                targetType: targetType,
                targetId: targetId,
                originalText: originalText,
                correctionText: correctionText,
                selectedLens: lens,
                correctionIntent: correctionIntent,
                savedToProfile: savedToProfile
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadDiscernmentPrompt(text: String, surface: String) async {
        do {
            discernmentPrompt = try await BiblicalAlignmentService.shared.getDiscernmentPrompt(text: text, surface: surface)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        result = nil
        rewrittenText = nil
        discernmentPrompt = nil
        errorMessage = nil
    }
}
