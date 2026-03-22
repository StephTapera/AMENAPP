// SermonNotePreviewSheet.swift
// AMENAPP
//
// Preview sheet shown after Sermon Snap (image OCR) or Sermon Recorder completes.
// User can review the structured note, edit the title, then save or discard.
// Caller passes a ChurchNote draft; onSave receives the (potentially edited) note.

import SwiftUI
import FirebaseAuth

// MARK: - SermonNotePreviewSheet

struct SermonNotePreviewSheet: View {
    let draft: ChurchNote
    let source: NoteSource
    let onSave:    (ChurchNote) -> Void
    let onDiscard: () -> Void

    enum NoteSource {
        case snap       // from Sermon Snap (image)
        case recording  // from Sermon Recorder (audio)
    }

    @State private var editedTitle: String
    @State private var isSaving = false
    @State private var saveError: String?

    init(draft: ChurchNote, source: NoteSource, onSave: @escaping (ChurchNote) -> Void, onDiscard: @escaping () -> Void) {
        self.draft     = draft
        self.source    = source
        self.onSave    = onSave
        self.onDiscard = onDiscard
        _editedTitle   = State(initialValue: draft.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color(.separator))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source == .snap ? "Sermon Snap" : "Sermon Recording")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .textCase(.uppercase)
                    Text("Review & Save")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(.label))
                }
                Spacer()
                Button(action: onDiscard) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Editable title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .textCase(.uppercase)
                        TextField("Sermon title", text: $editedTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Key Points
                    if !draft.keyPoints.isEmpty {
                        sectionView(title: "Key Points", icon: "list.bullet") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(draft.keyPoints, id: \.self) { pt in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(Color(.label))
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 6)
                                        Text(pt)
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color(.label))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }

                    // Scripture References
                    if !draft.scriptureReferences.isEmpty {
                        sectionView(title: "Scriptures", icon: "book.fill") {
                            FlowLayoutPreview(items: draft.scriptureReferences) { ref in
                                Text(ref)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.purple.opacity(0.08), in: Capsule())
                            }
                        }
                    }

                    // Content / Summary
                    if !draft.content.isEmpty {
                        sectionView(title: "Summary", icon: "doc.text") {
                            Text(draft.content)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(.secondaryLabel))
                                .lineLimit(8)
                        }
                    }

                    // Source badge
                    HStack(spacing: 6) {
                        Image(systemName: source == .snap ? "camera.fill" : "mic.fill")
                            .font(.system(size: 11))
                        Text(source == .snap ? "Generated from image" : "Generated from recording")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.top, 4)
                }
                .padding(20)
            }

            // Error
            if let err = saveError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    saveNote()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("Save to Notes", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.label), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Save

    private func saveNote() {
        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else {
            saveError = "Not signed in."
            return
        }
        isSaving = true
        let updated = ChurchNote(
            userId:              uid,
            title:               editedTitle.isEmpty ? draft.title : editedTitle,
            date:                draft.date,
            content:             draft.content,
            keyPoints:           draft.keyPoints,
            tags:                draft.tags,
            scriptureReferences: draft.scriptureReferences
        )
        // Delegate Firestore write to caller via onSave
        isSaving = false
        onSave(updated)
    }

    // MARK: - Section helper

    @ViewBuilder
    private func sectionView<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.tertiaryLabel))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .textCase(.uppercase)
            }
            content()
        }
    }
}

// MARK: - FlowLayoutPreview (wrapping chip layout)

private struct FlowLayoutPreview<T: Hashable, Content: View>: View {
    let items: [T]
    let content: (T) -> Content

    var body: some View {
        // Simple horizontal wrap using lazy VStack + HStack
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
            }
        }
    }
}
