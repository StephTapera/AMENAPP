import Foundation

extension BereanAttachmentPickerMode: Identifiable {
    var id: String {
        switch self {
        case .file:
            return "file"
        case .photo:
            return "photo"
        case .camera:
            return "camera"
        }
    }
}

extension AmenCommandLayerActionID {
    var homeAttachmentPickerMode: BereanAttachmentPickerMode? {
        switch self {
        case .addFiles:
            return .file
        case .photos:
            return .photo
        case .camera:
            return .camera
        default:
            return nil
        }
    }
}
