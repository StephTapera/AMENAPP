// ChurchNoteReflectionReplayCard.swift
// AMENAPP
//
// Surfaced when a reflection replay is due (7, 30, or 90 days after note creation).
// Shows the original note's key content, asks a reflective question, and records
// the user's response and outcome.
//
// Design: warm, personal, uncluttered. Two layers visible:
// original note excerpt (dimmed) + reflection layer (foregrounded).
// Language: calm, pastoral, non-intrusive.

import SwiftUI

// MARK: - Replay Card View

struct ChurchNoteReflectionReplayCard: View {

    let reflection: ChurchNoteReflection
    let noteTitle: String
    let notePreviewText: String    // a short excerpt from the original note
    let onSave: (ChurchNoteReflection) -> Void
    let onDismiss: () -> Void

    @State private var responseText: String = ""
    @State private var selectedOutcome: CNReflectionOutcome?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    private var intervalLabel: String {
        switch reflection.replayIntervalDays {
        case 1:   return "Yesterday"
        case 7:   return "7 days ago"
        case 30:  return "A month ago"
        case 90:  return "3 months ago"
        default:  return "\(reflection.replayIntervalDays) days ago"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Original note reference
                    originalNoteSection
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    // Reflection question
                    questionSection
                        .padding(.horizontal, 16)

                    // Response input
                    responseSection
                        .padding(.horizontal, 16)

                    // Outcome selection
                    outcomeSection
                        .padding(.horizontal, 16)

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        onDismiss()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Text("Save reflection")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedOutcome == nil)
                }
            }
            .navigationTitle("Reflection")
        }
    }

    // MARK: - Original Note Reference

    private var originalNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("From \(intervalLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !noteTitle.isEmpty {
                    Text(noteTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                if !notePreviewText.isEmpty {
                    Text(notePreviewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .italic()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Reflection Question

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reflection.promptType.question)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(reflection.promptType.followUpPrompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Response Input

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your response")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ZStack(alignment: .topLeading) {
                if responseText.isEmpty {
                    Text("Write freely — this stays private.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $responseText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Outcome Selection

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mark where you are")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CNReflectionOutcome.allCases, id: \.self) { outcome in
                    outcomeChip(outcome)
                }
            }
        }
    }

    private func outcomeChip(_ outcome: CNReflectionOutcome) -> some View {
        let isSelected = selectedOutcome == outcome
        return Button {
            withAnimation(ChurchNotesAnimationTokens.chipInsert) {
                selectedOutcome = isSelected ? nil : outcome
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: outcome.icon)
                    .font(.systemScaled(16))
                    .foregroundStyle(isSelected
                                     ? (outcome.isPositive ? Color(.systemGreen) : Color.secondary)
                                     : Color(.tertiaryLabel))
                    .accessibilityHidden(true)
                Text(outcome.displayName)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? Color(.secondarySystemBackground)
                          : Color(.tertiarySystemFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? Color.primary.opacity(0.2) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(outcome.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Save

    private func save() {
        var updated = reflection
        updated.responseText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.outcome = selectedOutcome
        onSave(updated)
        dismiss()
    }
}

// MARK: - Replay Schedule Picker

/// Lets user choose when to be prompted to revisit a note.
struct CNReflectionSchedulePicker: View {

    @Binding var selectedIntervals: Set<Int>
    let onConfirm: () -> Void

    private let options: [(label: String, days: Int, sub: String)] = [
        ("Tomorrow", 1, "A quick check-in"),
        ("In 7 days", 7, "How did the week go?"),
        ("In 30 days", 30, "Did it stay with you?"),
        ("In 90 days", 90, "Did you see fruit?"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Revisit this note")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 4)

            Text("Choose when you'd like to reflect on this.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            VStack(spacing: 1) {
                ForEach(options, id: \.days) { option in
                    scheduleRow(option)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            Button(action: onConfirm) {
                Text(selectedIntervals.isEmpty ? "No reminder" : "Set reminder")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        selectedIntervals.isEmpty
                            ? Color(.tertiarySystemFill)
                            : Color.primary,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(
                        selectedIntervals.isEmpty ? Color.secondary : Color(.systemBackground)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func scheduleRow(_ option: (label: String, days: Int, sub: String)) -> some View {
        let isSelected = selectedIntervals.contains(option.days)
        return Button {
            withAnimation(ChurchNotesAnimationTokens.chipInsert) {
                if isSelected {
                    selectedIntervals.remove(option.days)
                } else {
                    selectedIntervals.insert(option.days)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(option.sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label): \(option.sub)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#if DEBUG
struct ChurchNoteReflectionReplayCard_Previews: PreviewProvider {
    static let sampleReflection = ChurchNoteReflection(
        noteId: "test",
        promptType: .boreAnyFruit,
        replayIntervalDays: 7
    )

    static var previews: some View {
        ChurchNoteReflectionReplayCard(
            reflection: sampleReflection,
            noteTitle: "Trust and Obedience",
            notePreviewText: "Faith isn't waiting for certainty — it's moving before you can see the full picture.",
            onSave: { _ in },
            onDismiss: {}
        )
        .previewDisplayName("Replay Card — 7 days")
    }
}
#endif
