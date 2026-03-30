//
//  StudioExportService.swift
//  AMENAPP
//
//  Day 11: On-device PNG/JPG export using SwiftUI ImageRenderer.
//  Renders a Studio creation card to a UIImage, then saves to
//  the user's photo library or presents a share sheet.
//
//  Usage:
//    StudioExportService.exportAsImage(text: vm.generatedText, tool: selectedTool)
//

import Photos
import SwiftUI

@MainActor
enum StudioExportService {

    /// Renders the creation card to a UIImage and saves to Photos.
    /// Returns `true` on success; throws on permission denial.
    @discardableResult
    static func saveToPhotos(text: String, tool: StudioTool, title: String) async throws -> Bool {
        let image = try await render(text: text, tool: tool, title: title)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photoLibraryDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
        return true
    }

    /// Returns a `UIImage` suitable for a share sheet.
    static func renderForSharing(text: String, tool: StudioTool, title: String) async throws -> UIImage {
        try await render(text: text, tool: tool, title: title)
    }

    // MARK: - Private

    private static func render(text: String, tool: StudioTool, title: String) async throws -> UIImage {
        let card = StudioExportCard(text: text, tool: tool, title: title)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0 // @3x — print-quality
        guard let image = renderer.uiImage else {
            throw ExportError.renderFailed
        }
        return image
    }

    enum ExportError: LocalizedError {
        case renderFailed
        case photoLibraryDenied

        var errorDescription: String? {
            switch self {
            case .renderFailed:       return "Could not render the creation card."
            case .photoLibraryDenied: return "Photo library access denied. Enable it in Settings."
            }
        }
    }
}

// MARK: - Export Card View

/// The visual template rendered by ImageRenderer.
/// 1080×1350 px (@3x of 360×450 pt) — Instagram Portrait ratio.
private struct StudioExportCard: View {
    let text: String
    let tool: StudioTool
    let title: String

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [tool.accentColor.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tool.accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: tool.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(tool.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.outputLabel.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tool.accentColor)
                            .kerning(1.5)
                        Text(title.isEmpty ? "AMEN Studio" : title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "cross.fill")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(tool.accentColor.opacity(0.5))
                }
                .padding(.bottom, 20)

                Divider()
                    .overlay(tool.accentColor.opacity(0.15))
                    .padding(.bottom, 20)

                // Content
                Text(text)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 20)

                // Footer
                HStack {
                    Text("Created with AMEN")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(tool.accentColor.opacity(0.6))
                }
            }
            .padding(28)
        }
        .frame(width: 360, height: 450)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
