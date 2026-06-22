// AmenCreateRoute.swift
// AMENAPP
// Navigation routes for Universal Create.

import Foundation

enum AmenCreateRoute: Hashable, Identifiable {
    case composer(intent: AmenCreationIntent)
    case preview(draftId: String)

    var id: String {
        switch self {
        case .composer(let intent): return "composer_\(intent.rawValue)"
        case .preview(let draftId): return "preview_\(draftId)"
        }
    }
}
