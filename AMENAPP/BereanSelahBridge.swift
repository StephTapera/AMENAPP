// BereanSelahBridge.swift
// AMENAPP
//
// Connects Berean AI responses to the Selah reflection system.
// Allows users to save insights, prayers, reflections, and study paths
// from Berean conversations into their personal Selah journal.
//
// Privacy rules:
//   - Never saves without explicit user tap/consent
//   - Never saves sensitive content (crisis, abuse, health) without explicit action
//   - Saves go to the user's private selahEntries collection only
//   - Source is tagged as "berean" for context
//
// Firestore path:
//   users/{uid}/selahEntries/{entryId}
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - BereanSelahEntryType

enum BereanSelahEntryType: String, Codable, CaseIterable {
    case prayer       = "prayer"
    case reflection   = "reflection"
    case lament       = "lament"
    case gratitude    = "gratitude"
    case question     = "question"
    case discernment  = "discernment"
    case scriptureInsight = "scripture_insight"
    case studyNote    = "study_note"

    var displayName: String {
        switch self {
        case .prayer:           return "Prayer"
        case .reflection:       return "Reflection"
        case .lament:           return "Lament"
        case .gratitude:        return "Gratitude"
        case .question:         return "Spiritual Question"
        case .discernment:      return "Discernment"
        case .scriptureInsight: return "Scripture Insight"
        case .studyNote:        return "Study Note"
        }
    }

    var icon: String {
        switch self {
        case .prayer:           return "hands.sparkles"
        case .reflection:       return "sparkles"
        case .lament:           return "cloud.rain"
        case .gratitude:        return "sun.max"
        case .question:         return "questionmark.circle"
        case .discernment:      return "scale.3d"
        case .scriptureInsight: return "book.pages"
        case .studyNote:        return "note.text"
        }
    }
}

// MARK: - BereanSelahSaveRequest

struct BereanSelahSaveRequest {
    let content: String
    let entryType: BereanSelahEntryType
    let bereanMode: String           // "core" / "deep" / "adaptive"
    let theoLens: String             // "wisdom" / "prayer" / "discernment"
    let scriptureRefs: [String]
    let conversationId: String
    let responseId: String?
    let userConsentForMemory: Bool   // must be true; enforced by bridge
    let privacyLevel: PrivacyLevel

    enum PrivacyLevel: String, Codable {
        case `private` = "private"    // Only the user can see it
        case sharedWithPastor = "shared_with_pastor"  // Future: pastor consent flow
    }
}

// MARK: - BereanSelahSaveResult

enum BereanSelahSaveResult {
    case success(entryId: String)
    case failure(reason: String)
    case notAuthenticated
    case consentRequired  // userConsentForMemory was false
}

// MARK: - BereanSelahBridge

@MainActor
final class BereanSelahBridge {
    static let shared = BereanSelahBridge()
    private lazy var db = Firestore.firestore()
    private init() {}

    /// Saves a Berean response excerpt to the user's Selah journal.
    /// This MUST only be called from a UI action (user explicitly tapped "Save to Selah").
    /// Never call this silently or automatically.
    func save(_ request: BereanSelahSaveRequest) async -> BereanSelahSaveResult {
        guard request.userConsentForMemory else {
            return .consentRequired
        }

        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            return .notAuthenticated
        }

        guard AMENFeatureFlags.shared.bereanSelahBridgeEnabled else {
            AMENAnalyticsService.shared.track(.bereanFeatureFlagBlocked(feature: "berean_selah_bridge"))
            return .failure(reason: "Selah save is currently unavailable.")
        }

        AMENAnalyticsService.shared.track(.bereanSelahSaveStarted(entryType: request.entryType.rawValue))

        let entryId = UUID().uuidString
        let data: [String: Any] = [
            "entryId": entryId,
            "content": request.content,
            "entryType": request.entryType.rawValue,
            "source": "berean",
            "bereanMode": request.bereanMode,
            "theoLens": request.theoLens,
            "scriptureRefs": request.scriptureRefs,
            "conversationId": request.conversationId,
            "responseId": request.responseId as Any,
            "privacyLevel": request.privacyLevel.rawValue,
            "userConsentForMemory": true,
            "createdAt": FieldValue.serverTimestamp(),
            "ownerUid": uid
        ]

