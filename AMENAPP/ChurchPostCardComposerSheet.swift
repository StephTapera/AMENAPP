// ChurchPostCardComposerSheet.swift
// AMENAPP
//
// Composer sheet for creating and publishing church PostCard drafts.
// Presented from the First Visit Companion and Enhanced Church Card.

import SwiftUI

struct ChurchPostCardComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let churchId: String?
    let churchName: String
    let initialType: ChurchPostCardType

    @State private var selectedType: ChurchPostCardType
    @State private var content: String
    @State private var isPublishing = false
    @State private var showSuccess = false

    init(churchId: String?, churchName: String, type: ChurchPostCardType) {
        self.churchId = churchId
        self.churchName = churchName
        self.initialType = type
        _selectedType = State(initialValue: type)
        _content = State(initialValue: type.templateContent(churchName: churchName))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Type selector
                    typeSelectorRow

                    // Church name badge
                    churchBadge

                    // Editable content
                    editorSection

                    // Preview
                    previewSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PostCard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") {
                        publish()
                    }
                    .fontWeight(.semibold)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing)
                }
            }
            .alert("PostCard Published!", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your \(selectedType.displayName.lowercased()) PostCard has been shared.")
            }
        }
    }

    // MARK: - Type Selector

    private var typeSelectorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TYPE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChurchPostCardType.allCases, id: \.self) { type in
                        Button {
                            withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedType = type
                                content = type.templateContent(churchName: churchName)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: type.icon)
                                    .font(.caption)
                                Text(type.displayName)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedType == type
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.secondarySystemGroupedBackground)
                            )
                            .foregroundStyle(selectedType == type ? Color.accentColor : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedType == type ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Church Badge

    private var churchBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "building.2")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(churchName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Editor

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTENT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            TextEditor(text: $content)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: selectedType.icon)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(selectedType.displayName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .kerning(0.4)
                }

                Text(content.isEmpty ? "Your message will appear here…" : content)
                    .font(.body)
                    .foregroundStyle(content.isEmpty ? .tertiary : .primary)
                    .lineSpacing(4)

                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(churchName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Publish

    private func publish() {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPublishing = true

        var draft = ChurchPostCardDraftService.shared.generateDraft(
            type: selectedType,
            churchId: churchId,
            churchName: churchName
        )
        draft.content = content
        ChurchPostCardDraftService.shared.publishDraft(draft)

        isPublishing = false
        showSuccess = true
    }
}
