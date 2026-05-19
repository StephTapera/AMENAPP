import Foundation
import SwiftUI

@MainActor
struct BereanContextCoordinator {
    static func scripturePayload(
        text: String,
        reference: String,
        translation: String,
        sourceSurface: String = "selah_scripture_reader",
        sourceId: String? = nil
    ) -> BereanContextPayload {
        BereanContextPayload(
            selectedText: text,
            surroundingText: reference,
            sourceSurface: sourceSurface,
            sourceId: sourceId ?? reference,
            contentType: .scripture,
            scriptureReference: reference,
            languageCode: "en",
            metadata: ["translation": translation]
        )
    }

    static func textPayload(
        text: String,
        contentType: BereanContextContentType,
        sourceSurface: String,
        sourceId: String? = nil,
        surroundingText: String? = nil
    ) -> BereanContextPayload {
        BereanContextPayload(
            selectedText: text,
            surroundingText: surroundingText,
            sourceSurface: sourceSurface,
            sourceId: sourceId,
            contentType: contentType
        )
    }
}
