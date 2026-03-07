
//
//  ShareModels.swift
//  AMENShareExtension + AMENAPP (shared via App Group)
//
//  Models shared between the Share Extension and the main app.
//  Both targets must compile this file.
//

import Foundation
import SwiftUI

// MARK: - ShareDraft

/// Written by the Share Extension, read by the main AMEN app on launch.
struct ShareDraft: Codable {
    var text: String
    var linkURLString: String?
    /// Path to a JPEG saved inside the App Group container.
    var imageDataPath: String?
    /// "openTable" | "testimonies" | "churchNote"
    var destination: String
    var source: String = "shareExtension"
}

// MARK: - ShareComposeViewModel

@MainActor
final class ShareComposeViewModel: ObservableObject {
    @Published var draftText: String = ""
    @Published var linkURLString: String = ""
    @Published var imageData: Data? = nil
    @Published var selectedDestination: ShareDestination = .openTable

    enum ShareDestination: String, CaseIterable, Identifiable {
        case openTable   = "openTable"
        case testimonies = "testimonies"
        case churchNote  = "churchNote"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .openTable:   return "#OPENTABLE"
            case .testimonies: return "Testimony"
            case .churchNote:  return "Church Note"
            }
        }
        var icon: String {
            switch self {
            case .openTable:   return "globe"
            case .testimonies: return "star"
            case .churchNote:  return "note.text"
            }
        }
    }

    /// Heuristic: choose destination based on URL domain.
    func suggestDestination(for url: URL) {
        let host = url.host?.lowercased() ?? ""
        if host.contains("bible") || host.contains("youversion") || host.contains("biblegateway") {
            selectedDestination = .churchNote
        } else {
            selectedDestination = .openTable
        }
    }

    /// Heuristic: choose destination based on text keywords.
    func suggestDestinationFromText(_ text: String) {
        let lower = text.lowercased()
        let testimonyKeywords = ["testimony", "god changed", "miracle", "faith journey", "healed", "delivered"]
        if testimonyKeywords.contains(where: { lower.contains($0) }) {
            selectedDestination = .testimonies
        }
    }

    func makeDraft() -> ShareDraft {
        ShareDraft(
            text: draftText,
            linkURLString: linkURLString.isEmpty ? nil : linkURLString,
            destination: selectedDestination.rawValue
        )
    }
}

// MARK: - ShareExtensionComposeView

struct ShareExtensionComposeView: View {
    @ObservedObject var viewModel: ShareComposeViewModel
    let onCancel: () -> Void
    let onPost: (ShareDraft) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // Destination Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Post to")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.6)

                            HStack(spacing: 8) {
                                ForEach(ShareComposeViewModel.ShareDestination.allCases) { dest in
                                    Button {
                                        viewModel.selectedDestination = dest
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: dest.icon)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(dest.displayName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            viewModel.selectedDestination == dest
                                                ? Color.blue.opacity(0.15)
                                                : Color(.tertiarySystemBackground),
                                            in: Capsule()
                                        )
                                        .overlay(
                                            Capsule().strokeBorder(
                                                viewModel.selectedDestination == dest
                                                    ? Color.blue.opacity(0.5) : Color.clear,
                                                lineWidth: 1.2
                                            )
                                        )
                                    }
                                    .foregroundStyle(viewModel.selectedDestination == dest ? .blue : .secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Link Card
                        if !viewModel.linkURLString.isEmpty {
                            LinkCardView(
                                urlString: viewModel.linkURLString,
                                onRemove: { viewModel.linkURLString = "" }
                            )
                            .padding(.horizontal, 20)
                        }

                        // Image preview
                        if let data = viewModel.imageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable().scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal, 20)
                        }

                        // Text composer
                        ZStack(alignment: .topLeading) {
                            if viewModel.draftText.isEmpty {
                                Text("Add your thoughts…")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                            }
                            TextEditor(text: $viewModel.draftText)
                                .font(.system(size: 16))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                        )
                        .padding(.horizontal, 20)

                        // Char count
                        HStack {
                            Spacer()
                            let count = viewModel.draftText.count
                            Text("\(count)/500")
                                .font(.system(size: 12))
                                .foregroundStyle(count > 450 ? .orange : .tertiary)
                        }
                        .padding(.horizontal, 24)

                        // Privacy note
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("Shared links open in their original app. AMEN only stores the URL and a short preview.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Share to AMEN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onPost(viewModel.makeDraft())
                    } label: {
                        Text("Post")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .disabled(
                        viewModel.draftText.isEmpty &&
                        viewModel.linkURLString.isEmpty &&
                        viewModel.imageData == nil
                    )
                }
            }
        }
    }
}
