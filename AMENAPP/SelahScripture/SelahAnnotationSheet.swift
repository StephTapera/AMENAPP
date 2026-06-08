//
//  SelahAnnotationSheet.swift
//  AMENAPP
//
//  Bottom sheet for verse highlight, note, question, and prayer annotations.
//  Mirrors the SelahNote personal corpus type from selah.contracts.ts (FROZEN CONTRACT).
//
//  Design tokens from GLASS_TOKENS §2, §4, §8:
//   - Card fill: white, cornerRadius 28, card shadow
//   - Light glass material: .regularMaterial
//   - Highlight palette: cyan/amber/pink/lavender (§8) — exempt from color ban
//   - Text primary: Color(.label), secondary: Color(.secondaryLabel)
//
//  HARD LEGAL CONSTRAINT:
//  `translationRead` in SelahNoteData is for display ONLY and must NEVER be
//  passed to any AI engine, discernment check, CF, or Pinecone namespace.
//  Soft-delete only: onDelete sets deletedAt; hard-delete is forbidden per contract §3.
//

import SwiftUI

// MARK: - SelahAnnotationMode

/// Which kind of annotation the sheet is creating or editing.
/// Mirrors SelahNoteKind from SelahNoteModel.swift.
enum SelahAnnotationMode: String, CaseIterable {
    case highlight
    case note
    case question
    case prayer

    var displayTitle: String {
        switch self {
        case .highlight: return "Highlight"
        case .note:      return "Add Note"
        case .question:  return "Add Question"
        case .prayer:    return "Add Prayer"
        }
    }

    var placeholder: String {
        switch self {
        case .highlight: return ""
        case .note:      return "Write a study note…"
        case .question:  return "Write your question…"
        case .prayer:    return "Write your prayer…"
        }
    }

    var icon: String {
        switch self {
        case .highlight: return "highlighter"
        case .note:      return "note.text"
        case .question:  return "questionmark.circle"
        case .prayer:    return "hands.sparkles"
        }
    }

    /// Maps to SelahNoteKind rawValue
    var noteKind: String { rawValue }
}

// MARK: - SelahNoteData

/// Transfer object passed from SelahAnnotationSheet back to the reader.
/// translationRead: display only — NEVER passed to AI/CF/Pinecone.
struct SelahNoteData {
    let verseRef: String
    let translationRead: String   // display only per contract — never AI citation path
    let kind: String              // matches SelahNoteKind rawValue
    let color: String?            // hex from SelahHighlightColor palette, or nil
    let body: String?
}

// MARK: - SelahAnnotationSheet

struct SelahAnnotationSheet: View {

    // MARK: Inputs

    let verseRef: String
    let verseText: String
    let mode: SelahAnnotationMode
    let translationId: String
    let onSave: (SelahNoteData) -> Void
    let onDelete: ((String) -> Void)?
    var existingNote: SelahNote? = nil

    // MARK: State

    @State private var noteText: String = ""
    @State private var selectedColor: SelahHighlightColor = .cyan
    @Environment(\.dismiss) private var dismiss

    // MARK: Computed

    private var versePreview: String {
        verseText.count > 60
            ? String(verseText.prefix(60)) + "…"
            : verseText
    }

    // MARK: Init

    init(
        verseRef: String,
        verseText: String,
        mode: SelahAnnotationMode,
        translationId: String = "kjv",
        onSave: @escaping (SelahNoteData) -> Void,
        onDelete: ((String) -> Void)? = nil,
        existingNote: SelahNote? = nil
    ) {
        self.verseRef = verseRef
        self.verseText = verseText
        self.mode = mode
        self.translationId = translationId
        self.onSave = onSave
        self.onDelete = onDelete
        self.existingNote = existingNote

        // Pre-populate from existingNote if editing
        if let note = existingNote {
            _noteText = State(initialValue: note.body ?? "")
            if let colorHex = note.color,
               let matching = SelahHighlightColor.allCases.first(where: { $0.rawValue == colorHex }) {
                _selectedColor = State(initialValue: matching)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            dragIndicator

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    colorSwatches
                    if mode != .highlight {
                        textInputArea
                    }
                    actionButtons
                    if existingNote != nil && onDelete != nil {
                        deleteButton
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    // MARK: - Subviews

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                Text(mode.displayTitle)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(20))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            Text(verseRef)
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(Color(.label))

            Text(versePreview)
                .font(.systemScaled(14, design: .serif))
                .foregroundStyle(Color(.secondaryLabel))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var colorSwatches: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
                .tracking(0.5)

            HStack(spacing: 14) {
                ForEach(SelahHighlightColor.allCases, id: \.self) { color in
                    swatchButton(color: color)
                }
                Spacer()
            }
        }
    }

    private func swatchButton(color: SelahHighlightColor) -> some View {
        Button {
            selectedColor = color
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // For highlight mode, save immediately on color tap
            if mode == .highlight {
                saveAndDismiss()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(color.displayColor.opacity(4.0)) // solid fill for swatch visibility
                    .frame(width: 36, height: 36)
                if selectedColor == color {
                    Circle()
                        .strokeBorder(Color(.label).opacity(0.35), lineWidth: 2)
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.systemScaled(11, weight: .bold))
                        .foregroundStyle(Color(.label).opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(color.label) highlight color\(selectedColor == color ? ", selected" : "")")
    }

    @ViewBuilder
    private var textInputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .note ? "Note" : mode == .question ? "Question" : "Prayer")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color(.secondaryLabel))
                .tracking(0.5)

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text(mode.placeholder)
                        .font(.systemScaled(15))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.top, 12)
                        .padding(.horizontal, 14)
                }
                TextEditor(text: $noteText)
                    .font(.systemScaled(15))
                    .foregroundStyle(Color(.label))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if mode != .highlight {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")

                Button {
                    saveAndDismiss()
                } label: {
                    Text("Save")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.label).opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save \(mode.displayTitle)")
            }
        }
    }

    private var deleteButton: some View {
        Button {
            if let note = existingNote, let onDelete {
                onDelete(note.id)
                dismiss()
            }
        } label: {
            Text("Delete Note")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color(.systemRed))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemRed).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete Note")
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func saveAndDismiss() {
        let data = SelahNoteData(
            verseRef: verseRef,
            translationRead: translationId,
            kind: mode.noteKind,
            color: mode == .highlight ? selectedColor.rawValue : nil,
            body: mode == .highlight ? nil : (noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteText.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        onSave(data)
        dismiss()
    }
}

// MARK: - Highlight Background Modifier

/// Applies a verse highlight color background if a color hex is provided.
/// Uses `.background(Color(hex:).opacity(0.25))` per design tokens §8.
struct SelahVerseHighlightBackground: ViewModifier {
    let colorHex: String?

    func body(content: Content) -> some View {
        if let hex = colorHex,
           let color = SelahHighlightColor.allCases.first(where: { $0.rawValue == hex }) {
            content
                .background(
                    color.displayColor
                        .cornerRadius(8)
                )
        } else {
            content
        }
    }
}

extension View {
    func selahHighlight(colorHex: String?) -> some View {
        modifier(SelahVerseHighlightBackground(colorHex: colorHex))
    }
}
