import FirebaseAuth
import FirebaseStorage
import SwiftUI
import UIKit

@MainActor
enum AmenDesignExportService {
    static func renderImage(title: String, text: String, accentColor: Color) throws -> UIImage {
        let renderer = ImageRenderer(content: AmenDesignExportCard(title: title, text: text, accentColor: accentColor))
        renderer.scale = 3.0
        guard let image = renderer.uiImage else {
            throw ExportError.renderFailed
        }
        return image
    }

    static func exportPNG(designId: String, title: String, text: String, accentColor: Color) async throws -> ExportedDesignImage {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ExportError.notSignedIn
        }
        let image = try renderImage(title: title, text: text, accentColor: accentColor)
        guard let data = image.pngData() else {
            throw ExportError.renderFailed
        }

        let storagePath = "users/\(uid)/designs/\(designId)/export.png"
        let metadata = StorageMetadata()
        metadata.contentType = "image/png"
        let ref = Storage.storage().reference().child(storagePath)
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let downloadURL = try await ref.downloadURL()
        _ = try await AmenUniversalContentService.shared.exportDesignImageMetadata(
            designId: designId,
            storagePath: storagePath,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale)
        )
        return ExportedDesignImage(storagePath: storagePath, downloadURL: downloadURL.absoluteString)
    }

    enum ExportError: LocalizedError {
        case notSignedIn
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in to export designs."
            case .renderFailed:
                return "Could not render the design image."
            }
        }
    }
}

struct ExportedDesignImage {
    let storagePath: String
    let downloadURL: String
}

private struct AmenDesignExportCard: View {
    let title: String
    let text: String
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(.systemBackground)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(accentColor.opacity(0.10))
                .padding(24)
            VStack(alignment: .leading, spacing: 18) {
                Text(title.isEmpty ? "Amen Design" : title)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(8)
                    .minimumScaleFactor(0.72)
                Spacer()
                Text("AMEN")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(accentColor)
            }
            .padding(72)
        }
        .frame(width: 1080, height: 1350)
    }
}
