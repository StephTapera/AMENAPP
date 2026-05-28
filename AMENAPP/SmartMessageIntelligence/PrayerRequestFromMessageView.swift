import SwiftUI
import FirebaseAuth
import FirebaseFunctions

struct PrayerRequestFromMessageView: View {
    let spaceId: String
    let threadId: String
    let messageId: String
    let extractedText: String

    @State private var visibility: SmartPrayerVisibility = .private
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var promptTrigger = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Review") { Text(extractedText) }
            Section("Visibility") {
                Picker("Visibility", selection: $visibility) {
                    ForEach(SmartPrayerVisibility.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Button {
                    promptTrigger = true
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Label("Save Prayer Request", systemImage: "hands.sparkles") }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Add Prayer")
        .alert("Could not save prayer", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .amenSmartPrompt(surface: .prayerRequests, trigger: $promptTrigger)
    }

    private func save() async {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Sign in to save prayer requests."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await Functions.functions()
                .httpsCallable(SpacesCallable.createSpacePrayerRequest.rawValue)
                .call([
                    "spaceId": spaceId,
                    "body": extractedText,
                    "visibility": visibility.backendValue,
                    "category": "message",
                    "sourceMessageId": messageId,
                    "threadId": threadId
                ])
            AmenSmartMessageIntelligenceService.shared.trackActionConfirmed(
                SmartMessageAction(id: UUID().uuidString, title: "Create Prayer Request", subtitle: "", iconSystemName: "hands.sparkles", actionType: .createPrayerRequest, payload: [:], requiresConfirmation: true, privacyLevel: .private)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
