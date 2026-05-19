// AmenCaptionEditorView.swift
// AMENAPP
// Caption editor for media attachments.

import SwiftUI

struct AmenCaptionEditorView: View {
    @State private var caption: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(caption: String, onSave: @escaping (String) -> Void) {
        _caption = State(initialValue: caption)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Caption")
                    .font(.systemScaled(18, weight: .bold))
                TextEditor(text: $caption)
                    .frame(minHeight: 160)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                    .accessibilityLabel("Caption text")
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Caption")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onSave(caption)
                        dismiss()
                    }
                }
            }
        }
    }
}
