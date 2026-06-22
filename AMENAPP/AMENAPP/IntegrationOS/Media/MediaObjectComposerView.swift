// MediaObjectComposerView.swift — AMEN IntegrationOS
// SwiftUI media composer for creating sermon study packets.

import SwiftUI

@MainActor
final class MediaObjectComposerViewModel: ObservableObject {
    @Published var sermonTitle = ""
    @Published var mediaURL = ""
    @Published var packet: SermonStudyPacket?
    @Published var isTransforming = false
    @Published var errorMessage: String?

    private let service = SermonMediaTransformService.shared

    var canTransform: Bool {
        !sermonTitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        !mediaURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func transform() async {
        isTransforming = true
        errorMessage = nil
        do {
            packet = try await service.transform(
                sermonId: UUID().uuidString,
                mediaURL: mediaURL,
                title: sermonTitle
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isTransforming = false
    }
}

struct MediaObjectComposerView: View {
    @StateObject private var viewModel = MediaObjectComposerViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    inputSection

                    if let packet = viewModel.packet {
                        PacketPreviewSection(packet: packet)
                    }

                    if viewModel.isTransforming {
                        ProgressView("Generating study packet…")
                            .padding()
                    }

                    if let err = viewModel.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("Sermon Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var inputSection: some View {
        VStack(spacing: 12) {
            TextField("Sermon Title", text: $viewModel.sermonTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Media URL (audio/video)", text: $viewModel.mediaURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                Task { await viewModel.transform() }
            } label: {
                HStack {
                    if viewModel.isTransforming { ProgressView().tint(.white) }
                    Text("Generate Study Packet")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.canTransform ? Color.accentColor : Color.secondary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!viewModel.canTransform || viewModel.isTransforming)

            Text("AI-generated content requires human review before sharing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct PacketPreviewSection: View {
    let packet: SermonStudyPacket
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Study Packet")
                    .font(.headline)
                Spacer()
                Label("Pending Review", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !packet.scripture.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scripture").font(.subheadline.weight(.semibold))
                    ForEach(packet.scripture, id: \.self) { ref in
                        Text("• \(ref)").font(.subheadline)
                    }
                }
            }

            if !packet.discussionQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Discussion Questions").font(.subheadline.weight(.semibold))
                    ForEach(packet.discussionQuestions, id: \.self) { q in
                        Text("• \(q)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
        )
    }
}
