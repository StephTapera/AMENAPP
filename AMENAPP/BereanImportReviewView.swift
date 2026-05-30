
//
//  BereanImportReviewView.swift
//  AMENAPP
//
//  Review screen for the Berean Import pipeline.
//  Shown when ImportJob.status == .ready.
//
//  Each candidate card shows:
//    - Original text (collapsed)
//    - Berean's content type tag + performance flag warning
//    - Reconsecrated draft (editable inline)
//    - Keep / Discard / Edit actions
//  keepRecommended items appear at the top.
//
//  Commit flow calls FirebasePostService.createPost() for each kept candidate
//  and stamps provenance (importedFrom, aiAssisted).
//  Cleanup: deletes discarded candidate media, then marks job done.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - BereanImportReviewView

struct BereanImportReviewView: View {

    let job: ImportJob

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: BereanImportReviewViewModel

    init(job: ImportJob) {
        self.job = job
        _vm = StateObject(wrappedValue: BereanImportReviewViewModel(job: job))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    loadingView
                } else if vm.candidates.isEmpty {
                    emptyView
                } else {
                    candidateList
                }
            }
            .navigationTitle("Review Posts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { await vm.cancelImport() }
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    commitButton
                }
            }
        }
        .task { await vm.loadCandidates() }
        .alert("Delete This Import?", isPresented: $vm.showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    await vm.deleteJob()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All extracted posts and media for this import will be permanently removed.")
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage)
        }
        .sheet(isPresented: $vm.showDoneView) {
            ImportDoneView(importedCount: vm.importedCount) {
                dismiss()
            }
        }
    }

    // MARK: - Candidate List

    private var candidateList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Stats banner
                statsBanner.padding(.horizontal, 16).padding(.top, 8)

                // Performative warning if any flagged items
                if vm.candidates.contains(where: { $0.isPerformative && $0.userDecision == .pending }) {
                    performativeWarning.padding(.horizontal, 16)
                }

                // Cards: keepRecommended first
                ForEach(vm.sortedCandidates) { candidate in
                    CandidateCard(candidate: candidate, vm: vm)
                        .padding(.horizontal, 16)
                }

                // Danger zone
                deleteJobButton.padding(.horizontal, 16).padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Stats Banner

    private var statsBanner: some View {
        let pending = vm.candidates.filter { $0.userDecision == .pending }.count
        let kept    = vm.candidates.filter { $0.userDecision == .keep || $0.userDecision == .edited }.count
        let discarded = vm.candidates.filter { $0.userDecision == .discard }.count

        return HStack(spacing: 0) {
            StatChip(value: "\(pending)", label: "Pending", color: .secondary)
            Divider().frame(height: 28)
            StatChip(value: "\(kept)", label: "Keeping", color: .green)
            Divider().frame(height: 28)
            StatChip(value: "\(discarded)", label: "Discarded", color: .red)
        }
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 0.8))
    }

    // MARK: - Performative Warning

    private var performativeWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some posts flagged")
                    .font(.caption.weight(.semibold))
                Text("Berean flagged a few posts as performance-driven. They're shown with an orange border — you still decide what to keep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.3), lineWidth: 0.8))
    }

    // MARK: - Commit Button

    @ViewBuilder
    private var commitButton: some View {
        let keepCount = vm.candidates.filter { $0.userDecision == .keep || $0.userDecision == .edited }.count
        if keepCount > 0 {
            if vm.isCommitting {
                ProgressView()
            } else {
                Button("Post \(keepCount)") {
                    Task { await vm.commitKeptCandidates() }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Delete Job Button

    private var deleteJobButton: some View {
        Button(role: .destructive) {
            vm.showDeleteConfirm = true
        } label: {
            Label("Delete this import", systemImage: "trash")
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading candidates…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No posts found")
                .font(.title3.weight(.semibold))
            Text("Berean couldn't extract any posts from this archive. Try a different export format (JSON, not HTML).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CandidateCard

private struct CandidateCard: View {

    let candidate: ImportCandidate
    let vm: BereanImportReviewViewModel

    @State private var showOriginal = false
    @State private var editMode = false
    @State private var editText: String = ""

    private var borderColor: Color {
        if candidate.isPerformative { return .orange }
        switch candidate.userDecision {
        case .keep, .edited: return .green
        case .discard: return .red.opacity(0.4)
        default: return .white.opacity(0.12)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: source type + Berean tag
            cardHeader

            // Content
            if editMode {
                editableContent
            } else {
                displayContent
            }

            // Actions
            actionRow
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(borderColor, lineWidth: candidate.isPerformative || candidate.userDecision != .pending ? 1.5 : 0.8)
        )
        .opacity(candidate.userDecision == .discard ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: candidate.userDecision)
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            // Source type chip
            Label(candidate.sourceType.displayLabel, systemImage: candidate.sourceType.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground), in: Capsule())

            // Berean content type
            if let classification = candidate.bereanClassification {
                Text(classification.type.displayLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(bereanTypeColor(classification.type).opacity(0.8), in: Capsule())
            }

            Spacer()

            // Performative flag
            if candidate.isPerformative {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Berean recommend indicator
            if let c = candidate.bereanClassification {
                Image(systemName: c.keepRecommended ? "hand.thumbsup.fill" : "hand.thumbsdown")
                    .font(.caption)
                    .foregroundStyle(c.keepRecommended ? .green : .secondary)
            }
        }
    }

    @ViewBuilder
    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Reconsecrated draft (primary display)
            if let draft = candidate.bereanClassification?.reconsecratedDraft, !draft.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Berean's rewrite", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(draft)
                        .font(.subheadline)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: false)
                }
            } else {
                Text(candidate.originalText.isEmpty ? "(No text)" : candidate.originalText)
                    .font(.subheadline)
                    .lineLimit(4)
                    .foregroundStyle(.primary)
            }

            // Show original toggle
            if !candidate.originalText.isEmpty &&
               candidate.bereanClassification?.reconsecratedDraft?.isEmpty == false {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showOriginal.toggle() }
                } label: {
                    Label(showOriginal ? "Hide original" : "Show original", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showOriginal {
                    Text(candidate.originalText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity)
                }
            }

            // Media count badge
            if !candidate.mediaRefs.isEmpty {
                Label("\(candidate.mediaRefs.count) media item\(candidate.mediaRefs.count == 1 ? "" : "s")", systemImage: "photo.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Provenance label
            Text("Imported from \(candidate.provenance.importedFrom.capitalized)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var editableContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Edit post", systemImage: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            TextEditor(text: $editText)
                .font(.subheadline)
                .frame(minHeight: 80, maxHeight: 200)
                .padding(8)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.8)
                )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if editMode {
                // Save edit
                Button {
                    Task {
                        await vm.setDecision(candidateId: candidate.id ?? "",
                                              decision: .edited,
                                              editedText: editText)
                        editMode = false
                    }
                } label: {
                    Label("Save", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.green, in: Capsule())
                }

                Button {
                    editMode = false
                } label: {
                    Text("Cancel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                }
            } else {
                // Keep
                DecisionButton(
                    label: "Keep",
                    icon: "checkmark",
                    color: .green,
                    isActive: candidate.userDecision == .keep || candidate.userDecision == .edited
                ) {
                    Task { await vm.setDecision(candidateId: candidate.id ?? "", decision: .keep) }
                }

                // Discard
                DecisionButton(
                    label: "Discard",
                    icon: "trash",
                    color: .red,
                    isActive: candidate.userDecision == .discard
                ) {
                    Task { await vm.setDecision(candidateId: candidate.id ?? "", decision: .discard) }
                }

                // Edit
                Button {
                    editText = candidate.bereanClassification?.reconsecratedDraft ?? candidate.originalText
                    editMode = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                }
            }
        }
    }

    private func bereanTypeColor(_ type: BereanContentType) -> Color {
        switch type {
        case .testimony:  return .purple
        case .devotional: return .blue
        case .scripture:  return .indigo
        case .reflection: return .teal
        case .promotional: return .orange
        case .mundane:    return .gray
        }
    }
}

// MARK: - BereanImportReviewViewModel

@MainActor
final class BereanImportReviewViewModel: ObservableObject {

    @Published var candidates: [ImportCandidate] = []
    @Published var isLoading = true
    @Published var isCommitting = false
    @Published var showDeleteConfirm = false
    @Published var showDoneView = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var importedCount = 0

    private let job: ImportJob
    private let store = FirestoreImportJobStore.shared
    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    var sortedCandidates: [ImportCandidate] {
        candidates.sorted {
            if $0.keepRecommended != $1.keepRecommended { return $0.keepRecommended }
            return ($0.originalTimestamp ?? .distantPast) > ($1.originalTimestamp ?? .distantPast)
        }
    }

    init(job: ImportJob) {
        self.job = job
    }

    func loadCandidates() async {
        guard let jobId = job.id else { return }
        isLoading = true
        do {
            candidates = try await store.fetchCandidates(uid: uid, jobId: jobId)
        } catch {
            showErrorMessage(error.localizedDescription)
        }
        isLoading = false

        // Also observe for real-time updates
        Task {
            for await updated in store.observeCandidates(uid: uid, jobId: jobId) {
                candidates = updated
            }
        }
    }

    func setDecision(candidateId: String, decision: UserImportDecision, editedText: String? = nil) async {
        guard let jobId = job.id else { return }
        do {
            try await store.updateCandidateDecision(
                uid: uid, jobId: jobId,
                candidateId: candidateId,
                decision: decision,
                editedText: editedText
            )
            // Optimistic local update
            if let i = candidates.firstIndex(where: { $0.id == candidateId }) {
                candidates[i].userDecision = decision
                if let text = editedText {
                    candidates[i].bereanClassification?.reconsecratedDraft = text
                }
            }
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    func commitKeptCandidates() async {
        guard let jobId = job.id else { return }
        isCommitting = true
        defer { isCommitting = false }

        let kept = candidates.filter { $0.userDecision == .keep || $0.userDecision == .edited }
        var committed = 0

        for candidate in kept {
            do {
                try await commitCandidate(candidate, jobId: jobId)
                try? await store.incrementImportedCount(uid: uid, jobId: jobId)
                committed += 1
            } catch {
                // Log and continue — don't abort the whole batch for one failure
            }
        }

        // Discard cleanup: delete media for discarded candidates
        let discarded = candidates.filter { $0.userDecision == .discard }
        for candidate in discarded {
            await store.deleteCandidateMedia(uid: uid, jobId: jobId, mediaRefs: candidate.mediaRefs)
        }

        // Mark job done
        try? await store.setJobDone(uid: uid, jobId: jobId)

        importedCount = committed
        showDoneView = true
    }

    private func commitCandidate(_ candidate: ImportCandidate, jobId: String) async throws {
        // Resolve which text to use + whether AI was used
        let aiAssisted: Bool
        let finalText: String
        if candidate.userDecision == .edited,
           let draft = candidate.bereanClassification?.reconsecratedDraft, !draft.isEmpty {
            finalText = draft
            aiAssisted = true
        } else if let draft = candidate.bereanClassification?.reconsecratedDraft, !draft.isEmpty {
            finalText = draft
            aiAssisted = true
        } else {
            finalText = candidate.originalText
            aiAssisted = false
        }

        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Resolve media download URLs from Storage paths
        var mediaDownloadURLs: [String] = []
        for path in candidate.mediaRefs.prefix(4) {
            if let url = try? await Storage.storage().reference(withPath: path).downloadURL() {
                mediaDownloadURLs.append(url.absoluteString)
            }
        }

        // Write via Firestore directly (matching DataImportService pattern)
        // We set importedFrom + importBatchId + aiAssisted for provenance display
        let db = Firestore.firestore()
        var docData: [String: Any] = [
            "authorId":       uid,
            "content":        String(finalText.prefix(500)),
            "category":       "openTable",
            "visibility":     "everyone",
            "allowComments":  true,
            "createdAt":      Timestamp(date: candidate.originalTimestamp ?? Date()),
            "updatedAt":      Timestamp(date: Date()),
            "amenCount":      0,
            "lightbulbCount": 0,
            "commentCount":   0,
            "repostCount":    0,
            "isRepost":       false,
            "amenUserIds":    [String](),
            "lightbulbUserIds": [String](),
            // Provenance fields
            "importedFrom":   candidate.provenance.importedFrom,
            "importBatchId":  jobId,
            "aiAssisted":     aiAssisted,
            "moderationStatus": "pending",
            "wasEdited":      false,
            "editVersion":    0,
        ]

        if let user = Auth.auth().currentUser {
            docData["authorName"]     = user.displayName ?? "You"
            docData["authorInitials"] = String((user.displayName ?? "?").prefix(1)).uppercased()
        }

        if !mediaDownloadURLs.isEmpty {
            docData["imageURLs"] = mediaDownloadURLs
        }

        try await db.collection("posts").addDocument(data: docData)
    }

    func cancelImport() async {
        // Don't delete — user can resume from the job list later
    }

    func deleteJob() async {
        guard let jobId = job.id else { return }
        do {
            try await store.deleteJob(uid: uid, jobId: jobId)
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }

    private func showErrorMessage(_ msg: String) {
        errorMessage = msg
        showError = true
    }
}

// MARK: - Small Components

private struct DecisionButton: View {
    let label: String
    let icon: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? .white : color)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    isActive ? color : color.opacity(0.08),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(isActive ? .clear : color.opacity(0.3), lineWidth: 0.8)
                )
        }
    }
}

private struct StatChip: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.callout.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ImportDoneView: View {
    let importedCount: Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: true)
            VStack(spacing: 6) {
                Text("Posts Queued")
                    .font(.title2.weight(.bold))
                Text("\(importedCount) post\(importedCount == 1 ? "" : "s") submitted for review. They'll appear on your profile once approved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button("Done") { onDone() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 32)
            Spacer()
        }
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
    }
}
