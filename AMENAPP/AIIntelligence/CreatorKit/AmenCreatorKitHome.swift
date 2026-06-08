import SwiftUI
import FirebaseFunctions

// MARK: - CreatorDraftRequest

private struct CreatorDraftRequest {
    let contentType: String
    let topic: String
    let tone: String
    let length: String
}

// MARK: - AmenCreatorKitViewModel

@MainActor
final class AmenCreatorKitViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var draft: [String: Any]?
    @Published var draftId: String?
    @Published var errorMessage: String?
    @Published var showDraftSheet = false

    private let functions = Functions.functions(region: "us-central1")

    func generateDraft(type: String, topic: String, tone: String = "encouraging", length: String = "medium") async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        draft = nil
        draftId = nil

        let payload: [String: Any] = [
            "contentType": type,
            "topic": topic,
            "tone": tone,
            "length": length,
        ]

        do {
            let result = try await functions.httpsCallable("generateCreatorDraft").call(payload)

            if let data = result.data as? [String: Any] {
                if let draftData = data["draft"] as? [String: Any] {
                    draft = draftData
                    draftId = data["draftId"] as? String
                    showDraftSheet = true
                } else if let errorStr = data["error"] as? String, errorStr == "draft_unavailable" {
                    errorMessage = data["fallback"] as? String ?? "Draft generation temporarily unavailable. Please try again."
                } else {
                    errorMessage = "Unexpected response from draft service."
                }
            } else {
                errorMessage = "Could not read draft response."
            }
        } catch {
            errorMessage = "Could not generate draft. Please check your connection and try again."
        }

        isLoading = false
    }
}

// MARK: - CreatorDraftSheetView

private struct CreatorDraftSheetView: View {
    let draft: [String: Any]
    let draftId: String?
    @Environment(\.dismiss) private var dismiss

    var title: String      { draft["title"] as? String ?? "Draft" }
    var draftBody: String  { draft["body"] as? String ?? "" }
    var hashtags: [String] { draft["suggestedHashtags"] as? [String] ?? [] }
    var scriptures: [String] { draft["scriptures"] as? [String] ?? [] }
    var cta: String        { draft["callToAction"] as? String ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.title2.weight(.semibold))

                    if !scriptures.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scripture").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(scriptures, id: \.self) { ref in
                                Text(ref).font(.subheadline).foregroundStyle(.blue)
                            }
                        }
                    }

                    Text(draftBody)
                        .font(.body)

                    if !cta.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Call to Action").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(cta).font(.subheadline.italic())
                        }
                    }

                    if !hashtags.isEmpty {
                        Text(hashtags.map { "#\($0)" }.joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("This is an AI draft. Review and edit before publishing.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("AI Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AmenCreatorKitHome

struct AmenCreatorKitHome: View {
    @StateObject private var viewModel = AmenCreatorKitViewModel()
    @State private var selectedAction: String?
    @State private var topicInput = ""
    @State private var showTopicPrompt = false

    private let draftActions = [
        ("Post", "post", "square.and.pencil"),
        ("Devotional", "devotional", "book.closed"),
        ("Study Guide", "studyGuide", "graduationcap"),
        ("Sermon", "sermon", "mic"),
    ]

    var body: some View {
        if AMENFeatureFlags.shared.amenCreatorKitEnabled {
            VStack(spacing: 12) {
                Text("Amen Creator Kit")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)

                AmenLiquidGlassControlDock(placement: .top) {
                    ForEach(draftActions, id: \.0) { label, type, icon in
                        AmenLiquidGlassPillButton(
                            title: label,
                            systemImage: icon,
                            isLoading: viewModel.isLoading && selectedAction == type,
                            isDisabled: viewModel.isLoading,
                            action: {
                                selectedAction = type
                                showTopicPrompt = true
                            }
                        )
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer(minLength: 0)
            }
            .padding(.top)
            .background(Color(.systemBackground))
            .alert("What's your topic?", isPresented: $showTopicPrompt, actions: {
                TextField("Topic or Scripture reference", text: $topicInput)
                Button("Generate") {
                    guard let type = selectedAction, !topicInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task { await viewModel.generateDraft(type: type, topic: topicInput) }
                    topicInput = ""
                }
                Button("Cancel", role: .cancel) { topicInput = "" }
            }, message: {
                Text("Enter a topic or Scripture reference for your \(selectedAction ?? "draft").")
            })
            .sheet(isPresented: $viewModel.showDraftSheet) {
                if let draft = viewModel.draft {
                    CreatorDraftSheetView(draft: draft, draftId: viewModel.draftId)
                }
            }
        }
    }
}
