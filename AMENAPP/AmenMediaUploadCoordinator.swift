import Foundation
import SwiftUI
import PhotosUI

struct AmenMediaUploadItem: Identifiable {
    let id: String
    var mediaRef: MediaRef
    var progress: Double = 0.0
    var errorMessage: String? = nil
    var localURL: URL? = nil

    static func placeholder(id: String) -> AmenMediaUploadItem {
        AmenMediaUploadItem(id: id, mediaRef: MediaRef(id: id, type: .image))
    }
}

@MainActor
final class AmenMediaUploadCoordinator: ObservableObject {
    @Published var items: [AmenMediaUploadItem] = []

    var mediaRefs: [MediaRef] {
        items.map(\.mediaRef)
    }

    func handlePickedItems(_ pickedItems: [PhotosPickerItem], allowsMultiple: Bool) async {}
    func handleCameraCapture(_ capture: AmenCameraCapture, allowsMultiple: Bool) async {}
    func updateCaption(itemId: String, caption: String) {}
    func updateCover(itemId: String, coverTime: Double) {}
    func attachVoiceover(itemId: String, voiceoverURL: URL) {}
    func replaceLocalMedia(itemId: String, with url: URL) {}
}
