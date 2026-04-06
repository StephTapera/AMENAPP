// CreationDraftService.swift
// AMEN Creator — Draft Management Service
// Persist, restore, and manage creation drafts

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class CreationDraftService: ObservableObject {

    static let shared = CreationDraftService()
    private init() {}

    private let db = Firestore.firestore()

    @Published var activeDrafts: [CreationDraft] = []
    @Published var isLoading = false

    // MARK: - Load Drafts

    func loadDrafts() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        do {
            let snapshot = try await db
                .collection("creationDrafts")
                .whereField("userId", isEqualTo: uid)
                .whereField("status", isEqualTo: "active")
                .order(by: "updatedAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            activeDrafts = snapshot.documents.compactMap {
                try? $0.data(as: CreationDraft.self)
            }
        } catch {
            dlog("⚠️ [CreationDraftService] loadDrafts failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Delete Draft

    func deleteDraft(_ draft: CreationDraft) async {
        guard let draftId = draft.id else { return }
        do {
            try await db
                .collection("creationDrafts")
                .document(draftId)
                .updateData(["status": "abandoned"])
            activeDrafts.removeAll { $0.id == draft.id }
        } catch {
            dlog("⚠️ [CreationDraftService] deleteDraft failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Recover Most Recent

    func mostRecentActiveDraft() -> CreationDraft? {
        activeDrafts.first
    }

    // MARK: - Has Stale Drafts

    var hasActiveDrafts: Bool { !activeDrafts.isEmpty }
}

// MARK: - Drafts List View

struct CreationDraftsView: View {
    @ObservedObject private var service = CreationDraftService.shared
    @State private var showStudio = false
    @State private var selectedDraft: CreationDraft?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Loading drafts...")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.activeDrafts.isEmpty {
                    CreationEmptyState(
                        icon: "doc.text.fill",
                        title: "No Drafts",
                        message: "Your saved creation drafts will appear here.",
                        actionLabel: "Start Creating"
                    ) {
                        selectedDraft = nil
                        showStudio = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(service.activeDrafts) { draft in
                            DraftRow(draft: draft) {
                                selectedDraft = draft
                                showStudio = true
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await service.deleteDraft(draft) }
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedDraft = nil
                        showStudio = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .task { await service.loadDrafts() }
        }
        .fullScreenCover(isPresented: $showStudio) {
            CreationStudioView(
                initialTemplate: nil,
                draftId: selectedDraft?.id
            )
        }
    }
}

// MARK: - Draft Row

struct DraftRow: View {
    let draft: CreationDraft
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.08))
                        .frame(width: 50, height: 50)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let tId = draft.templateId {
                            Text(templateName(tId))
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Text(relativeDate(draft.updatedAt))
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func templateName(_ id: String) -> String {
        CreationTemplate.systemTemplates.first { $0.id == id }?.name ?? "Custom"
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff/60))m ago" }
        if diff < 86400 { return "\(Int(diff/3600))h ago" }
        return "\(Int(diff/86400))d ago"
    }
}