        do {
            try await db
                .collection("users").document(uid)
                .collection("selahEntries").document(entryId)
                .setData(data)

            AMENAnalyticsService.shared.track(.bereanSelahSaveCompleted(entryType: request.entryType.rawValue))
            return .success(entryId: entryId)
        } catch {
            return .failure(reason: error.localizedDescription)
        }
    }
}

// MARK: - BereanSaveToSelahSheet

/// Sheet presented when user taps "Save to Selah" from a Berean conversation bubble.
import SwiftUI

struct BereanSaveToSelahSheet: View {
    let message: BereanSpiritualMessage
    let conversationId: String
    @Binding var isPresented: Bool

    @State private var selectedType: BereanSelahEntryType = .reflection
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var didSave = false

    @ObservedObject private var lensStore = BereanTheoLensStore.shared
    @ObservedObject private var modelStore = BereanModelStore.shared

    private var scriptureRefs: [String] {
        BereanScriptureReferenceExtractor.references(in: message.content)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                if didSave {
                    savedConfirmation
                } else {
                    saveForm
                }
            }
            .navigationTitle("Save to Selah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var saveForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Preview of content being saved
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saving this insight")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.secondary)
                    Text(message.content)
                        .font(AMENFont.regular(14))
                        .foregroundColor(.primary)
                        .lineLimit(4)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }

                // Entry type selector
                VStack(alignment: .leading, spacing: 10) {
                    Text("Save as")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                        ForEach(BereanSelahEntryType.allCases, id: \.rawValue) { type in
                            Button {
                                selectedType = type
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: type.icon)
                                        .font(.systemScaled(13))
                                    Text(type.displayName)
                                        .font(AMENFont.regular(13))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedType == type ? Color.black : Color(.secondarySystemBackground))
                                )
                                .foregroundColor(selectedType == type ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Scripture refs preview
                if !scriptureRefs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scripture references")
                            .font(AMENFont.semiBold(13))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            ForEach(scriptureRefs.prefix(4), id: \.self) { ref in
                                Text(ref)
                                    .font(AMENFont.regular(12))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                            }
                        }
                    }
                }

                // Privacy note
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.systemScaled(12))
                        .foregroundColor(.secondary)
                    Text("Saved privately to your Selah journal. Only you can see this.")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.secondary)
                }

                if let err = saveError {
                    Text(err)
                        .font(AMENFont.regular(13))
                        .foregroundColor(.red)
                }

                Button {
                    Task { await performSave() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save to Selah")
                                .font(AMENFont.semiBold(16))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(.label), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(20)
        }
    }

    private var savedConfirmation: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(44))
                .foregroundColor(.black)
            Text("Saved to Selah")
                .font(AMENFont.semiBold(20))
            Text("Your insight is in your private Selah journal.")
                .font(AMENFont.regular(15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") { isPresented = false }
                .font(AMENFont.semiBold(16))
                .foregroundColor(.black)
        }
        .padding(24)
    }

    private func performSave() async {
        isSaving = true
        saveError = nil

        let request = BereanSelahSaveRequest(
            content: message.content,
            entryType: selectedType,
            bereanMode: modelStore.selectedMode.backendValue,
            theoLens: lensStore.selectedLens.backendValue,
            scriptureRefs: scriptureRefs,
            conversationId: conversationId,
            responseId: message.structuredResponse?.responseId,
            userConsentForMemory: true,  // User explicitly tapped save
            privacyLevel: .private
        )

        let result = await BereanSelahBridge.shared.save(request)

        isSaving = false
        switch result {
        case .success:
            withAnimation { didSave = true }
        case .failure(let reason):
            saveError = reason
        case .notAuthenticated:
            saveError = "Please sign in to save to Selah."
        case .consentRequired:
            saveError = "Consent is required to save."
        }
    }
}
