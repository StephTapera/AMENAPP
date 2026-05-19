// BereanChurchNotesBridge.swift
// AMENAPP
//
// Connects Berean AI responses to the Church Notes system.
// Allows users to save scripture research, discussion questions, action items,
// and sermon notes from Berean conversations into their Church Notes.
//
// Privacy rules:
//   - Never saves without explicit user tap/consent
//   - Notes are saved to user's private churchNotes collection
//   - Source is tagged as "berean" for context
//
// Firestore path:
//   users/{uid}/churchNotes/{noteId}
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - BereanChurchNoteCategory

enum BereanChurchNoteCategory: String, CaseIterable, Codable {
    case researchCard       = "research_card"
    case sermonNote         = "sermon_note"
    case scriptureStudy     = "scripture_study"
    case theologicalCompare = "theological_comparison"
    case discussionQuestion = "discussion_question"
    case actionItem         = "action_item"
    case prayerRequest      = "prayer_request"
    case questionParking    = "question_parking"
    case followUpReading    = "follow_up_reading"

    var displayName: String {
        switch self {
        case .researchCard:       return "Research Card"
        case .sermonNote:         return "Sermon Note"
        case .scriptureStudy:     return "Scripture Study"
        case .theologicalCompare: return "Theological Comparison"
        case .discussionQuestion: return "Discussion Question"
        case .actionItem:         return "Action Item"
        case .prayerRequest:      return "Prayer Request"
        case .questionParking:    return "Parking Lot Question"
        case .followUpReading:    return "Follow-Up Reading"
        }
    }

    var icon: String {
        switch self {
        case .researchCard:       return "doc.magnifyingglass"
        case .sermonNote:         return "note.text"
        case .scriptureStudy:     return "book.pages"
        case .theologicalCompare: return "scale.3d"
        case .discussionQuestion: return "bubble.left.and.bubble.right"
        case .actionItem:         return "checkmark.circle"
        case .prayerRequest:      return "hands.sparkles"
        case .questionParking:    return "questionmark.square"
        case .followUpReading:    return "books.vertical"
        }
    }
}

// MARK: - BereanChurchNoteSaveResult

enum BereanChurchNoteSaveResult {
    case success(noteId: String)
    case failure(reason: String)
    case notAuthenticated
    case featureDisabled
}

// MARK: - BereanChurchNotesBridge

@MainActor
final class BereanChurchNotesBridge {
    static let shared = BereanChurchNotesBridge()
    private lazy var db = Firestore.firestore()
    private init() {}

    /// Saves a Berean response as a Church Note.
    /// Must only be called from an explicit user action.
    func save(
        content: String,
        title: String,
        category: BereanChurchNoteCategory,
        scriptureRefs: [String],
        bereanMode: String,
        theoLens: String,
        conversationId: String,
        tags: [String] = []
    ) async -> BereanChurchNoteSaveResult {
        guard AMENFeatureFlags.shared.bereanChurchNotesBridgeEnabled else {
            AMENAnalyticsService.shared.track(.bereanFeatureFlagBlocked(feature: "berean_church_notes_bridge"))
            return .featureDisabled
        }

        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            return .notAuthenticated
        }

        AMENAnalyticsService.shared.track(.bereanChurchNoteSaveStarted)

        let noteId = UUID().uuidString
        let allTags = (tags + scriptureRefs + [category.rawValue, "berean"]).removingDuplicates()

        let data: [String: Any] = [
            "noteId": noteId,
            "title": title.isEmpty ? "Berean Study — \(Date().formatted(date: .abbreviated, time: .omitted))" : title,
            "content": content,
            "category": category.rawValue,
            "source": "berean",
            "bereanMode": bereanMode,
            "theoLens": theoLens,
            "scriptureRefs": scriptureRefs,
            "conversationId": conversationId,
            "tags": allTags,
            "ownerUid": uid,
            "collaborationPermissions": "private",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db
                .collection("users").document(uid)
                .collection("churchNotes").document(noteId)
                .setData(data)

            AMENAnalyticsService.shared.track(.bereanChurchNoteSaveCompleted)
            return .success(noteId: noteId)
        } catch {
            return .failure(reason: error.localizedDescription)
        }
    }
}

// MARK: - Array deduplication helper

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - BereanSaveToChurchNotesSheet

struct BereanSaveToChurchNotesSheet: View {
    let message: BereanSpiritualMessage
    let conversationId: String
    @Binding var isPresented: Bool

    @State private var selectedCategory: BereanChurchNoteCategory = .scriptureStudy
    @State private var noteTitle: String = ""
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
            .navigationTitle("Add to Church Notes")
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

                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Note title (optional)")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.secondary)
                    TextField("E.g. \"Study on Romans 8\"", text: $noteTitle)
                        .font(AMENFont.regular(15))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }

                // Content preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Content")
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

                // Category
                VStack(alignment: .leading, spacing: 10) {
                    Text("Save as")
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                        ForEach(BereanChurchNoteCategory.allCases, id: \.rawValue) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 12))
                                    Text(cat.displayName)
                                        .font(AMENFont.regular(12))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(selectedCategory == cat ? Color.black : Color(.secondarySystemBackground))
                                )
                                .foregroundColor(selectedCategory == cat ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Scripture refs
                if !scriptureRefs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scripture references")
                            .font(AMENFont.semiBold(13))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            ForEach(scriptureRefs.prefix(4), id: \.self) { ref in
                                Text(ref)
                                    .font(AMENFont.regular(11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                            }
                        }
                    }
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
                            ProgressView().tint(.white)
                        } else {
                            Text("Add to Church Notes")
                                .font(AMENFont.semiBold(16))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .font(.system(size: 44))
                .foregroundColor(.black)
            Text("Added to Church Notes")
                .font(AMENFont.semiBold(20))
            Text("You can find this in your Church Notes.")
                .font(AMENFont.regular(15))
                .foregroundColor(.secondary)
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

        let result = await BereanChurchNotesBridge.shared.save(
            content: message.content,
            title: noteTitle,
            category: selectedCategory,
            scriptureRefs: scriptureRefs,
            bereanMode: modelStore.selectedMode.backendValue,
            theoLens: lensStore.selectedLens.backendValue,
            conversationId: conversationId
        )

        isSaving = false
        switch result {
        case .success:
            withAnimation { didSave = true }
        case .failure(let reason):
            saveError = reason
        case .notAuthenticated:
            saveError = "Please sign in to save to Church Notes."
        case .featureDisabled:
            saveError = "Church Notes save is currently unavailable."
        }
    }
}
