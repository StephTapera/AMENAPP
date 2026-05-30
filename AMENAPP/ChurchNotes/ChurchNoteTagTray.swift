//
//  ChurchNoteTagTray.swift
//  AMENAPP
//
//  Theme tag chip tray with add/remove, wrapping, and content-based suggestions.
//  Reuses TagWrapLayout (defined in ChurchNotesEditor.swift).
//

import SwiftUI

struct ChurchNoteTagTray: View {

    @Binding var appliedTags: [String]
    var noteContent: String = ""

    @State private var newTagText: String = ""
    @State private var isAddingTag: Bool = false

    // MARK: - Suggested Tags

    private static let suggestedPool: [String] = [
        "Faith", "Grace", "Healing", "Waiting", "Forgiveness",
        "Worship", "Obedience", "Prayer", "Hope", "Community",
        "Stewardship", "Conviction", "Love", "Trust", "Purpose",
        "Joy", "Wisdom", "Comfort", "Identity", "Perseverance"
    ]

    /// Tags suggested based on keyword matching in note content.
    private var contentSuggestions: [String] {
        guard !noteContent.isEmpty else { return [] }
        let lower = noteContent.lowercased()
        return Self.suggestedPool.filter { tag in
            lower.contains(tag.lowercased()) && !appliedTags.contains(tag)
        }.prefix(5).map { $0 }
    }

    /// Tags from the pool that aren't applied and aren't content-suggested.
    private var remainingSuggestions: [String] {
        let suggested = Set(contentSuggestions)
        let applied = Set(appliedTags)
        return Self.suggestedPool.filter { tag in
            !applied.contains(tag) && !suggested.contains(tag)
        }.prefix(4).map { $0 }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Applied tags
            if !appliedTags.isEmpty {
                TagWrapLayout(spacing: 6) {
                    ForEach(appliedTags, id: \.self) { tag in
                        appliedChip(tag)
                    }
                }
                .animation(CNToken.Anim.chipInsert, value: appliedTags)
            }

            // Content-suggested tags
            if !contentSuggestions.isEmpty {
                TagWrapLayout(spacing: 6) {
                    ForEach(contentSuggestions, id: \.self) { tag in
                        suggestedChip(tag, isContentMatch: true)
                    }
                    ForEach(remainingSuggestions, id: \.self) { tag in
                        suggestedChip(tag, isContentMatch: false)
                    }
                }
                .animation(CNToken.Anim.chipInsert, value: contentSuggestions)
            } else if appliedTags.isEmpty {
                // Show some default suggestions when nothing is applied yet
                TagWrapLayout(spacing: 6) {
                    ForEach(Array(Self.suggestedPool.prefix(8)), id: \.self) { tag in
                        suggestedChip(tag, isContentMatch: false)
                    }
                }
            }

            // Inline add tag
            if isAddingTag {
                HStack(spacing: 6) {
                    TextField("Add tag…", text: $newTagText)
                        .font(.systemScaled(13, weight: .regular))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(.systemBackground).opacity(0.7))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                        )
                        .frame(maxWidth: 160)
                        .onSubmit {
                            addCustomTag()
                        }

                    Button {
                        addCustomTag()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(16, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isAddingTag = false
                        newTagText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(16, weight: .regular))
                            .foregroundStyle(.primary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                Button {
                    withAnimation(CNToken.Anim.chipInsert) {
                        isAddingTag = true
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.systemScaled(11, weight: .medium))
                        Text("Tag")
                            .font(.systemScaled(12, weight: .medium))
                    }
                    .foregroundStyle(.primary.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add custom tag")
            }
        }
    }

    // MARK: - Chips

    private func appliedChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.systemScaled(12, weight: .medium))
            Button {
                withAnimation(CNToken.Anim.chipInsert) {
                    appliedTags.removeAll { $0 == tag }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(8, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(tag) tag")
        }
        .foregroundStyle(.primary.opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(.systemBackground).opacity(0.85))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag) tag")
    }

    private func suggestedChip(_ tag: String, isContentMatch: Bool) -> some View {
        Button {
            withAnimation(CNToken.Anim.chipInsert) {
                appliedTags.append(tag)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.systemScaled(9, weight: .medium))
                Text(tag)
                    .font(.systemScaled(12, weight: .regular))
            }
            .foregroundStyle(.primary.opacity(isContentMatch ? 0.55 : 0.35))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .strokeBorder(
                        Color.primary.opacity(isContentMatch ? 0.12 : 0.06),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add tag: \(tag)")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Actions

    private func addCustomTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !appliedTags.contains(trimmed) else {
            isAddingTag = false
            newTagText = ""
            return
        }
        withAnimation(CNToken.Anim.chipInsert) {
            appliedTags.append(trimmed)
        }
        newTagText = ""
        isAddingTag = false
    }
}
