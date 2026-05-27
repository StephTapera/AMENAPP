//
//  SelahLensViewModel.swift
//  AMENAPP
//
//  Observable state machine for the Selah Lens feature. Drives both
//  SelahLensBar (action classification) and BereanStudySheetView (study sheet).
//
//  All mutations happen on @MainActor. Functions never throw — they swallow
//  errors into the published error state so SwiftUI can surface them.
//

import Foundation

@MainActor
final class SelahLensViewModel: ObservableObject {

    // MARK: - State

    enum SelahLensState: Equatable {
        case idle
        case loading
        case loaded(ClassifyVerseThemeResponse)
        case error(String)
    }

    @Published var state: SelahLensState = .idle

    @Published var studySheet: BereanStudySheetResponse?
    @Published var studySheetLoading: Bool = false
    @Published var studySheetError: String?

    // MARK: - Dependencies

    private let service: SelahFunctionsService

    init(service: SelahFunctionsService = .shared) {
        self.service = service
    }

    // MARK: - Classification

    /// Classifies the verse theme and populates `state`. Never throws —
    /// errors land in `state = .error(message)`.
    func classifyVerse(
        verseId: String,
        translation: SelahTranslation,
        verseText: String
    ) async {
        state = .loading
        do {
            let response = try await service.classifyVerseTheme(
                verseId: verseId,
                translation: translation,
                verseText: verseText
            )
            state = .loaded(response)
        } catch {
            state = .error(errorMessage(from: error))
        }
    }

    // MARK: - Study Sheet

    /// Fetches the Berean study sheet and populates `studySheet`. Never throws —
    /// errors land in `studySheetError`.
    func loadStudySheet(
        verseId: String,
        translation: SelahTranslation,
        verseText: String
    ) async {
        studySheetLoading = true
        studySheetError = nil
        do {
            let response = try await service.bereanStudySheet(
                verseId: verseId,
                translation: translation,
                verseText: verseText
            )
            studySheet = response
        } catch {
            studySheetError = errorMessage(from: error)
        }
        studySheetLoading = false
    }

    // MARK: - Reset

    /// Clears all published state. Call when the lens bar is dismissed or
    /// the reader navigates to a different verse.
    func reset() {
        state = .idle
        studySheet = nil
        studySheetLoading = false
        studySheetError = nil
    }

    // MARK: - Private

    private func errorMessage(from error: Error) -> String {
        if let selahError = error as? SelahFunctionsError {
            return selahError.localizedDescription
        }
        return error.localizedDescription
    }
}
